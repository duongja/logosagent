#include "messaging_adapter.h"

#include "agent_state.h"
#include "json_utils.h"
#include "logos_sdk.h"
#include "owner_message_utils.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <utility>

void MessagingAdapter::setLogosModules(LogosModules* modules)
{
    m_logos = modules;
}

void MessagingAdapter::setState(AgentState* state)
{
    m_state = state;
}

void MessagingAdapter::setInboundHandler(InboundHandler handler)
{
    m_inboundHandler = std::move(handler);
}

void MessagingAdapter::wireEvents()
{
    if (!m_logos) {
        return;
    }

    m_logos->chat_module.on("message_received", [this](const QVariantList& data) {
        if (data.size() < 4) {
            return;
        }
        const QString conversationId = data.at(0).toString();
        const QJsonObject message{
            {QStringLiteral("conversation_id"), conversationId},
            {QStringLiteral("content"), data.at(1).toString()},
            {QStringLiteral("timestamp_ms"), data.at(2).toLongLong()},
            {QStringLiteral("sender"), data.at(3).toString()}
        };
        if (!conversationId.isEmpty()) {
            m_ownerConversationId = conversationId;
        }
        recordMessage(QJsonObject{
            {QStringLiteral("transport"), QStringLiteral("chat")},
            {QStringLiteral("direction"), QStringLiteral("in")},
            {QStringLiteral("payload"), message},
            {QStringLiteral("conversation_id"), conversationId},
            {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        });
        if (m_inboundHandler) {
            m_inboundHandler(QStringLiteral("owner"), message);
        }
    });

    m_logos->chat_module.on("conversation_created", [this](const QVariantList& data) {
        if (data.size() < 6) {
            return;
        }
        const QString conversationId = data.at(0).toString();
        if (!conversationId.isEmpty()) {
            m_ownerConversationId = conversationId;
        }
        recordMessage(QJsonObject{
            {QStringLiteral("transport"), QStringLiteral("chat")},
            {QStringLiteral("direction"), QStringLiteral("event")},
            {QStringLiteral("event"), QStringLiteral("conversation_created")},
            {QStringLiteral("conversation_id"), conversationId},
            {QStringLiteral("is_outgoing"), data.at(1).toBool()},
            {QStringLiteral("peer_label"), data.at(2).toString()},
            {QStringLiteral("kind"), data.at(3).toString()},
            {QStringLiteral("name"), data.at(4).toString()},
            {QStringLiteral("description"), data.at(5).toString()},
            {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        });
    });

    m_logos->chat_module.on("delivery_state_changed", [this](const QVariantList& data) {
        if (data.isEmpty()) {
            return;
        }
        const QString state = data.at(0).toString();
        const QString detail = data.size() > 1 ? data.at(1).toString() : QString();
        if (state.compare(QStringLiteral("connected"), Qt::CaseInsensitive) == 0) {
            m_chatStarted = true;
            m_chatLastError.clear();
        } else if (!detail.isEmpty()) {
            m_chatLastError = detail;
        }
    });

    m_logos->delivery_module.on("messageReceived", [this](const QVariantList& data) {
        if (data.size() < 4) {
            return;
        }
        const QString topic = data.at(1).toString();
        QByteArray payloadBytes = data.at(2).toByteArray();
        if (payloadBytes.isEmpty()) {
            payloadBytes = data.at(2).toString().toUtf8();
        }
        QString err;
        const QJsonObject payload = JsonUtils::parseObject(QString::fromUtf8(payloadBytes), &err);
        if (payload.isEmpty()) {
            return;
        }
        recordMessage(QJsonObject{
            {QStringLiteral("transport"), QStringLiteral("delivery")},
            {QStringLiteral("direction"), QStringLiteral("in")},
            {QStringLiteral("topic"), topic},
            {QStringLiteral("payload"), payload},
            {QStringLiteral("message_hash"), data.at(0).toString()},
            {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        });
        if (m_inboundHandler) {
            m_inboundHandler(topic, payload);
        }
    });

    m_logos->delivery_module.on("connectionStateChanged", [this](const QVariantList& data) {
        if (data.isEmpty()) {
            return;
        }
        recordDeliveryConnectionState(data.at(0).toString());
    });
}

QJsonObject MessagingAdapter::init(const QJsonObject& config)
{
    return init(config, false);
}

QJsonObject MessagingAdapter::init(const QJsonObject& config, bool asyncStart, StartCallback callback)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("messaging.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }

    QJsonObject result;
    if (config.contains(QStringLiteral("chat"))) {
        result.insert(QStringLiteral("chat"), initChat(config.value(QStringLiteral("chat")).toObject()));
    }
    if (config.contains(QStringLiteral("delivery"))) {
        result.insert(QStringLiteral("delivery"), initDelivery(config.value(QStringLiteral("delivery")).toObject(), asyncStart, callback));
    }
    return JsonUtils::ok(result);
}

QJsonObject MessagingAdapter::send(const QJsonObject& params)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("messaging.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    QString err;
    QString recipient = JsonUtils::requireString(params, QStringLiteral("recipient"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("messaging.invalid_params"), err);
    }
    const QString requestedRecipient = recipient;
    const QString message = params.value(QStringLiteral("message")).isObject()
        ? JsonUtils::toString(params.value(QStringLiteral("message")).toObject())
        : params.value(QStringLiteral("message")).toString();
    const QString transport = params.value(QStringLiteral("transport")).toString(QStringLiteral("chat"));

    if (transport == QStringLiteral("delivery")) {
        QString payloadErr;
        QJsonObject payload = JsonUtils::parseObject(message, &payloadErr);
        if (!payloadErr.isEmpty()) {
            payload = QJsonObject{{QStringLiteral("text"), message}};
        }
        return deliverySend(recipient, payload);
    }

    if (recipient == QStringLiteral("owner") || recipient == QStringLiteral("owner-chat")) {
        if (m_ownerConversationId.isEmpty()) {
            return JsonUtils::error(
                QStringLiteral("messaging.owner_conversation_missing"),
                QStringLiteral("recipient alias 'owner' requires an active owner Chat conversation"));
        }
        recipient = m_ownerConversationId;
    }

    const LogosResult sent = m_logos->chat_module.send_message(recipient, message);
    const bool accepted = sent.success;
    recordMessage(QJsonObject{
        {QStringLiteral("transport"), QStringLiteral("chat")},
        {QStringLiteral("direction"), QStringLiteral("out")},
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("requested_recipient"), requestedRecipient},
        {QStringLiteral("message"), message},
        {QStringLiteral("accepted_immediately"), accepted},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    });
    if (!accepted) {
        return JsonUtils::error(
            QStringLiteral("chat.send_failed"), sent.getError(),
            QJsonObject{
                {QStringLiteral("recipient"), recipient},
                {QStringLiteral("requested_recipient"), requestedRecipient}
            });
    }
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("accepted_immediately"), accepted},
        {QStringLiteral("note"), QStringLiteral("chat_module send_message completed")},
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("requested_recipient"), requestedRecipient}
    });
}

