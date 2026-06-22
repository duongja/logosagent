#include "agent_runtime.h"

#include "crypto_utils.h"
#include "json_utils.h"
#include "owner_message_utils.h"

#include <QDateTime>
#include <QJsonArray>
#include <utility>

namespace {

QJsonObject schema(std::initializer_list<QString> required)
{
    QJsonArray req;
    for (const QString& item : required) {
        req.append(item);
    }
    return QJsonObject{
        {QStringLiteral("type"), QStringLiteral("object")},
        {QStringLiteral("required"), req}
    };
}

QString amountFromParams(const QJsonObject& params)
{
    return params.value(QStringLiteral("amount")).toVariant().toString();
}

QJsonObject redactSecretFields(QJsonObject obj)
{
    obj.remove(QStringLiteral("private_key_hex"));
    obj.remove(QStringLiteral("key_hex"));
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        if (it.value().isObject()) {
            it.value() = redactSecretFields(it.value().toObject());
        } else if (it.value().isArray()) {
            QJsonArray arr = it.value().toArray();
            for (int i = 0; i < arr.size(); ++i) {
                if (arr.at(i).isObject()) {
                    arr[i] = redactSecretFields(arr.at(i).toObject());
                }
            }
            it.value() = arr;
        }
    }
    return obj;
}

} // namespace

AgentRuntime::AgentRuntime()
    : m_policy(&m_state)
{
    m_wallet.setState(&m_state);
    m_storage.setState(&m_state);
    m_messaging.setState(&m_state);
    m_program.setState(&m_state);
    m_a2a.setState(&m_state);
    m_a2a.setMessaging(&m_messaging);
    m_a2a.setWallet(&m_wallet);
    m_a2a.setTaskExecutor([this](const QString& skill, const QJsonObject& params, const QString& origin) {
        return invokeObject(skill, params, origin);
    });
    m_messaging.setInboundHandler([this](const QString& channel, const QJsonObject& payload) {
        if (channel == QStringLiteral("owner")) {
            handleOwnerMessage(payload);
        } else {
            m_a2a.handleInbound(channel, payload);
        }
    });
    registerDefaultSkills();
}

void AgentRuntime::setLogosModules(LogosModules* modules)
{
    m_logos = modules;
    m_eventsWired = false;
    m_wallet.setLogosModules(modules);
    m_storage.setLogosModules(modules);
    m_messaging.setLogosModules(modules);
}

void AgentRuntime::setPersistencePath(const QString& path)
{
    m_state.setPersistencePath(path);
}

void AgentRuntime::setEventSink(EventSink sink)
{
    m_eventSink = std::move(sink);
}

void AgentRuntime::wireDependencyEvents()
{
    if (!m_logos || m_eventsWired) {
        return;
    }
    m_storage.wireEvents();
    m_messaging.wireEvents();
    m_eventsWired = true;
}

QJsonObject AgentRuntime::init(const QString& configJson)
{
    QString err;
    const QJsonObject config = JsonUtils::parseObject(configJson.isEmpty() ? QStringLiteral("{}") : configJson, &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("agent.invalid_config"), err);
    }
    if (!m_state.load(&err)) {
        return JsonUtils::error(QStringLiteral("agent.state_load_failed"), err);
    }

    QJsonObject nextConfig = config;
    if (!nextConfig.contains(QStringLiteral("policy"))) {
        nextConfig.insert(QStringLiteral("policy"), QJsonObject{
            {QStringLiteral("per_transaction_limit"), QStringLiteral("0")},
            {QStringLiteral("period_limit"), QStringLiteral("0")},
            {QStringLiteral("period_seconds"), 86400}
        });
    }
    if (!nextConfig.contains(QStringLiteral("identity"))) {
        nextConfig.insert(QStringLiteral("identity"), QJsonObject{
            {QStringLiteral("agent_id"), CryptoUtils::randomId(QStringLiteral("agent"))}
        });
    }
    QJsonObject identity = nextConfig.value(QStringLiteral("identity")).toObject();
    if (!identity.value(QStringLiteral("signing")).isObject()) {
        QString keyErr;
        const QJsonObject signing = CryptoUtils::generateEd25519KeyPair(&keyErr);
        if (!keyErr.isEmpty()) {
            return JsonUtils::error(QStringLiteral("agent.identity_key_failed"), keyErr);
        }
        identity.insert(QStringLiteral("signing"), signing);
        nextConfig.insert(QStringLiteral("identity"), identity);
    }
    if (!identity.value(QStringLiteral("encryption")).isObject()) {
        QString keyErr;
        const QJsonObject encryption = CryptoUtils::generateX25519KeyPair(&keyErr);
        if (!keyErr.isEmpty()) {
            return JsonUtils::error(QStringLiteral("agent.identity_key_failed"), keyErr);
        }
        identity.insert(QStringLiteral("encryption"), encryption);
        nextConfig.insert(QStringLiteral("identity"), identity);
    }
    if (!nextConfig.contains(QStringLiteral("a2a_secret"))) {
        nextConfig.insert(QStringLiteral("a2a_secret"), QString());
    }
    if (!nextConfig.contains(QStringLiteral("security"))) {
        nextConfig.insert(QStringLiteral("security"), QJsonObject{
            {QStringLiteral("allow_dev_file_cipher"), false},
            {QStringLiteral("allow_dev_a2a_secret"), false}
        });
    }
    m_state.setConfig(nextConfig);
    if (!m_state.save(&err)) {
        return JsonUtils::error(QStringLiteral("agent.state_save_failed"), err);
    }
    m_initialized = true;
    emitEvent(QStringLiteral("agentInitialized"), QJsonObject{{QStringLiteral("persistence_path"), m_state.persistencePath()}});
    return JsonUtils::ok(QJsonObject{{QStringLiteral("persistence_path"), m_state.persistencePath()}});
}

