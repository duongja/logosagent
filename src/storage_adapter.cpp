#include "storage_adapter.h"

#include "agent_state.h"
#include "crypto_utils.h"
#include "json_utils.h"
#include "logos_sdk.h"

#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QJsonArray>
#include <QThread>
#include <QUrl>
#include <QVariant>
#include <QVariantList>

namespace {

QJsonObject redactedEncryption(QJsonObject encryption)
{
    encryption.remove(QStringLiteral("key_hex"));
    return encryption;
}

QString recipientLabel(const QJsonObject& params)
{
    const QJsonValue value = params.value(QStringLiteral("recipient"));
    if (value.isString()) {
        return value.toString();
    }
    const QJsonObject recipient = value.toObject();
    return recipient.value(QStringLiteral("address")).toString(
        recipient.value(QStringLiteral("messaging_address")).toString(
            recipient.value(QStringLiteral("agent_address")).toString(
                recipient.value(QStringLiteral("id")).toString())));
}

QByteArray readFileBytes(const QString& path, QString* error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) {
            *error = file.errorString();
        }
        return {};
    }
    return file.readAll();
}

bool waitForDownloadedCipher(const QString& path, const QJsonObject& encryption, QString* error)
{
    const QString expectedHash = encryption.value(QStringLiteral("cipher_sha256")).toString();
    const qint64 expectedSize = static_cast<qint64>(encryption.value(QStringLiteral("size")).toInteger(-1));
    if (expectedHash.isEmpty() && expectedSize < 0) {
        return true;
    }

    QElapsedTimer timer;
    timer.start();
    QString lastError;
    while (timer.elapsed() < 30000) {
        QFileInfo info(path);
        if (info.exists() && (expectedSize < 0 || info.size() == expectedSize)) {
            QString readError;
            const QByteArray bytes = readFileBytes(path, &readError);
            if (!readError.isEmpty()) {
                lastError = readError;
            } else if (expectedHash.isEmpty() || CryptoUtils::sha256Hex(bytes) == expectedHash) {
                return true;
            } else {
                lastError = QStringLiteral("cipher content hash mismatch while waiting for download completion");
            }
        }
        QThread::msleep(100);
    }

    if (error) {
        *error = lastError.isEmpty()
            ? QStringLiteral("download did not complete before timeout")
            : lastError;
    }
    return false;
}

} // namespace

void StorageAdapter::setLogosModules(LogosModules* modules)
{
    m_logos = modules;
}

void StorageAdapter::setState(AgentState* state)
{
    m_state = state;
}

