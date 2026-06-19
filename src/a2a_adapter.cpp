#include "a2a_adapter.h"

#include "agent_state.h"
#include "crypto_utils.h"
#include "json_utils.h"
#include "messaging_adapter.h"
#include "wallet_adapter.h"

#include <QDateTime>
#include <QJsonArray>
#include <utility>

namespace {

QString topicHash(const QString& value, const QString& fallback)
{
    const QString source = value.isEmpty() ? fallback : value;
    return CryptoUtils::sha256Hex(source.toUtf8()).left(32);
}

QString valueAsString(const QJsonValue& value)
{
    if (value.isString()) {
        return value.toString();
    }
    if (value.isDouble()) {
        return QString::number(static_cast<qulonglong>(value.toDouble()));
    }
    return {};
}

} // namespace

void A2AAdapter::setState(AgentState* state)
{
    m_state = state;
}

void A2AAdapter::setMessaging(MessagingAdapter* messaging)
{
    m_messaging = messaging;
}

void A2AAdapter::setWallet(WalletAdapter* wallet)
{
    m_wallet = wallet;
}

void A2AAdapter::setTaskExecutor(TaskExecutor executor)
{
    m_taskExecutor = std::move(executor);
}

QJsonObject A2AAdapter::card() const
{
    if (!m_state) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("state is not initialized"));
    }
    const QJsonObject config = m_state->config();
    const QJsonObject identity = m_state->identity();
    const QJsonObject cardCfg = config.value(QStringLiteral("agent_card")).toObject();
    const QString name = cardCfg.value(QStringLiteral("name")).toString(QStringLiteral("Logos Agent"));
    const QString agentAddress = identity.value(QStringLiteral("messaging_address")).toString(
        identity.value(QStringLiteral("lez_account")).toString());

    QJsonArray skills;
    const QJsonArray configured = cardCfg.value(QStringLiteral("skills")).toArray();
    if (!configured.isEmpty()) {
        skills = configured;
    } else {
        skills = QJsonArray{
            QJsonObject{{QStringLiteral("id"), QStringLiteral("storage.upload")}, {QStringLiteral("name"), QStringLiteral("Storage Upload")}},
            QJsonObject{{QStringLiteral("id"), QStringLiteral("messaging.send")}, {QStringLiteral("name"), QStringLiteral("Message Send")}},
            QJsonObject{{QStringLiteral("id"), QStringLiteral("wallet.balance")}, {QStringLiteral("name"), QStringLiteral("Wallet Balance")}}
        };
    }

    QJsonObject securitySchemes{
        {QStringLiteral("logos-ed25519"), QJsonObject{
            {QStringLiteral("type"), QStringLiteral("mutualTLS")},
            {QStringLiteral("description"), QStringLiteral("A2A envelope signatures bound to this Agent Card's Logos Ed25519 public key.")}
        }}
    };
    const QJsonObject signing = signingIdentity();
    const QJsonObject encryption = identity.value(QStringLiteral("encryption")).toObject();
    const QString publicKey = signing.value(QStringLiteral("public_key_hex")).toString();
    const QString keyId = signing.value(QStringLiteral("key_id")).toString();

    QJsonObject card{
        {QStringLiteral("protocolVersion"), QStringLiteral("1.0")},
        {QStringLiteral("name"), name},
        {QStringLiteral("description"), cardCfg.value(QStringLiteral("description")).toString(QStringLiteral("Logos-native autonomous agent"))},
        {QStringLiteral("url"), QStringLiteral("logosmsg://%1").arg(agentAddress)},
        {QStringLiteral("preferredTransport"), QStringLiteral("logos-messaging")},
        {QStringLiteral("version"), cardCfg.value(QStringLiteral("version")).toString(QStringLiteral("0.1.0"))},
        {QStringLiteral("capabilities"), QJsonObject{
            {QStringLiteral("streaming"), true},
            {QStringLiteral("pushNotifications"), false},
            {QStringLiteral("stateTransitionHistory"), true}
        }},
        {QStringLiteral("defaultInputModes"), QJsonArray{QStringLiteral("application/json"), QStringLiteral("text/plain")}},
        {QStringLiteral("defaultOutputModes"), QJsonArray{QStringLiteral("application/json"), QStringLiteral("text/plain")}},
        {QStringLiteral("skills"), skills},
        {QStringLiteral("securitySchemes"), securitySchemes},
        {QStringLiteral("security"), QJsonArray{QJsonObject{{QStringLiteral("logos-ed25519"), QJsonArray{}}}}},
        {QStringLiteral("logos"), QJsonObject{
            {QStringLiteral("agent_address"), agentAddress},
            {QStringLiteral("lez_account"), identity.value(QStringLiteral("lez_account")).toString()},
            {QStringLiteral("signing_key_id"), keyId},
            {QStringLiteral("signing_public_key"), publicKey},
            {QStringLiteral("encryption_key_id"), encryption.value(QStringLiteral("key_id")).toString()},
            {QStringLiteral("encryption_public_key"), encryption.value(QStringLiteral("public_key_hex")).toString()},
            {QStringLiteral("task_topic"), taskTopic(agentAddress)},
            {QStringLiteral("discovery_topic"), discoveryTopic()},
            {QStringLiteral("payment"), cardCfg.value(QStringLiteral("payment")).toObject()}
        }}
    };
    QJsonObject signedCard = card;
    QString signErr;
    const QString signature = CryptoUtils::signObjectEd25519(card, signing.value(QStringLiteral("private_key_hex")).toString(), &signErr);
    if (signErr.isEmpty() && !signature.isEmpty()) {
        signedCard.insert(QStringLiteral("signature"), signature);
        signedCard.insert(QStringLiteral("signature_alg"), QStringLiteral("ed25519"));
        signedCard.insert(QStringLiteral("signature_key_id"), keyId);
    } else {
        signedCard.insert(QStringLiteral("signature"), QString());
        signedCard.insert(QStringLiteral("signature_status"), signErr.isEmpty() ? QStringLiteral("not_configured") : signErr);
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("card"), signedCard}});
}