QJsonObject AgentRuntime::start()
{
    if (!m_initialized) {
        QString err;
        if (!m_state.load(&err)) {
            return JsonUtils::error(QStringLiteral("agent.state_load_failed"), err);
        }
        m_initialized = true;
    }
    wireDependencyEvents();
    const QJsonObject config = m_state.config();
    const bool asyncStart = config.value(QStringLiteral("runtime")).toObject().value(QStringLiteral("async_start")).toBool(false);
    QJsonObject adapters;
    m_starting = true;
    adapters.insert(QStringLiteral("wallet"), m_wallet.init(config));
    adapters.insert(QStringLiteral("storage"), m_storage.init(config, asyncStart, [this](const QJsonObject& result) {
        recordAsyncAdapterResult(QStringLiteral("storage"), result);
    }));
    adapters.insert(QStringLiteral("messaging"), m_messaging.init(config, asyncStart, [this](const QJsonObject& result) {
        recordAsyncAdapterResult(QStringLiteral("messaging.delivery"), result);
    }));
    if (!asyncStart && config.contains(QStringLiteral("a2a")) && config.contains(QStringLiteral("delivery"))) {
        adapters.insert(QStringLiteral("a2a"), m_a2a.start());
    } else if (asyncStart && config.contains(QStringLiteral("a2a")) && config.contains(QStringLiteral("delivery"))) {
        adapters.insert(QStringLiteral("a2a"), JsonUtils::ok(QJsonObject{
            {QStringLiteral("starting"), true},
            {QStringLiteral("async"), true},
            {QStringLiteral("note"), QStringLiteral("A2A task subscription is deferred until Delivery startup is complete")}
        }));
    }
    m_lastStartAdapters = adapters;
    m_started = true;
    m_starting = asyncStart;
    emitEvent(QStringLiteral("agentStarted"), adapters);

    if (!asyncStart && config.value(QStringLiteral("a2a")).toObject().value(QStringLiteral("publish_on_start")).toBool(false)) {
        adapters.insert(QStringLiteral("a2a_publish"), m_a2a.publishCard());
    }

    return JsonUtils::ok(QJsonObject{{QStringLiteral("adapters"), adapters}, {QStringLiteral("async_start"), asyncStart}});
}

QJsonObject AgentRuntime::stop()
{
    QString err;
    m_state.save(&err);
    m_started = false;
    emitEvent(QStringLiteral("agentStopped"), QJsonObject{});
    return err.isEmpty()
        ? JsonUtils::ok(QJsonObject{{QStringLiteral("stopped"), true}})
        : JsonUtils::error(QStringLiteral("agent.state_save_failed"), err);
}

QJsonObject AgentRuntime::invoke(const QString& skillName, const QString& paramsJson, const QString& origin)
{
    QString err;
    const QJsonObject params = JsonUtils::parseObject(paramsJson.isEmpty() ? QStringLiteral("{}") : paramsJson, &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("agent.invalid_params"), err);
    }
    return invokeObject(skillName, params, origin);
}