void StorageAdapter::wireEvents()
{
    if (!m_logos || !m_state) {
        return;
    }
    m_logos->storage_module.on("storageUploadDone", [this](const QVariantList& data) {
        if (data.size() < 3 || !data.at(0).toBool()) {
            return;
        }
        const QString sessionId = data.at(1).toString();
        const QString cid = data.at(2).toString();
        QJsonObject patch{
            {QStringLiteral("address"), cid},
            {QStringLiteral("upload_session"), sessionId},
            {QStringLiteral("status"), QStringLiteral("uploaded")},
            {QStringLiteral("uploaded_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        };
        m_state->updateFileByAddress(sessionId, patch);
        m_state->save();
    });
}

QJsonObject StorageAdapter::init(const QJsonObject& config)
{
    return init(config, false);
}

QJsonObject StorageAdapter::init(const QJsonObject& config, bool asyncStart, StartCallback callback)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("storage.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    const QJsonObject storageCfg = config.value(QStringLiteral("storage")).toObject();
    if (!storageCfg.isEmpty()) {
        const QString cfgJson = JsonUtils::toString(storageCfg);
        if (!m_logos->storage_module.init(cfgJson)) {
            m_lastError = QStringLiteral("storage_module.init returned false");
            m_configured = false;
            return JsonUtils::error(QStringLiteral("storage.init_failed"), QStringLiteral("storage_module.init returned false"));
        }
        m_configured = true;
        m_lastError.clear();
        if (config.value(QStringLiteral("autostart_storage")).toBool(true)) {
            m_starting = true;
            m_started = false;
            if (asyncStart) {
                m_logos->storage_module.startAsync([this, callback](bool ok) {
                    m_starting = false;
                    m_started = ok;
                    m_lastError = ok ? QString() : QStringLiteral("storage_module.start returned false");
                    const QJsonObject result = ok
                        ? JsonUtils::ok(QJsonObject{{QStringLiteral("started"), true}, {QStringLiteral("async"), true}})
                        : JsonUtils::error(QStringLiteral("storage.start_failed"), m_lastError, QJsonObject{{QStringLiteral("async"), true}});
                    if (callback) {
                        callback(result);
                    }
                }, Timeout(60000));
                return JsonUtils::ok(QJsonObject{
                    {QStringLiteral("configured"), true},
                    {QStringLiteral("starting"), true},
                    {QStringLiteral("async"), true}
                });
            }
            if (!m_logos->storage_module.start()) {
                m_starting = false;
                m_lastError = QStringLiteral("storage_module.start returned false");
                return JsonUtils::error(QStringLiteral("storage.start_failed"), QStringLiteral("storage_module.start returned false"));
            }
            m_starting = false;
            m_started = true;
        }
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("configured"), !storageCfg.isEmpty()}});
}

QJsonObject StorageAdapter::status() const
{
    QJsonObject out{
        {QStringLiteral("configured"), m_configured},
        {QStringLiteral("starting"), m_starting},
        {QStringLiteral("started"), m_started}
    };
    if (!m_lastError.isEmpty()) {
        out.insert(QStringLiteral("last_error"), m_lastError);
    }
    return out;
}

QJsonObject StorageAdapter::upload(const QJsonObject& params)
{
    if (!m_logos || !m_state) {
        return JsonUtils::error(QStringLiteral("storage.unavailable"), QStringLiteral("storage adapter is not initialized"));
    }
    QString err;
    const QString path = JsonUtils::requireString(params, QStringLiteral("path"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.invalid_params"), err);
    }
    const QString label = params.value(QStringLiteral("label")).toString(QFileInfo(path).fileName());
    const QString encryptedPath = tempPath(QStringLiteral(".enc"));
    QString encErr;
    const QJsonObject encryption = CryptoUtils::encryptFile(path, encryptedPath, &encErr);
    if (!encErr.isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.encrypt_failed"), encErr);
    }

    LogosResult result = m_logos->storage_module.uploadUrl(QUrl::fromLocalFile(encryptedPath));
    if (!result.success) {
        return JsonUtils::error(QStringLiteral("storage.upload_failed"), result.getError());
    }
    const QString sessionId = result.getString();
    QJsonObject entry{
        {QStringLiteral("label"), label},
        {QStringLiteral("address"), sessionId},
        {QStringLiteral("upload_session"), sessionId},
        {QStringLiteral("source_path"), path},
        {QStringLiteral("encrypted_path"), encryptedPath},
        {QStringLiteral("status"), QStringLiteral("uploading")},
        {QStringLiteral("encryption"), encryption},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    };
    m_state->addFile(entry);
    m_state->save();
    return JsonUtils::ok(QJsonObject{{QStringLiteral("file"), publicFileEntry(entry)}});
}

QJsonObject StorageAdapter::download(const QJsonObject& params)
{
    if (!m_logos || !m_state) {
        return JsonUtils::error(QStringLiteral("storage.unavailable"), QStringLiteral("storage adapter is not initialized"));
    }
    QString err;
    QString address = params.value(QStringLiteral("address")).toString();
    if (address.trimmed().isEmpty() && params.value(QStringLiteral("share")).isObject()) {
        address = params.value(QStringLiteral("share")).toObject().value(QStringLiteral("address")).toString();
    }
    if (address.trimmed().isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.invalid_params"), QStringLiteral("missing or invalid address"));
    }
    const QString outPath = JsonUtils::requireString(params, QStringLiteral("path"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.invalid_params"), err);
    }
    const QJsonObject meta = m_state->fileByAddress(address);
    QJsonObject encryption;
    if (params.value(QStringLiteral("share")).isObject()) {
        const QJsonObject share = params.value(QStringLiteral("share")).toObject();
        const QJsonObject wrapped = share.value(QStringLiteral("encryption")).toObject();
        const QJsonObject recipientIdentity = m_state->identity().value(QStringLiteral("encryption")).toObject();
        QString unwrapErr;
        encryption = CryptoUtils::unwrapEncryptionForRecipient(wrapped, recipientIdentity, &unwrapErr);
        if (!unwrapErr.isEmpty()) {
            return JsonUtils::error(QStringLiteral("storage.unwrap_failed"), unwrapErr);
        }
    } else if (!meta.isEmpty() && meta.value(QStringLiteral("encryption")).isObject()) {
        encryption = meta.value(QStringLiteral("encryption")).toObject();
    }

    const QString encryptedPath = tempPath(QStringLiteral(".download.enc"));
    LogosResult result = m_logos->storage_module.downloadToUrl(address, QUrl::fromLocalFile(encryptedPath), false, 1024 * 64);
    if (!result.success) {
        return JsonUtils::error(QStringLiteral("storage.download_failed"), result.getError());
    }

    if (encryption.isEmpty()) {
        return JsonUtils::ok(QJsonObject{
            {QStringLiteral("address"), address},
            {QStringLiteral("encrypted_path"), encryptedPath},
            {QStringLiteral("note"), QStringLiteral("download started; no local encryption metadata found for automatic decrypt")}
        });
    }
    const QString alg = encryption.value(QStringLiteral("alg")).toString();
    const QJsonObject securityCfg = m_state->config().value(QStringLiteral("security")).toObject();
    if (alg == QStringLiteral("xor-sha256-stream-dev") && !securityCfg.value(QStringLiteral("allow_dev_file_cipher")).toBool(false)) {
        return JsonUtils::error(
            QStringLiteral("storage.legacy_dev_crypto_disabled"),
            QStringLiteral("legacy dev cipher metadata requires security.allow_dev_file_cipher=true"));
    }
    QString waitErr;
    if (!waitForDownloadedCipher(encryptedPath, encryption, &waitErr)) {
        return JsonUtils::error(QStringLiteral("storage.download_incomplete"), waitErr);
    }
    QString decErr;
    const bool decrypted = CryptoUtils::decryptFile(encryptedPath, outPath, encryption, &decErr);
    if (!decrypted) {
        return JsonUtils::error(QStringLiteral("storage.decrypt_failed"), decErr);
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("address"), address}, {QStringLiteral("path"), outPath}});
}

QJsonObject StorageAdapter::list() const
{
    if (!m_state) {
        return JsonUtils::error(QStringLiteral("storage.unavailable"), QStringLiteral("state is not initialized"));
    }
    QJsonArray files;
    const QJsonArray stored = m_state->files();
    for (const QJsonValue& value : stored) {
        files.append(publicFileEntry(value.toObject()));
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("files"), files}});
}