QJsonObject MessagingAdapter::join(const QJsonObject& params)
{
    QString err;
    const QString groupId = JsonUtils::requireString(params, QStringLiteral("group_id"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("messaging.invalid_params"), err);
    }
    const QJsonObject sub = deliverySubscribe(groupId);
    if (!sub.value(QStringLiteral("ok")).toBool()) {
        return sub;
    }
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("group_id"), groupId},
        {QStringLiteral("transport"), QStringLiteral("delivery_topic")},
        {QStringLiteral("note"), QStringLiteral("chat module group conversations are not exposed yet; delivery topics are used for group transport")}
    });
}

QJsonObject MessagingAdapter::createGroup(const QJsonObject& params)
{
    const QJsonArray members = params.value(QStringLiteral("members")).toArray();
    const QString groupId = params.value(QStringLiteral("group_id")).toString(
        QStringLiteral("/logos-agent/1/group-%1/json").arg(QDateTime::currentMSecsSinceEpoch()));
    QJsonObject joined = join(QJsonObject{{QStringLiteral("group_id"), groupId}});
    if (!joined.value(QStringLiteral("ok")).toBool()) {
        return joined;
    }
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("group_id"), groupId},
        {QStringLiteral("members"), members},
        {QStringLiteral("transport"), QStringLiteral("delivery_topic")}
    });
}

