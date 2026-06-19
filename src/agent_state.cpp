#include "agent_state.h"

#include "json_utils.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QMutexLocker>

namespace {

QJsonObject defaultState()
{
    return QJsonObject{
        {QStringLiteral("schema_version"), 1},
        {QStringLiteral("config"), QJsonObject{}},
        {QStringLiteral("files"), QJsonArray{}},
        {QStringLiteral("transactions"), QJsonArray{}},
        {QStringLiteral("approvals"), QJsonArray{}},
        {QStringLiteral("tasks"), QJsonArray{}},
        {QStringLiteral("discovered_agents"), QJsonArray{}},
        {QStringLiteral("messages"), QJsonArray{}},
        {QStringLiteral("replay_nonces"), QJsonArray{}},
        {QStringLiteral("updated_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    };
}

QJsonObject mergeObjects(QJsonObject base, const QJsonObject& overlay)
{
    for (auto it = overlay.begin(); it != overlay.end(); ++it) {
        if (base.value(it.key()).isObject() && it.value().isObject()) {
            base.insert(it.key(), mergeObjects(base.value(it.key()).toObject(), it.value().toObject()));
        } else {
            base.insert(it.key(), it.value());
        }
    }
    return base;
}

} // namespace

void AgentState::setPersistencePath(const QString& path)
{
    QMutexLocker lock(&m_mutex);
    m_persistencePath = path;
    QDir().mkpath(m_persistencePath);
}

QString AgentState::persistencePath() const
{
    QMutexLocker lock(&m_mutex);
    return m_persistencePath;
}

QString AgentState::stateFilePath() const
{
    QMutexLocker lock(&m_mutex);
    return m_persistencePath + QStringLiteral("/state.json");
}

bool AgentState::load(QString* errorMessage)
{
    QMutexLocker lock(&m_mutex);
    if (m_persistencePath.isEmpty()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("persistence path is not configured");
        }
        return false;
    }

    const QString path = m_persistencePath + QStringLiteral("/state.json");
    if (!QFile::exists(path)) {
        m_state = defaultState();
        return true;
    }

    QString err;
    const QJsonObject loaded = JsonUtils::readObjectFile(path, &err);
    if (loaded.isEmpty() && !err.isEmpty()) {
        if (errorMessage) {
            *errorMessage = err;
        }
        return false;
    }
    m_state = mergeObjects(defaultState(), loaded);
    return true;
}

bool AgentState::save(QString* errorMessage) const
{
    QMutexLocker lock(&m_mutex);
    QJsonObject out = m_state;
    out.insert(QStringLiteral("updated_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    return JsonUtils::writeObjectFile(m_persistencePath + QStringLiteral("/state.json"), out, errorMessage);
}

QJsonObject AgentState::config() const
{
    QMutexLocker lock(&m_mutex);
    return m_state.value(QStringLiteral("config")).toObject();
}

void AgentState::setConfig(const QJsonObject& config)
{
    QMutexLocker lock(&m_mutex);
    m_state.insert(QStringLiteral("config"), mergeObjects(m_state.value(QStringLiteral("config")).toObject(), config));
}

QJsonObject AgentState::policy() const
{
    QMutexLocker lock(&m_mutex);
    return m_state.value(QStringLiteral("config")).toObject().value(QStringLiteral("policy")).toObject();
}

QJsonObject AgentState::identity() const
{
    QMutexLocker lock(&m_mutex);
    return m_state.value(QStringLiteral("config")).toObject().value(QStringLiteral("identity")).toObject();
}

QJsonArray AgentState::files() const
{
    return arrayLocked(QStringLiteral("files"));
}

void AgentState::addFile(const QJsonObject& file)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("files")).toArray();
    arr.append(file);
    m_state.insert(QStringLiteral("files"), arr);
}

bool AgentState::updateFileByAddress(const QString& address, const QJsonObject& patch)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("files")).toArray();
    bool changed = false;
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject item = arr.at(i).toObject();
        if (item.value(QStringLiteral("address")).toString() == address) {
            item = mergeObjects(item, patch);
            arr[i] = item;
            changed = true;
            break;
        }
    }
    if (changed) {
        m_state.insert(QStringLiteral("files"), arr);
    }
    return changed;
}

QJsonObject AgentState::fileByAddress(const QString& address) const
{
    QMutexLocker lock(&m_mutex);
    const QJsonArray arr = m_state.value(QStringLiteral("files")).toArray();
    for (const QJsonValue& value : arr) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("address")).toString() == address) {
            return item;
        }
    }
    return {};
}

QJsonArray AgentState::transactions() const
{
    return arrayLocked(QStringLiteral("transactions"));
}

void AgentState::addTransaction(const QJsonObject& tx)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("transactions")).toArray();
    arr.insert(0, tx);
    while (arr.size() > 200) {
        arr.removeLast();
    }
    m_state.insert(QStringLiteral("transactions"), arr);
}

QJsonArray AgentState::approvals() const
{
    return arrayLocked(QStringLiteral("approvals"));
}

