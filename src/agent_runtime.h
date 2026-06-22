#ifndef LOGOS_AGENT_RUNTIME_H
#define LOGOS_AGENT_RUNTIME_H

#include "a2a_adapter.h"
#include "agent_state.h"
#include "messaging_adapter.h"
#include "policy_engine.h"
#include "program_adapter.h"
#include "skill_registry.h"
#include "storage_adapter.h"
#include "wallet_adapter.h"

#include <QJsonObject>
#include <QString>
#include <functional>

class LogosModules;

class AgentRuntime
{
public:
    using EventSink = std::function<void(const QString& eventName, const QJsonObject& payload)>;

    AgentRuntime();

    void setLogosModules(LogosModules* modules);
    void setPersistencePath(const QString& path);
    void setEventSink(EventSink sink);
    void wireDependencyEvents();

    QJsonObject init(const QString& configJson);
    QJsonObject start();
    QJsonObject stop();
    QJsonObject invoke(const QString& skillName, const QString& paramsJson, const QString& origin);
    QJsonObject invokeObject(const QString& skillName, const QJsonObject& params, const QString& origin);
    QJsonObject approve(const QString& approvalId, const QString& decisionJson);
    QJsonObject skills() const;
    QJsonObject status();

    AgentState& state();
    WalletAdapter& wallet();
    StorageAdapter& storage();
    MessagingAdapter& messaging();
    A2AAdapter& a2a();
    ProgramAdapter& program();
    PolicyEngine& policy();

private:
    void registerDefaultSkills();
    QJsonObject maybeGateSpend(const QString& skillName, const QString& amount, const QJsonObject& params, const QString& origin);
    QJsonObject executeSkill(const QString& skillName, const QJsonObject& params, const QString& origin);
    void emitEvent(const QString& name, const QJsonObject& payload);
    void recordAsyncAdapterResult(const QString& adapter, const QJsonObject& result);
    void handleOwnerMessage(const QJsonObject& payload);

    LogosModules* m_logos = nullptr;
    AgentState m_state;
    WalletAdapter m_wallet;
    StorageAdapter m_storage;
    MessagingAdapter m_messaging;
    A2AAdapter m_a2a;
    ProgramAdapter m_program;
    PolicyEngine m_policy;
    SkillRegistry m_skills;
    EventSink m_eventSink;
    bool m_initialized = false;
    bool m_started = false;
    bool m_eventsWired = false;
    bool m_starting = false;
    QJsonObject m_lastStartAdapters;
};

#endif