QJsonObject MessagingAdapter::status() const
{
    QJsonObject out{
        {QStringLiteral("chat_starting"), m_chatStarting},
        {QStringLiteral("chat_started"), m_chatStarted},
        {QStringLiteral("delivery_starting"), m_deliveryStarting},
        {QStringLiteral("delivery_started"), m_deliveryStarted},
        {QStringLiteral("delivery_connection_status"), m_deliveryConnectionStatus}
    };
    if (!m_chatLastError.isEmpty()) {
        out.insert(QStringLiteral("chat_last_error"), m_chatLastError);
    }
    if (!m_ownerConversationId.isEmpty()) {
        out.insert(QStringLiteral("owner_conversation_id"), m_ownerConversationId);
    }
    if (!m_chatAddress.isEmpty()) {
        out.insert(QStringLiteral("chat_address"), m_chatAddress);
        out.insert(QStringLiteral("chat_intro_bundle"), m_chatAddress);
    }
    if (!m_deliveryLastError.isEmpty()) {
        out.insert(QStringLiteral("delivery_last_error"), m_deliveryLastError);
    }
    return out;
}

QJsonObject MessagingAdapter::replyToOwner(const QJsonObject& inboundPayload, const QJsonObject& body)
{
    const QString conversationId = ownerConversationIdFromPayload(inboundPayload);
    if (conversationId.isEmpty()) {
        return JsonUtils::error(
            QStringLiteral("messaging.owner_conversation_missing"),
            QStringLiteral("owner chat event did not include a conversation id"));
    }
    m_ownerConversationId = conversationId;
    return send(QJsonObject{
        {QStringLiteral("recipient"), conversationId},
        {QStringLiteral("message"), body}
    });
}

QJsonObject MessagingAdapter::deliverySend(const QString& topic, const QJsonObject& payload)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("delivery.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    LogosResult sent = m_logos->delivery_module.send(topic, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    if (!sent.success) {
        return JsonUtils::error(QStringLiteral("delivery.send_failed"), sent.getError());
    }
    recordMessage(QJsonObject{
        {QStringLiteral("transport"), QStringLiteral("delivery")},
        {QStringLiteral("direction"), QStringLiteral("out")},
        {QStringLiteral("topic"), topic},
        {QStringLiteral("payload"), payload},
        {QStringLiteral("request_id"), sent.getString()},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    });
    return JsonUtils::ok(QJsonObject{{QStringLiteral("topic"), topic}, {QStringLiteral("request_id"), sent.getString()}});
}

QJsonObject MessagingAdapter::deliverySubscribe(const QString& topic)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("delivery.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    LogosResult sub = m_logos->delivery_module.subscribe(topic);
    if (!sub.success) {
        return JsonUtils::error(QStringLiteral("delivery.subscribe_failed"), sub.getError());
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("topic"), topic}});
}

QJsonObject MessagingAdapter::initChat(const QJsonObject& chatCfg)
{
    m_ownerConversationId = chatCfg.value(QStringLiteral("owner_conversation_id")).toString();
    const QString installationName = chatCfg.value(QStringLiteral("name")).toString();

    QJsonObject config;
    config.insert(
        QStringLiteral("delivery_preset"),
        chatCfg.value(QStringLiteral("delivery_preset")).toString(QStringLiteral("logos.dev")));
    QString logLevel = chatCfg.value(QStringLiteral("log_level")).toString();
    if (logLevel.isEmpty()) {
        logLevel = chatCfg.value(QStringLiteral("logLevel")).toString(QStringLiteral("INFO"));
    }
    config.insert(QStringLiteral("log_level"), logLevel.toLower());

    const LogosResult initialized = m_logos->chat_module.init(config.toVariantMap());
    if (!initialized.success) {
        m_chatStarting = false;
        m_chatStarted = false;
        m_chatLastError = initialized.getError();
        return JsonUtils::error(QStringLiteral("chat.init_failed"), m_chatLastError);
    }

    if (!installationName.isEmpty()) {
        const LogosResult named = m_logos->chat_module.set_installation_name(installationName);
        if (!named.success) {
            m_chatLastError = named.getError();
            return JsonUtils::error(QStringLiteral("chat.name_failed"), m_chatLastError);
        }
    }

    m_chatStarting = false;
    m_chatStarted = true;
    m_chatLastError.clear();
    m_chatAddress = m_logos->chat_module.get_address();
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("started"), true},
        {QStringLiteral("address"), m_chatAddress},
        {QStringLiteral("config"), config},
        {QStringLiteral("note"), QStringLiteral("Chat v0.2 initialized through the released LIDL interface")}
    });
}

