#include "logos_agent_plugin.h"

#include "json_utils.h"

#include <QDebug>
#include <QDir>
#include <QStandardPaths>

LogosAgentPlugin::LogosAgentPlugin(QObject* parent)
    : QObject(parent)
{
}

LogosAgentPlugin::~LogosAgentPlugin()
{
    m_runtime.stop();
    delete m_logos;
}

void LogosAgentPlugin::initLogos(LogosAPI* logosAPIInstance)
{
    if (m_logos) {
        delete m_logos;
        m_logos = nullptr;
    }
    logosAPI = logosAPIInstance;
    m_logosAPI = logosAPIInstance;
    if (m_logosAPI) {
        m_logos = new LogosModules(m_logosAPI);
        m_runtime.setLogosModules(m_logos);
        m_runtime.setPersistencePath(persistencePathFromApi());
        m_runtime.setEventSink([this](const QString& eventName, const QJsonObject& payload) {
            emitAgentEvent(eventName, payload);
        });
        wireEvents();
    }
}

QString LogosAgentPlugin::init(const QString& configJson)
{
    return JsonUtils::toString(m_runtime.init(configJson));
}

QString LogosAgentPlugin::start()
{
    return JsonUtils::toString(m_runtime.start());
}

QString LogosAgentPlugin::stop()
{
    return JsonUtils::toString(m_runtime.stop());
}

QString LogosAgentPlugin::invoke(const QString& skillName, const QString& paramsJson)
{
    return JsonUtils::toString(m_runtime.invoke(skillName, paramsJson, QStringLiteral("module")));
}

QString LogosAgentPlugin::approve(const QString& approvalId, const QString& decisionJson)
{
    return JsonUtils::toString(m_runtime.approve(approvalId, decisionJson));
}

QString LogosAgentPlugin::skills()
{
    return JsonUtils::toString(m_runtime.skills());
}

QString LogosAgentPlugin::status()
{
    return JsonUtils::toString(m_runtime.status());
}

void LogosAgentPlugin::wireEvents()
{
    if (!m_logos) {
        return;
    }
    m_runtime.wireDependencyEvents();
}

QString LogosAgentPlugin::persistencePathFromApi() const
{
    if (m_logosAPI) {
        const QString path = m_logosAPI->property("instancePersistencePath").toString();
        if (!path.isEmpty()) {
            QDir().mkpath(path);
            return path;
        }
    }

    QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (base.isEmpty()) {
        base = QDir::homePath() + QStringLiteral("/.local/share/logos-agent");
    }
    QDir().mkpath(base);
    return base;
}

void LogosAgentPlugin::emitAgentEvent(const QString& eventName, const QJsonObject& payload)
{
    emit eventResponse(eventName, QVariantList() << JsonUtils::toString(payload));
}
