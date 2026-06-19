#ifndef LOGOS_AGENT_PLUGIN_H
#define LOGOS_AGENT_PLUGIN_H

#include <QObject>
#include <QString>
#include <QVariantList>

#include "logos_agent_interface.h"
#include "agent_runtime.h"
#include "logos_api.h"
#include "logos_sdk.h"
#include "module_config.h"

class LogosAgentPlugin : public QObject, public LogosAgentInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID LogosAgentInterface_iid FILE "metadata.json")
    Q_INTERFACES(LogosAgentInterface PluginInterface)

public:
    explicit LogosAgentPlugin(QObject* parent = nullptr);
    ~LogosAgentPlugin() override;

    QString name() const override { return MODULE_NAME; }
    QString version() const override { return MODULE_VERSION; }

    Q_INVOKABLE void initLogos(LogosAPI* logosAPIInstance);

    Q_INVOKABLE QString init(const QString& configJson) override;
    Q_INVOKABLE QString start() override;
    Q_INVOKABLE QString stop() override;
    Q_INVOKABLE QString invoke(const QString& skillName, const QString& paramsJson) override;
    Q_INVOKABLE QString approve(const QString& approvalId, const QString& decisionJson) override;
    Q_INVOKABLE QString skills() override;
    Q_INVOKABLE QString status() override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    void wireEvents();
    QString persistencePathFromApi() const;
    void emitAgentEvent(const QString& eventName, const QJsonObject& payload);

    LogosAPI* m_logosAPI = nullptr;
    LogosModules* m_logos = nullptr;
    AgentRuntime m_runtime;
};

#endif
