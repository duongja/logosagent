#include "messaging_adapter.h"

#include "agent_state.h"
#include "json_utils.h"
#include "logos_sdk.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
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

    m_logos->chat_module.on("chatNewMessage", [this](const QVariantList& data) {
        if (data.isEmpty()) {
            return;
        }
        QString err;
        const QJsonObject message = JsonUtils::parseObject(data.at(0).toString(), &err);
        if (message.isEmpty()) {
            return;
        }
        recordMessage(QJsonObject{
            {QStringLiteral("transport"), QStringLiteral("chat")},
            {QStringLiteral("direction"), QStringLiteral("in")},
            {QStringLiteral("payload"), message},
            {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        });
        if (m_inboundHandler) {
            m_inboundHandler(QStringLiteral("owner"), message);
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
}

QJsonObject MessagingAdapter::init(const QJsonObject& config)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("messaging.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }

    QJsonObject result;
    if (config.contains(QStringLiteral("chat"))) {
        result.insert(QStringLiteral("chat"), initChat(config.value(QStringLiteral("chat")).toObject()));
    }
    if (config.contains(QStringLiteral("delivery"))) {
        result.insert(QStringLiteral("delivery"), initDelivery(config.value(QStringLiteral("delivery")).toObject()));
    }
    return JsonUtils::ok(result);
}

QJsonObject MessagingAdapter::send(const QJsonObject& params)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("messaging.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    QString err;
    const QString recipient = JsonUtils::requireString(params, QStringLiteral("recipient"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("messaging.invalid_params"), err);
    }
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

    const QString contentHex = QString::fromLatin1(message.toUtf8().toHex());
    const bool ok = m_logos->chat_module.sendMessage(recipient, contentHex);
    if (!ok) {
        return JsonUtils::error(QStringLiteral("messaging.send_failed"), QStringLiteral("chat_module.sendMessage returned false"));
    }
    recordMessage(QJsonObject{
        {QStringLiteral("transport"), QStringLiteral("chat")},
        {QStringLiteral("direction"), QStringLiteral("out")},
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("message"), message},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    });
    return JsonUtils::ok(QJsonObject{{QStringLiteral("recipient"), recipient}});
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
    return QJsonObject{
        {QStringLiteral("chat_started"), m_chatStarted},
        {QStringLiteral("delivery_started"), m_deliveryStarted}
    };
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
    const QString cfgJson = JsonUtils::toString(chatCfg);
    if (!m_logos->chat_module.initChat(cfgJson)) {
        return JsonUtils::error(QStringLiteral("chat.init_failed"), QStringLiteral("chat_module.initChat returned false"));
    }
    m_logos->chat_module.setEventCallback();
    if (!m_logos->chat_module.startChat()) {
        return JsonUtils::error(QStringLiteral("chat.start_failed"), QStringLiteral("chat_module.startChat returned false"));
    }
    m_chatStarted = true;
    if (chatCfg.value(QStringLiteral("create_intro_bundle")).toBool(false)) {
        m_logos->chat_module.createIntroBundle();
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("started"), true}});
}

QJsonObject MessagingAdapter::initDelivery(const QJsonObject& deliveryCfg)
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
        return JsonUtils::error(QStringLiteral("delivery.create_failed"), created.getError());
    }
    LogosResult started = m_logos->delivery_module.start();
    if (!started.success) {
        return JsonUtils::error(QStringLiteral("delivery.start_failed"), started.getError());
    }
    m_deliveryStarted = true;
    return JsonUtils::ok(QJsonObject{{QStringLiteral("started"), true}, {QStringLiteral("config"), cfg}});
}

void MessagingAdapter::recordMessage(const QJsonObject& message)
{
    if (m_state) {
        m_state->addMessage(message);
        m_state->save();
    }
}
