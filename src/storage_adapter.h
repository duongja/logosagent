#ifndef LOGOS_AGENT_STORAGE_ADAPTER_H
#define LOGOS_AGENT_STORAGE_ADAPTER_H

#include <QJsonObject>
#include <QString>

class AgentState;
class LogosModules;

class StorageAdapter
{
public:
    void setLogosModules(LogosModules* modules);
    void setState(AgentState* state);

    void wireEvents();
    QJsonObject init(const QJsonObject& config);
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
};

#endif