QJsonObject A2AAdapter::publishCard()
{
    if (!m_messaging) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("messaging adapter is not initialized"));
    }
    const QJsonObject cardResult = card();
    if (!cardResult.value(QStringLiteral("ok")).toBool()) {
        return cardResult;
    }
    return m_messaging->deliverySend(discoveryTopic(), envelope(QStringLiteral("agent.card"), cardResult.value(QStringLiteral("card")).toObject()));
}

QJsonObject A2AAdapter::start()
{
    if (!m_messaging || !m_state) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("A2A adapter is not initialized"));
    }
    const QJsonObject identity = m_state->identity();
    const QString agentAddress = identity.value(QStringLiteral("messaging_address")).toString(
        identity.value(QStringLiteral("lez_account")).toString(identity.value(QStringLiteral("agent_id")).toString()));
    if (agentAddress.isEmpty()) {
        return JsonUtils::error(QStringLiteral("a2a.identity_missing"), QStringLiteral("identity.agent_id, messaging_address, or lez_account is required"));
    }
    return m_messaging->deliverySubscribe(taskTopic(agentAddress));
}

QJsonObject A2AAdapter::discover(const QJsonObject& params)
{
    if (!m_messaging || !m_state) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("A2A adapter is not initialized"));
    }
    const QString topic = discoveryTopic(params);
    const QJsonObject sub = m_messaging->deliverySubscribe(topic);
    if (!sub.value(QStringLiteral("ok")).toBool()) {
        return sub;
    }
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("topic"), topic},
        {QStringLiteral("agents"), m_state->discoveredAgents()},
        {QStringLiteral("note"), QStringLiteral("discovery is live pub/sub; call again after cards are received")}
    });
}

QJsonObject A2AAdapter::task(const QJsonObject& params)
{
    if (!m_messaging || !m_state) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("A2A adapter is not initialized"));
    }
    const QString agentAddress = params.value(QStringLiteral("agent_address")).toString();
    const QString skill = params.value(QStringLiteral("skill")).toString();
    if (agentAddress.isEmpty() || skill.isEmpty()) {
        return JsonUtils::error(QStringLiteral("a2a.invalid_params"), QStringLiteral("agent_address and skill are required"));
    }
    const QString amount = valueAsString(params.value(QStringLiteral("amount")));
    QJsonObject payment;
    if (amountIsPositive(amount)) {
        payment = payForTask(params);
        if (!payment.value(QStringLiteral("ok")).toBool(false)) {
            return payment;
        }
    }
    const QString taskId = params.value(QStringLiteral("task_id")).toString(CryptoUtils::randomId(QStringLiteral("task")));
    QJsonObject task{
        {QStringLiteral("task_id"), taskId},
        {QStringLiteral("context_id"), params.value(QStringLiteral("context_id")).toString(CryptoUtils::randomId(QStringLiteral("ctx")))},
        {QStringLiteral("agent_address"), agentAddress},
        {QStringLiteral("skill"), skill},
        {QStringLiteral("params"), params.value(QStringLiteral("params")).toObject()},
        {QStringLiteral("state"), QStringLiteral("TASK_STATE_SUBMITTED")},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    };
    if (!payment.isEmpty()) {
        task.insert(QStringLiteral("payment"), payment);
    }
    m_state->upsertTask(task);
    m_state->save();

    const QJsonObject sent = m_messaging->deliverySend(taskTopic(agentAddress), envelope(QStringLiteral("task.submit"), task));
    if (!sent.value(QStringLiteral("ok")).toBool()) {
        return sent;
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("task"), task}, {QStringLiteral("transport"), sent}});
}