QString MessagingAdapter::ownerConversationIdFromPayload(const QJsonObject& payload) const
{
    const QString direct = OwnerMessageUtils::ownerConversationId(payload);
    if (!direct.isEmpty()) {
        return direct;
    }
    return m_ownerConversationId;
}

QJsonObject MessagingAdapter::initDelivery(const QJsonObject& deliveryCfg, bool asyncStart, StartCallback callback)
{
    QJsonObject cfg = deliveryCfg;
    if (cfg.isEmpty()) {
        cfg = QJsonObject{
            {QStringLiteral("logLevel"), QStringLiteral("INFO")},
            {QStringLiteral("mode"), QStringLiteral("Core")},
            {QStringLiteral("preset"), QStringLiteral("logos.dev")}
        };
    }
    LogosResult created = m_logos->delivery_module.createNode(JsonUtils::toString(cfg));
    if (!created.success) {
        m_deliveryLastError = created.getError();
        return JsonUtils::error(QStringLiteral("delivery.create_failed"), created.getError());
    }
    m_deliveryStarting = true;
    m_deliveryStarted = false;
    m_deliveryConnectionStatus.clear();
    m_deliveryLastError.clear();
    if (asyncStart) {
        QTimer::singleShot(0, [this, cfg, callback]() {
            LogosResult started = m_logos->delivery_module.start();
            const bool eventConfirmedStart = m_deliveryStarted && m_deliveryLastError.isEmpty();
            const bool returnUnverifiedStart = !started.success && started.getError().isEmpty();
            m_deliveryStarting = false;
            m_deliveryStarted = started.success || eventConfirmedStart || returnUnverifiedStart;
            m_deliveryLastError = m_deliveryStarted ? QString() : started.getError();
            const QJsonObject result = m_deliveryStarted
                ? JsonUtils::ok(QJsonObject{
                    {QStringLiteral("started"), true},
                    {QStringLiteral("async"), true},
                    {QStringLiteral("return_unverified"), returnUnverifiedStart},
                    {QStringLiteral("connection_status"), m_deliveryConnectionStatus},
                    {QStringLiteral("config"), cfg}
                })
                : JsonUtils::error(QStringLiteral("delivery.start_failed"), m_deliveryLastError, QJsonObject{{QStringLiteral("async"), true}, {QStringLiteral("config"), cfg}});
            if (callback) {
                callback(result);
            }
        });
        return JsonUtils::ok(QJsonObject{
            {QStringLiteral("created"), true},
            {QStringLiteral("starting"), true},
            {QStringLiteral("async"), true},
            {QStringLiteral("config"), cfg}
        });
    }
    LogosResult started = m_logos->delivery_module.start();
    const bool eventConfirmedStart = m_deliveryStarted && m_deliveryLastError.isEmpty();
    const bool returnUnverifiedStart = !started.success && started.getError().isEmpty();
    if (!started.success && !eventConfirmedStart && !returnUnverifiedStart) {
        m_deliveryStarting = false;
        m_deliveryLastError = started.getError();
        return JsonUtils::error(QStringLiteral("delivery.start_failed"), started.getError());
    }
    m_deliveryStarting = false;
    m_deliveryStarted = true;
    m_deliveryLastError.clear();
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("started"), true},
        {QStringLiteral("return_unverified"), returnUnverifiedStart},
        {QStringLiteral("connection_status"), m_deliveryConnectionStatus},
        {QStringLiteral("config"), cfg}
    });
}

void MessagingAdapter::recordMessage(const QJsonObject& message)
{
    if (m_state) {
        m_state->addMessage(message);
        m_state->save();
    }
}

void MessagingAdapter::recordDeliveryConnectionState(const QString& status)
{
    m_deliveryConnectionStatus = status;
    if (status == QStringLiteral("Connected") || status == QStringLiteral("PartiallyConnected")) {
        m_deliveryStarting = false;
        m_deliveryStarted = true;
        m_deliveryLastError.clear();
    }
}
