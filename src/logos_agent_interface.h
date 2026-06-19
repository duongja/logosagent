#ifndef LOGOS_AGENT_INTERFACE_H
#define LOGOS_AGENT_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

class LogosAgentInterface : public PluginInterface
{
public:
    virtual ~LogosAgentInterface() = default;

    /**
     * Initialize the agent runtime. The JSON config may contain wallet paths,
     * owner chat configuration, delivery settings, storage settings, policy
     * limits, and agent card metadata.
     */
    Q_INVOKABLE virtual QString init(const QString& configJson) = 0;

    /** Start configured Logos adapters and resume durable pending work. */
    Q_INVOKABLE virtual QString start() = 0;

    /** Stop long-running adapters and persist runtime state. */
    Q_INVOKABLE virtual QString stop() = 0;

    /** Invoke a skill by name with a JSON object of parameters. */
    Q_INVOKABLE virtual QString invoke(const QString& skillName, const QString& paramsJson) = 0;

    /** Approve or reject a pending above-threshold action. */
    Q_INVOKABLE virtual QString approve(const QString& approvalId, const QString& decisionJson) = 0;

    /** List all registered skills and schemas. */
    Q_INVOKABLE virtual QString skills() = 0;

    /** Return current agent status, balance summary, and pending queues. */
    Q_INVOKABLE virtual QString status() = 0;
};

#define LogosAgentInterface_iid "org.logos.LogosAgentInterface"
Q_DECLARE_INTERFACE(LogosAgentInterface, LogosAgentInterface_iid)

#endif