QJsonObject A2AAdapter::subscribe(const QJsonObject& params)
{
    if (!m_messaging) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("messaging adapter is not initialized"));
    }
    const QString taskId = params.value(QStringLiteral("task_id")).toString();
    if (taskId.isEmpty()) {
        return JsonUtils::error(QStringLiteral("a2a.invalid_params"), QStringLiteral("task_id is required"));
    }
    return m_messaging->deliverySubscribe(statusTopic(taskId));
}

QJsonObject A2AAdapter::cancel(const QJsonObject& params)
{
    if (!m_messaging || !m_state) {
        return JsonUtils::error(QStringLiteral("a2a.unavailable"), QStringLiteral("A2A adapter is not initialized"));
    }
    const QString agentAddress = params.value(QStringLiteral("agent_address")).toString();
    const QString taskId = params.value(QStringLiteral("task_id")).toString();
    if (agentAddress.isEmpty() || taskId.isEmpty()) {
        return JsonUtils::error(QStringLiteral("a2a.invalid_params"), QStringLiteral("agent_address and task_id are required"));
    }
    QJsonObject cancel{
        {QStringLiteral("task_id"), taskId},
        {QStringLiteral("state"), QStringLiteral("TASK_STATE_CANCELED")},
        {QStringLiteral("reason"), params.value(QStringLiteral("reason")).toString()},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    };
    m_state->upsertTask(cancel);
    m_state->save();
    return m_messaging->deliverySend(taskTopic(agentAddress), envelope(QStringLiteral("task.cancel"), cancel));
}

