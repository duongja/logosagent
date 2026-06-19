#ifndef LOGOS_AGENT_POLICY_ENGINE_H
#define LOGOS_AGENT_POLICY_ENGINE_H

#include <QJsonObject>
#include <QString>

class AgentState;

class PolicyEngine
{
public:
    explicit PolicyEngine(AgentState* state = nullptr);
    void setState(AgentState* state);

    QJsonObject checkSpend(const QString& skillName, const QString& amount, const QJsonObject& request) const;
    QJsonObject createApproval(const QString& skillName, const QString& amount, const QJsonObject& request) const;

private:
    QString perTxLimit() const;
    QString periodLimit() const;
    QString spentThisPeriod() const;

    AgentState* m_state = nullptr;
};

#endif
