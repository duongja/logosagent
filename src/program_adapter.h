#ifndef LOGOS_AGENT_PROGRAM_ADAPTER_H
#define LOGOS_AGENT_PROGRAM_ADAPTER_H

#include <QJsonObject>
#include <QString>

class AgentState;

class ProgramAdapter
{
public:
    void setState(AgentState* state);

    QJsonObject query(const QJsonObject& params);
    QJsonObject call(const QJsonObject& params);
    QJsonObject deploy(const QJsonObject& params);

private:
    QJsonObject runHelper(const QString& command, const QJsonObject& params);
    QString helperPath() const;

    AgentState* m_state = nullptr;
};

#endif
