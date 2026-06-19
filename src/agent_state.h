#ifndef LOGOS_AGENT_STATE_H
#define LOGOS_AGENT_STATE_H

#include <QJsonArray>
#include <QJsonObject>
#include <QMutex>
#include <QString>

class AgentState
{
public:
    void setPersistencePath(const QString& path);
    QString persistencePath() const;
    QString stateFilePath() const;

    bool load(QString* errorMessage = nullptr);
    bool save(QString* errorMessage = nullptr) const;

    QJsonObject config() const;
    void setConfig(const QJsonObject& config);
    QJsonObject policy() const;
    QJsonObject identity() const;

    QJsonArray files() const;
    void addFile(const QJsonObject& file);
    bool updateFileByAddress(const QString& address, const QJsonObject& patch);
    QJsonObject fileByAddress(const QString& address) const;

    QJsonArray transactions() const;
    void addTransaction(const QJsonObject& tx);

    QJsonArray approvals() const;
    void addApproval(const QJsonObject& approval);
    bool updateApproval(const QString& approvalId, const QJsonObject& patch);
    QJsonObject approvalById(const QString& approvalId) const;

    QJsonArray tasks() const;
    void upsertTask(const QJsonObject& task);
    QJsonObject taskById(const QString& taskId) const;

    QJsonArray discoveredAgents() const;
    void upsertDiscoveredAgent(const QJsonObject& card);

    QJsonArray messages() const;
    void addMessage(const QJsonObject& message);

    QJsonArray replayNonces() const;
    bool hasReplayNonce(const QString& scope, const QString& nonce) const;
    void addReplayNonce(const QString& scope, const QString& nonce, const QString& createdAt);

    QJsonObject toJson() const;

private:
    QJsonArray arrayLocked(const QString& key) const;
    void setArrayLocked(const QString& key, const QJsonArray& value);

    QString m_persistencePath;
    mutable QMutex m_mutex;
    QJsonObject m_state;
};

#endif