void A2AAdapter::handleInbound(const QString& topic, const QJsonObject& payload)
{
    if (!m_state || !verifyEnvelope(payload) || !rememberEnvelopeNonce(payload)) {
        return;
    }
    const QString kind = payload.value(QStringLiteral("kind")).toString();
    const QJsonObject body = payload.value(QStringLiteral("payload")).toObject();
    if (kind == QStringLiteral("agent.card")) {
        m_state->upsertDiscoveredAgent(body);
        m_state->save();
        return;
    }
    if (kind.startsWith(QStringLiteral("task."))) {
        if (kind == QStringLiteral("task.submit") && !isTaskSubmitAddressedToSelf(topic, body)) {
            return;
        }
        if (kind == QStringLiteral("task.cancel") && !isTaskTopicForSelf(topic)) {
            return;
        }
        QJsonObject task = body;
        if (kind == QStringLiteral("task.cancel")) {
            const QJsonObject stored = m_state->taskById(task.value(QStringLiteral("task_id")).toString());
            if (!stored.isEmpty()) {
                const QJsonObject refund = refundForCanceledTask(stored);
                if (!refund.isEmpty()) {
                    task.insert(QStringLiteral("refund"), refund);
                }
            }
        }
        if (!task.contains(QStringLiteral("state"))) {
            task.insert(QStringLiteral("state"), kind == QStringLiteral("task.cancel") ? QStringLiteral("TASK_STATE_CANCELED") : QStringLiteral("TASK_STATE_WORKING"));
        }
        task.insert(QStringLiteral("last_topic"), topic);
        task.insert(QStringLiteral("updated_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        const QJsonObject payment = task.value(QStringLiteral("payment")).toObject();
        if (!payment.isEmpty()) {
            QJsonObject receipt = payment;
            receipt.insert(QStringLiteral("type"), QStringLiteral("a2a.task.payment.received"));
            receipt.insert(QStringLiteral("task_id"), task.value(QStringLiteral("task_id")).toString());
            receipt.insert(QStringLiteral("received_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
            m_state->addTransaction(receipt);
        }
        m_state->upsertTask(task);
        m_state->save();
        if (kind == QStringLiteral("task.submit")) {
            executeSubmittedTask(topic, task);
        }
    }
}

QString A2AAdapter::discoveryTopic(const QJsonObject& params) const
{
    if (params.contains(QStringLiteral("topic"))) {
        return params.value(QStringLiteral("topic")).toString();
    }
    if (m_state) {
        const QString configured = m_state->config().value(QStringLiteral("a2a")).toObject()
            .value(QStringLiteral("discovery_topic")).toString();
        if (!configured.isEmpty()) {
            return configured;
        }
    }
    return QStringLiteral("/logos-agent/1/discovery/json");
}

QString A2AAdapter::taskTopic(const QString& address) const
{
    return QStringLiteral("/logos-agent/1/task-%1/json").arg(topicHash(address, QStringLiteral("unknown-agent")));
}

QString A2AAdapter::statusTopic(const QString& taskId) const
{
    return QStringLiteral("/logos-agent/1/status-%1/json").arg(topicHash(taskId, QStringLiteral("unknown-task")));
}

QString A2AAdapter::localAgentAddress() const
{
    if (!m_state) {
        return {};
    }
    const QJsonObject identity = m_state->identity();
    return identity.value(QStringLiteral("messaging_address")).toString(
        identity.value(QStringLiteral("lez_account")).toString(
            identity.value(QStringLiteral("agent_id")).toString()));
}

bool A2AAdapter::isTaskTopicForSelf(const QString& topic) const
{
    const QString address = localAgentAddress();
    return !address.isEmpty() && topic == taskTopic(address);
}

bool A2AAdapter::isTaskSubmitAddressedToSelf(const QString& topic, const QJsonObject& task) const
{
    const QString address = localAgentAddress();
    if (address.isEmpty() || topic != taskTopic(address)) {
        return false;
    }
    return task.value(QStringLiteral("agent_address")).toString() == address;
}

bool A2AAdapter::amountIsPositive(const QString& amount) const
{
    bool ok = false;
    const qulonglong value = amount.trimmed().toULongLong(&ok);
    return ok && value > 0;
}

QString A2AAdapter::paymentRecipientFromParams(const QJsonObject& params) const
{
    const QString explicitRecipient = params.value(QStringLiteral("payment_recipient")).toString();
    if (!explicitRecipient.isEmpty()) {
        return explicitRecipient;
    }
    const QJsonObject payment = params.value(QStringLiteral("payment")).toObject();
    const QString paymentRecipient = payment.value(QStringLiteral("recipient")).toString();
    if (!paymentRecipient.isEmpty()) {
        return paymentRecipient;
    }
    const QString agentAddress = params.value(QStringLiteral("agent_address")).toString();
    if (!m_state || agentAddress.isEmpty()) {
        return {};
    }
    const QJsonArray agents = m_state->discoveredAgents();
    for (const QJsonValue& value : agents) {
        const QJsonObject card = value.toObject();
        const QJsonObject logos = card.value(QStringLiteral("logos")).toObject();
        if (logos.value(QStringLiteral("agent_address")).toString() == agentAddress) {
            const QString lezAccount = logos.value(QStringLiteral("lez_account")).toString();
            if (!lezAccount.isEmpty()) {
                return lezAccount;
            }
        }
    }
    return {};
}

QString A2AAdapter::paymentModeFromParams(const QJsonObject& params) const
{
    const QString mode = params.value(QStringLiteral("payment_mode")).toString();
    if (!mode.isEmpty()) {
        return mode;
    }
    return params.value(QStringLiteral("payment")).toObject().value(QStringLiteral("mode")).toString(QStringLiteral("public"));
}

QJsonObject A2AAdapter::payForTask(const QJsonObject& params)
{
    if (!m_wallet) {
        return JsonUtils::error(QStringLiteral("a2a.payment_unavailable"), QStringLiteral("wallet adapter is not initialized"));
    }
    const QString amount = valueAsString(params.value(QStringLiteral("amount")));
    const QString recipient = paymentRecipientFromParams(params);
    if (recipient.isEmpty()) {
        return JsonUtils::error(QStringLiteral("a2a.payment_recipient_missing"), QStringLiteral("payment_recipient or discovered peer logos.lez_account is required for paid A2A tasks"));
    }

    const QJsonObject transfer = m_wallet->send(QJsonObject{
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("mode"), paymentModeFromParams(params)}
    });
    if (!transfer.value(QStringLiteral("ok")).toBool(false)) {
        return transfer;
    }
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("amount"), amount},
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("payer"), m_state ? m_state->identity().value(QStringLiteral("lez_account")).toString() : QString()},
        {QStringLiteral("mode"), paymentModeFromParams(params)},
        {QStringLiteral("paid_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("transfer"), transfer}
    });
}

QJsonObject A2AAdapter::refundForCanceledTask(const QJsonObject& task)
{
    const QJsonObject payment = task.value(QStringLiteral("payment")).toObject();
    if (payment.isEmpty()) {
        return {};
    }
    const QString amount = valueAsString(payment.value(QStringLiteral("amount")));
    if (!amountIsPositive(amount)) {
        return {};
    }
    const QString payer = payment.value(QStringLiteral("payer")).toString();
    if (payer.isEmpty()) {
        return JsonUtils::error(
            QStringLiteral("a2a.refund_payer_missing"),
            QStringLiteral("paid task did not include a payer address"));
    }
    if (!m_wallet) {
        return JsonUtils::error(QStringLiteral("a2a.refund_unavailable"), QStringLiteral("wallet adapter is not initialized"));
    }

    const QString mode = payment.value(QStringLiteral("refund_mode")).toString(
        payment.value(QStringLiteral("mode")).toString(QStringLiteral("public")));
    const QJsonObject transfer = m_wallet->send(QJsonObject{
        {QStringLiteral("recipient"), payer},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("mode"), mode}
    });
    QJsonObject refund{
        {QStringLiteral("ok"), transfer.value(QStringLiteral("ok")).toBool(false)},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("recipient"), payer},
        {QStringLiteral("mode"), mode},
        {QStringLiteral("refunded_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("transfer"), transfer}
    };
    if (m_state) {
        QJsonObject receipt = refund;
        receipt.insert(QStringLiteral("type"), QStringLiteral("a2a.task.payment.refund"));
        receipt.insert(QStringLiteral("task_id"), task.value(QStringLiteral("task_id")).toString());
        receipt.insert(QStringLiteral("spending_controlled"), true);
        receipt.insert(QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        m_state->addTransaction(receipt);
    }
    return refund;
}

QJsonObject A2AAdapter::signingIdentity() const
{
    if (!m_state) {
        return {};
    }
    return m_state->identity().value(QStringLiteral("signing")).toObject();
}

QJsonObject A2AAdapter::envelope(const QString& kind, QJsonObject payload) const
{
    const QJsonObject signing = signingIdentity();
    QJsonObject env{
        {QStringLiteral("logos_agent_protocol"), QStringLiteral("a2a-logos-messaging-binding")},
        {QStringLiteral("version"), QStringLiteral("0.1.0")},
        {QStringLiteral("kind"), kind},
        {QStringLiteral("payload"), payload},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("nonce"), CryptoUtils::randomId(QStringLiteral("msg"))},
        {QStringLiteral("signature_alg"), QStringLiteral("ed25519")},
        {QStringLiteral("signature_key_id"), signing.value(QStringLiteral("key_id")).toString()},
        {QStringLiteral("signer_public_key"), signing.value(QStringLiteral("public_key_hex")).toString()}
    };
    QString signErr;
    const QString signature = CryptoUtils::signObjectEd25519(env, signing.value(QStringLiteral("private_key_hex")).toString(), &signErr);
    if (signErr.isEmpty() && !signature.isEmpty()) {
        env.insert(QStringLiteral("signature"), signature);
    } else {
        env.insert(QStringLiteral("signature"), QString());
        env.insert(QStringLiteral("signature_status"), signErr);
    }
    return env;
}

QJsonObject A2AAdapter::statusEnvelopePayload(const QJsonObject& task, const QString& state, const QJsonObject& result) const
{
    QJsonObject status{
        {QStringLiteral("task_id"), task.value(QStringLiteral("task_id")).toString()},
        {QStringLiteral("context_id"), task.value(QStringLiteral("context_id")).toString()},
        {QStringLiteral("agent_address"), task.value(QStringLiteral("agent_address")).toString()},
        {QStringLiteral("skill"), task.value(QStringLiteral("skill")).toString()},
        {QStringLiteral("state"), state},
        {QStringLiteral("updated_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    };
    if (!result.isEmpty()) {
        status.insert(QStringLiteral("result"), result);
    }
    return status;
}

void A2AAdapter::executeSubmittedTask(const QString&, const QJsonObject& task)
{
    if (!m_state || !m_messaging) {
        return;
    }
    const QString taskId = task.value(QStringLiteral("task_id")).toString();
    const QString skill = task.value(QStringLiteral("skill")).toString();
    if (taskId.isEmpty() || skill.isEmpty()) {
        return;
    }

    const QJsonObject working = statusEnvelopePayload(task, QStringLiteral("TASK_STATE_WORKING"));
    m_state->upsertTask(working);
    m_state->save();
    m_messaging->deliverySend(statusTopic(taskId), envelope(QStringLiteral("task.status"), working));

    QJsonObject result;
    if (m_taskExecutor) {
        result = m_taskExecutor(skill, task.value(QStringLiteral("params")).toObject(), QStringLiteral("a2a-task"));
    } else {
        result = JsonUtils::error(QStringLiteral("a2a.executor_missing"), QStringLiteral("A2A task executor is not configured"));
    }

    QString finalState = QStringLiteral("TASK_STATE_COMPLETED");
    if (result.value(QStringLiteral("requires_approval")).toBool(false)) {
        finalState = QStringLiteral("TASK_STATE_INPUT_REQUIRED");
    } else if (!result.value(QStringLiteral("ok")).toBool(false)) {
        finalState = QStringLiteral("TASK_STATE_FAILED");
    }

    const QJsonObject completed = statusEnvelopePayload(task, finalState, result);
    m_state->upsertTask(completed);
    m_state->save();
    QString finalKind = QStringLiteral("task.failed");
    if (finalState == QStringLiteral("TASK_STATE_COMPLETED")) {
        finalKind = QStringLiteral("task.completed");
    } else if (finalState == QStringLiteral("TASK_STATE_INPUT_REQUIRED")) {
        finalKind = QStringLiteral("task.input-required");
    }
    m_messaging->deliverySend(statusTopic(taskId), envelope(finalKind, completed));
}

bool A2AAdapter::verifyEnvelope(const QJsonObject& envelope) const
{
    const QString signature = envelope.value(QStringLiteral("signature")).toString();
    const QString signatureAlg = envelope.value(QStringLiteral("signature_alg")).toString(QStringLiteral("ed25519"));
    if (signatureAlg == QStringLiteral("ed25519")) {
        const QString publicKey = envelope.value(QStringLiteral("signer_public_key")).toString();
        const QString keyId = envelope.value(QStringLiteral("signature_key_id")).toString();
        if (signature.isEmpty() || publicKey.isEmpty()) {
            return false;
        }
        if (!keyId.isEmpty() && CryptoUtils::ed25519KeyId(publicKey) != keyId) {
            return false;
        }
        return CryptoUtils::verifyObjectSignatureEd25519(envelope, publicKey, signature);
    }

    const QJsonObject config = m_state ? m_state->config() : QJsonObject{};
    const QString secret = config.value(QStringLiteral("a2a_secret")).toString();
    const bool allowDevSecret = config.value(QStringLiteral("security")).toObject()
        .value(QStringLiteral("allow_dev_a2a_secret")).toBool(false);
    if (signatureAlg != QStringLiteral("logos-hmac-dev") || secret.isEmpty() || !allowDevSecret) {
        return false;
    }
    return CryptoUtils::verifyObjectSignature(envelope, secret, signature);
}

bool A2AAdapter::rememberEnvelopeNonce(const QJsonObject& envelope)
{
    if (!m_state) {
        return false;
    }
    const QString publicKey = envelope.value(QStringLiteral("signer_public_key")).toString();
    const QString keyId = envelope.value(QStringLiteral("signature_key_id")).toString(
        publicKey.isEmpty() ? QStringLiteral("legacy-hmac") : CryptoUtils::ed25519KeyId(publicKey));
    const QString nonce = envelope.value(QStringLiteral("nonce")).toString();
    if (keyId.isEmpty() || nonce.isEmpty()) {
        return false;
    }
    if (m_state->hasReplayNonce(keyId, nonce)) {
        return false;
    }
    m_state->addReplayNonce(keyId, nonce, envelope.value(QStringLiteral("created_at")).toString());
    return true;
}
