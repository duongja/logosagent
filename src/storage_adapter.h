#ifndef LOGOS_AGENT_STORAGE_ADAPTER_H
#define LOGOS_AGENT_STORAGE_ADAPTER_H

#include <QJsonObject>
#include <QString>
#include <functional>

class AgentState;
class LogosModules;

class StorageAdapter
{
public:
    using StartCallback = std::function<void(const QJsonObject& result)>;

    void setLogosModules(LogosModules* modules);
    void setState(AgentState* state);

    void wireEvents();
    QJsonObject init(const QJsonObject& config);
    QJsonObject init(const QJsonObject& config, bool asyncStart, StartCallback callback = {});
    QJsonObject status() const;
    QJsonObject upload(const QJsonObject& params);
    QJsonObject download(const QJsonObject& params);
    QJsonObject list() const;
    QJsonObject share(const QJsonObject& params);

private:
    QString tempPath(const QString& suffix) const;
    QJsonObject publicFileEntry(const QJsonObject& file) const;
    QString recipientEncryptionPublicKey(const QJsonObject& params) const;

    LogosModules* m_logos = nullptr;
    AgentState* m_state = nullptr;
    bool m_configured = false;
    bool m_starting = false;
    bool m_started = false;
    QString m_lastError;
};

#endif