QJsonObject AgentRuntime::invokeObject(const QString& skillName, const QJsonObject& params, const QString& origin)
{
    if (!m_skills.contains(skillName)) {
        return JsonUtils::error(QStringLiteral("agent.unknown_skill"), QStringLiteral("unknown skill: %1").arg(skillName));
    }
    const SkillDefinition def = m_skills.definition(skillName);
    if (def.spendsTokens) {
        const QString amount = amountFromParams(params);
        const QJsonObject gate = maybeGateSpend(skillName, amount.isEmpty() ? QStringLiteral("0") : amount, params, origin);
        if (gate.value(QStringLiteral("requires_approval")).toBool(false)) {
            return JsonUtils::ok(gate);
        }
    }
    return executeSkill(skillName, params, origin);
}

QJsonObject AgentRuntime::approve(const QString& approvalId, const QString& decisionJson)
{
    QString err;
    const QJsonObject decision = JsonUtils::parseObject(decisionJson.isEmpty() ? QStringLiteral("{}") : decisionJson, &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("agent.invalid_decision"), err);
    }
    QJsonObject approval = m_state.approvalById(approvalId);
    if (approval.isEmpty()) {
        return JsonUtils::error(QStringLiteral("agent.approval_not_found"), QStringLiteral("approval not found"));
    }
    if (approval.value(QStringLiteral("status")).toString() != QStringLiteral("pending")) {
        return JsonUtils::error(QStringLiteral("agent.approval_not_pending"), QStringLiteral("approval is not pending"));
    }

    const bool approved = decision.value(QStringLiteral("approved")).toBool(false);
    QJsonObject patch{
        {QStringLiteral("status"), approved ? QStringLiteral("approved") : QStringLiteral("rejected")},
        {QStringLiteral("decided_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("decision"), decision}
    };
    m_state.updateApproval(approvalId, patch);
    m_state.save();
    if (!approved) {
        emitEvent(QStringLiteral("approvalRejected"), patch);
        return JsonUtils::ok(QJsonObject{{QStringLiteral("approval_id"), approvalId}, {QStringLiteral("status"), QStringLiteral("rejected")}});
    }

    const QJsonObject request = approval.value(QStringLiteral("request")).toObject();
    const QString skill = approval.value(QStringLiteral("skill")).toString();
    const QJsonObject result = executeSkill(skill, request, QStringLiteral("owner-approval"));
    emitEvent(QStringLiteral("approvalExecuted"), QJsonObject{{QStringLiteral("approval_id"), approvalId}, {QStringLiteral("result"), result}});
    return result;
}

QJsonObject AgentRuntime::skills() const
{
    return JsonUtils::ok(QJsonObject{{QStringLiteral("skills"), m_skills.describe()}});
}

QJsonObject AgentRuntime::status()
{
    QJsonObject status{
        {QStringLiteral("initialized"), m_initialized},
        {QStringLiteral("started"), m_started},
        {QStringLiteral("starting"), m_starting},
        {QStringLiteral("persistence_path"), m_state.persistencePath()},
        {QStringLiteral("identity"), redactSecretFields(m_state.identity())},
        {QStringLiteral("policy"), m_state.policy()},
        {QStringLiteral("messaging"), m_messaging.status()},
        {QStringLiteral("storage"), m_storage.status()},
        {QStringLiteral("startup_adapters"), m_lastStartAdapters},
        {QStringLiteral("pending_approvals"), m_state.approvals()},
        {QStringLiteral("active_tasks"), m_state.tasks()}
    };
    const QJsonObject balance = m_wallet.balance();
    if (balance.value(QStringLiteral("ok")).toBool(false)) {
        status.insert(QStringLiteral("wallet"), balance);
    }
    return JsonUtils::ok(status);
}

void AgentRuntime::recordAsyncAdapterResult(const QString& adapter, const QJsonObject& result)
{
    m_lastStartAdapters.insert(adapter, result);
    bool anyStarting = false;
    const QJsonObject storageStatus = m_storage.status();
    const QJsonObject messagingStatus = m_messaging.status();
    anyStarting = storageStatus.value(QStringLiteral("starting")).toBool(false)
        || messagingStatus.value(QStringLiteral("chat_starting")).toBool(false)
        || messagingStatus.value(QStringLiteral("delivery_starting")).toBool(false);
    m_starting = anyStarting;
    emitEvent(QStringLiteral("agentAdapterStarted"), QJsonObject{
        {QStringLiteral("adapter"), adapter},
        {QStringLiteral("result"), result},
        {QStringLiteral("starting"), m_starting}
    });

    const QJsonObject config = m_state.config();
    if (adapter == QStringLiteral("messaging.delivery")
        && result.value(QStringLiteral("ok")).toBool(false)
        && config.contains(QStringLiteral("a2a"))
        && config.contains(QStringLiteral("delivery"))) {
        const QJsonObject a2aResult = m_a2a.start();
        m_lastStartAdapters.insert(QStringLiteral("a2a"), a2aResult);
        emitEvent(QStringLiteral("agentAdapterStarted"), QJsonObject{
            {QStringLiteral("adapter"), QStringLiteral("a2a")},
            {QStringLiteral("result"), a2aResult},
            {QStringLiteral("starting"), m_starting}
        });
        if (config.value(QStringLiteral("a2a")).toObject().value(QStringLiteral("publish_on_start")).toBool(false)) {
            const QJsonObject publishResult = m_a2a.publishCard();
            m_lastStartAdapters.insert(QStringLiteral("a2a_publish"), publishResult);
            emitEvent(QStringLiteral("agentAdapterStarted"), QJsonObject{
                {QStringLiteral("adapter"), QStringLiteral("a2a_publish")},
                {QStringLiteral("result"), publishResult},
                {QStringLiteral("starting"), m_starting}
            });
        }
    }
}

AgentState& AgentRuntime::state() { return m_state; }
WalletAdapter& AgentRuntime::wallet() { return m_wallet; }
StorageAdapter& AgentRuntime::storage() { return m_storage; }
MessagingAdapter& AgentRuntime::messaging() { return m_messaging; }
A2AAdapter& AgentRuntime::a2a() { return m_a2a; }
ProgramAdapter& AgentRuntime::program() { return m_program; }
PolicyEngine& AgentRuntime::policy() { return m_policy; }

void AgentRuntime::registerDefaultSkills()
{
    auto add = [this](SkillDefinition def) { m_skills.registerSkill(std::move(def)); };

    add({QStringLiteral("storage.upload"), QStringLiteral("storage"), QStringLiteral("Encrypt and upload a local file to Logos Storage."), schema({QStringLiteral("path")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.storage().upload(p); }});
    add({QStringLiteral("storage.download"), QStringLiteral("storage"), QStringLiteral("Retrieve and decrypt a stored file."), schema({QStringLiteral("address"), QStringLiteral("path")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.storage().download(p); }});
    add({QStringLiteral("storage.list"), QStringLiteral("storage"), QStringLiteral("List files the agent has stored."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject&, const QString&) { return rt.storage().list(); }});
    add({QStringLiteral("storage.share"), QStringLiteral("storage"), QStringLiteral("Create a share payload for another Logos identity."), schema({QStringLiteral("address"), QStringLiteral("recipient")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.storage().share(p); }});

    add({QStringLiteral("messaging.send"), QStringLiteral("messaging"), QStringLiteral("Send a message to a Logos chat conversation or Delivery topic."), schema({QStringLiteral("recipient"), QStringLiteral("message")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.messaging().send(p); }});
    add({QStringLiteral("messaging.join"), QStringLiteral("messaging"), QStringLiteral("Join a Delivery-backed group topic."), schema({QStringLiteral("group_id")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.messaging().join(p); }});
    add({QStringLiteral("messaging.create_group"), QStringLiteral("messaging"), QStringLiteral("Create a Delivery-backed group topic."), schema({QStringLiteral("members")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.messaging().createGroup(p); }});

    add({QStringLiteral("wallet.balance"), QStringLiteral("wallet"), QStringLiteral("Return shielded token balance."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject&, const QString&) { return rt.wallet().balance(); }});
    add({QStringLiteral("wallet.send"), QStringLiteral("wallet"), QStringLiteral("Send LEZ tokens subject to spending policy."), schema({QStringLiteral("recipient"), QStringLiteral("amount")}), {}, QStringLiteral("0"), true,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.wallet().send(p); }});
    add({QStringLiteral("wallet.history"), QStringLiteral("wallet"), QStringLiteral("Return recent locally observed transactions."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject&, const QString&) { return rt.wallet().history(); }});

    add({QStringLiteral("program.query"), QStringLiteral("program"), QStringLiteral("Query LEZ program or chain state through agent_lez helper."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.program().query(p); }});
    add({QStringLiteral("program.call"), QStringLiteral("program"), QStringLiteral("Call a LEZ wallet facade or program-specific runner subject to spending policy."), schema({}), {}, QStringLiteral("0"), true,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.program().call(p); }});
    add({QStringLiteral("program.deploy"), QStringLiteral("program"), QStringLiteral("Deploy a compiled LEZ program binary subject to spending policy."), schema({QStringLiteral("binary_path")}), {}, QStringLiteral("0"), true,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.program().deploy(p); }});

    add({QStringLiteral("agent.card"), QStringLiteral("agent"), QStringLiteral("Return signed A2A-compatible Agent Card."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject&, const QString&) { return rt.a2a().card(); }});
    add({QStringLiteral("agent.discover"), QStringLiteral("agent"), QStringLiteral("Subscribe to an A2A discovery topic and return cached cards."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.a2a().discover(p); }});
    add({QStringLiteral("agent.task"), QStringLiteral("agent"), QStringLiteral("Send an A2A task request and optional LEZ payment."), schema({QStringLiteral("agent_address"), QStringLiteral("skill")}), {}, QStringLiteral("0"), true,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.a2a().task(p); }});
    add({QStringLiteral("agent.subscribe"), QStringLiteral("agent"), QStringLiteral("Subscribe to A2A task status updates."), schema({QStringLiteral("task_id")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.a2a().subscribe(p); }});
    add({QStringLiteral("agent.cancel"), QStringLiteral("agent"), QStringLiteral("Cancel an in-progress A2A task."), schema({QStringLiteral("agent_address"), QStringLiteral("task_id")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) { return rt.a2a().cancel(p); }});

    add({QStringLiteral("meta.skills"), QStringLiteral("meta"), QStringLiteral("List all skills."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject&, const QString&) { return rt.skills(); }});
    add({QStringLiteral("meta.status"), QStringLiteral("meta"), QStringLiteral("Return runtime status."), schema({}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject&, const QString&) { return rt.status(); }});
    add({QStringLiteral("meta.configure"), QStringLiteral("meta"), QStringLiteral("Update runtime configuration."), schema({QStringLiteral("key"), QStringLiteral("value")}), {}, QStringLiteral("0"), false,
         [](AgentRuntime& rt, const QJsonObject& p, const QString&) {
             const QString key = p.value(QStringLiteral("key")).toString();
             QJsonObject cfg = rt.state().config();
             cfg.insert(key, p.value(QStringLiteral("value")));
             rt.state().setConfig(cfg);
             rt.state().save();
             return JsonUtils::ok(QJsonObject{{QStringLiteral("config"), rt.state().config()}});
         }});
}

QJsonObject AgentRuntime::maybeGateSpend(const QString& skillName, const QString& amount, const QJsonObject& params, const QString& origin)
{
    const QJsonObject check = m_policy.checkSpend(skillName, amount, params);
    if (!check.value(QStringLiteral("requires_approval")).toBool(false)) {
        return check;
    }
    QJsonObject approval = m_policy.createApproval(skillName, amount, params);
    approval.insert(QStringLiteral("origin"), origin);
    m_state.addApproval(approval);
    m_state.save();
    emitEvent(QStringLiteral("approvalRequired"), approval);
    return QJsonObject{
        {QStringLiteral("requires_approval"), true},
        {QStringLiteral("approval_id"), approval.value(QStringLiteral("approval_id")).toString()},
        {QStringLiteral("approval"), approval},
        {QStringLiteral("policy"), check}
    };
}

QJsonObject AgentRuntime::executeSkill(const QString& skillName, const QJsonObject& params, const QString& origin)
{
    const SkillDefinition def = m_skills.definition(skillName);
    QJsonObject result = def.handler(*this, params, origin);
    emitEvent(QStringLiteral("skillCompleted"), QJsonObject{
        {QStringLiteral("skill"), skillName},
        {QStringLiteral("origin"), origin},
        {QStringLiteral("params"), params},
        {QStringLiteral("result"), result}
    });
    return result;
}

void AgentRuntime::emitEvent(const QString& name, const QJsonObject& payload)
{
    if (m_eventSink) {
        m_eventSink(name, payload);
    }
}

void AgentRuntime::handleOwnerMessage(const QJsonObject& payload)
{
    QString err;
    const QJsonObject message = OwnerMessageUtils::normalizeOwnerMessage(payload, &err);
    if (message.isEmpty()) {
        emitEvent(QStringLiteral("ownerMessageRejected"), QJsonObject{
            {QStringLiteral("error"), err},
            {QStringLiteral("payload"), payload}
        });
        return;
    }

    if (message.contains(QStringLiteral("skill"))) {
        const QString skill = message.value(QStringLiteral("skill")).toString();
        const QJsonObject params = message.value(QStringLiteral("params")).toObject();
        QJsonObject result = invokeObject(skill, params, QStringLiteral("owner-chat"));
        emitEvent(QStringLiteral("ownerSkillResult"), QJsonObject{
            {QStringLiteral("request"), message},
            {QStringLiteral("raw_payload"), payload},
            {QStringLiteral("result"), result}
        });
    }
    if (message.contains(QStringLiteral("approval_id"))) {
        QJsonObject decision = message;
        approve(message.value(QStringLiteral("approval_id")).toString(), JsonUtils::toString(decision));
    }
}