QJsonObject StorageAdapter::share(const QJsonObject& params)
{
    if (!m_state) {
        return JsonUtils::error(QStringLiteral("storage.unavailable"), QStringLiteral("state is not initialized"));
    }
    QString err;
    const QString address = JsonUtils::requireString(params, QStringLiteral("address"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.invalid_params"), err);
    }
    const QString recipient = recipientLabel(params);
    if (recipient.trimmed().isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.invalid_params"), QStringLiteral("missing or invalid recipient"));
    }
    const QJsonObject meta = m_state->fileByAddress(address);
    if (meta.isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.not_found"), QStringLiteral("no stored file metadata for address"));
    }
    const QJsonObject encryption = meta.value(QStringLiteral("encryption")).toObject();
    if (!encryption.contains(QStringLiteral("key_hex"))) {
        return JsonUtils::error(QStringLiteral("storage.missing_key"), QStringLiteral("stored file metadata does not contain a local file encryption key"));
    }
    const QString recipientPublicKey = recipientEncryptionPublicKey(params);
    if (recipientPublicKey.isEmpty()) {
        return JsonUtils::error(
            QStringLiteral("storage.recipient_key_required"),
            QStringLiteral("storage.share requires recipient_public_key_hex or recipient.encryption_public_key_hex"));
    }
    QString wrapErr;
    const QJsonObject wrappedEncryption = CryptoUtils::wrapEncryptionForRecipient(encryption, recipientPublicKey, &wrapErr);
    if (!wrapErr.isEmpty()) {
        return JsonUtils::error(QStringLiteral("storage.wrap_failed"), wrapErr);
    }
    QJsonObject share{
        {QStringLiteral("type"), QStringLiteral("logos.storage.share.v1")},
        {QStringLiteral("address"), address},
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("label"), meta.value(QStringLiteral("label")).toString()},
        {QStringLiteral("encryption"), wrappedEncryption},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
    };
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("share"), share},
        {QStringLiteral("note"), QStringLiteral("send this wrapped share payload with messaging.send to deliver access")}
    });
}

QString StorageAdapter::tempPath(const QString& suffix) const
{
    const QString base = m_state ? m_state->persistencePath() + QStringLiteral("/tmp") : QDir::tempPath();
    QDir().mkpath(base);
    return base + QStringLiteral("/") + CryptoUtils::randomId(QStringLiteral("file")) + suffix;
}

QJsonObject StorageAdapter::publicFileEntry(const QJsonObject& file) const
{
    QJsonObject out = file;
    if (out.value(QStringLiteral("encryption")).isObject()) {
        out.insert(QStringLiteral("encryption"), redactedEncryption(out.value(QStringLiteral("encryption")).toObject()));
    }
    return out;
}

QString StorageAdapter::recipientEncryptionPublicKey(const QJsonObject& params) const
{
    const QString direct = params.value(QStringLiteral("recipient_public_key_hex")).toString(
        params.value(QStringLiteral("encryption_public_key_hex")).toString());
    if (!direct.isEmpty()) {
        return direct;
    }
    const QString recipientValue = params.value(QStringLiteral("recipient")).toString();
    if (QByteArray::fromHex(recipientValue.toLatin1()).size() == 32) {
        return recipientValue;
    }
    const QJsonObject recipientObj = params.value(QStringLiteral("recipient")).toObject();
    const QJsonObject logos = recipientObj.value(QStringLiteral("logos")).toObject();
    const QString fromRecipient = recipientObj.value(QStringLiteral("encryption_public_key_hex")).toString(
        recipientObj.value(QStringLiteral("encryption_public_key")).toString(
            recipientObj.value(QStringLiteral("public_key_hex")).toString(
                logos.value(QStringLiteral("encryption_public_key")).toString())));
    if (!fromRecipient.isEmpty()) {
        return fromRecipient;
    }
    return params.value(QStringLiteral("recipient_encryption_key")).toObject()
        .value(QStringLiteral("public_key_hex")).toString();
}