void AgentState::addApproval(const QJsonObject& approval)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("approvals")).toArray();
    arr.insert(0, approval);
    m_state.insert(QStringLiteral("approvals"), arr);
}

bool AgentState::updateApproval(const QString& approvalId, const QJsonObject& patch)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("approvals")).toArray();
    bool changed = false;
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject item = arr.at(i).toObject();
        if (item.value(QStringLiteral("approval_id")).toString() == approvalId) {
            item = mergeObjects(item, patch);
            arr[i] = item;
            changed = true;
            break;
        }
    }
    if (changed) {
        m_state.insert(QStringLiteral("approvals"), arr);
    }
    return changed;
}

QJsonObject AgentState::approvalById(const QString& approvalId) const
{
    QMutexLocker lock(&m_mutex);
    const QJsonArray arr = m_state.value(QStringLiteral("approvals")).toArray();
    for (const QJsonValue& value : arr) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("approval_id")).toString() == approvalId) {
            return item;
        }
    }
    return {};
}

QJsonArray AgentState::tasks() const
{
    return arrayLocked(QStringLiteral("tasks"));
}

void AgentState::upsertTask(const QJsonObject& task)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("tasks")).toArray();
    const QString taskId = task.value(QStringLiteral("task_id")).toString();
    bool changed = false;
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject item = arr.at(i).toObject();
        if (item.value(QStringLiteral("task_id")).toString() == taskId) {
            arr[i] = mergeObjects(item, task);
            changed = true;
            break;
        }
    }
    if (!changed) {
        arr.insert(0, task);
    }
    while (arr.size() > 200) {
        arr.removeLast();
    }
    m_state.insert(QStringLiteral("tasks"), arr);
}

QJsonObject AgentState::taskById(const QString& taskId) const
{
    QMutexLocker lock(&m_mutex);
    const QJsonArray arr = m_state.value(QStringLiteral("tasks")).toArray();
    for (const QJsonValue& value : arr) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("task_id")).toString() == taskId) {
            return item;
        }
    }
    return {};
}

QJsonArray AgentState::discoveredAgents() const
{
    return arrayLocked(QStringLiteral("discovered_agents"));
}

void AgentState::upsertDiscoveredAgent(const QJsonObject& card)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("discovered_agents")).toArray();
    const QString key = card.value(QStringLiteral("preferredTransport")).toString()
        + QStringLiteral(":")
        + card.value(QStringLiteral("name")).toString();
    bool changed = false;
    for (int i = 0; i < arr.size(); ++i) {
        const QJsonObject item = arr.at(i).toObject();
        const QString existingKey = item.value(QStringLiteral("preferredTransport")).toString()
            + QStringLiteral(":")
            + item.value(QStringLiteral("name")).toString();
        if (existingKey == key) {
            arr[i] = card;
            changed = true;
            break;
        }
    }
    if (!changed) {
        arr.insert(0, card);
    }
    m_state.insert(QStringLiteral("discovered_agents"), arr);
}

QJsonArray AgentState::messages() const
{
    return arrayLocked(QStringLiteral("messages"));
}

void AgentState::addMessage(const QJsonObject& message)
{
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("messages")).toArray();
    arr.insert(0, message);
    while (arr.size() > 500) {
        arr.removeLast();
    }
    m_state.insert(QStringLiteral("messages"), arr);
}

QJsonArray AgentState::replayNonces() const
{
    return arrayLocked(QStringLiteral("replay_nonces"));
}

bool AgentState::hasReplayNonce(const QString& scope, const QString& nonce) const
{
    QMutexLocker lock(&m_mutex);
    const QJsonArray arr = m_state.value(QStringLiteral("replay_nonces")).toArray();
    for (const QJsonValue& value : arr) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("scope")).toString() == scope
            && item.value(QStringLiteral("nonce")).toString() == nonce) {
            return true;
        }
    }
    return false;
}

void AgentState::addReplayNonce(const QString& scope, const QString& nonce, const QString& createdAt)
{
    if (scope.isEmpty() || nonce.isEmpty()) {
        return;
    }
    QMutexLocker lock(&m_mutex);
    QJsonArray arr = m_state.value(QStringLiteral("replay_nonces")).toArray();
    for (const QJsonValue& value : arr) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("scope")).toString() == scope
            && item.value(QStringLiteral("nonce")).toString() == nonce) {
            return;
        }
    }
    arr.insert(0, QJsonObject{
        {QStringLiteral("scope"), scope},
        {QStringLiteral("nonce"), nonce},
        {QStringLiteral("created_at"), createdAt}
    });
    while (arr.size() > 1000) {
        arr.removeLast();
    }
    m_state.insert(QStringLiteral("replay_nonces"), arr);
}

QJsonObject AgentState::toJson() const
{
    QMutexLocker lock(&m_mutex);
    return m_state;
}

QJsonArray AgentState::arrayLocked(const QString& key) const
{
    QMutexLocker lock(&m_mutex);
    return m_state.value(key).toArray();
}

void AgentState::setArrayLocked(const QString& key, const QJsonArray& value)
{
    QMutexLocker lock(&m_mutex);
    m_state.insert(key, value);
}
