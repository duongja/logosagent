#include "json_utils.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <limits>

namespace JsonUtils {

QJsonObject ok(const QJsonObject& data)
{
    QJsonObject out = data;
    out.insert(QStringLiteral("ok"), true);
    return out;
}

QJsonObject error(const QString& code, const QString& message, const QJsonObject& data)
{
    QJsonObject out = data;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("code"), code);
    out.insert(QStringLiteral("error"), message);
    return out;
}

QJsonObject parseObject(const QString& json, QString* errorMessage)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        if (errorMessage) {
            *errorMessage = parseError.errorString();
        }
        return {};
    }
    if (!doc.isObject()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("expected JSON object");
        }
        return {};
    }
    return doc.object();
}

QJsonArray parseArray(const QString& json, QString* errorMessage)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        if (errorMessage) {
            *errorMessage = parseError.errorString();
        }
        return {};
    }
    if (!doc.isArray()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("expected JSON array");
        }
        return {};
    }
    return doc.array();
}

QString toString(const QJsonObject& obj, QJsonDocument::JsonFormat format)
{
    return QString::fromUtf8(QJsonDocument(obj).toJson(format));
}

QString toString(const QJsonArray& arr, QJsonDocument::JsonFormat format)
{
    return QString::fromUtf8(QJsonDocument(arr).toJson(format));
}

QJsonObject readObjectFile(const QString& path, QString* errorMessage)
{
    QFile f(path);
    if (!f.exists()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("file does not exist: %1").arg(path);
        }
        return {};
    }
    if (!f.open(QIODevice::ReadOnly)) {
        if (errorMessage) {
            *errorMessage = f.errorString();
        }
        return {};
    }
    return parseObject(QString::fromUtf8(f.readAll()), errorMessage);
}

bool writeObjectFile(const QString& path, const QJsonObject& obj, QString* errorMessage)
{
    QFileInfo info(path);
    QDir().mkpath(info.absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (errorMessage) {
            *errorMessage = f.errorString();
        }
        return false;
    }
    const QByteArray bytes = QJsonDocument(obj).toJson(QJsonDocument::Indented);
    if (f.write(bytes) != bytes.size()) {
        if (errorMessage) {
            *errorMessage = f.errorString();
        }
        return false;
    }
    return true;
}

QString requireString(const QJsonObject& obj, const QString& key, QString* errorMessage)
{
    const QJsonValue value = obj.value(key);
    if (!value.isString() || value.toString().trimmed().isEmpty()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("missing or invalid string field: %1").arg(key);
        }
        return {};
    }
    return value.toString();
}

qulonglong requireUInt64(const QJsonObject& obj, const QString& key, QString* errorMessage)
{
    const QJsonValue value = obj.value(key);
    bool ok = false;
    qulonglong parsed = 0;
    if (value.isString()) {
        parsed = value.toString().toULongLong(&ok);
    } else if (value.isDouble()) {
        const double d = value.toDouble();
        ok = d >= 0 && d <= static_cast<double>(std::numeric_limits<qulonglong>::max());
        parsed = ok ? static_cast<qulonglong>(d) : 0;
    }
    if (!ok) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("missing or invalid uint64 field: %1").arg(key);
        }
        return 0;
    }
    return parsed;
}

QJsonObject requireObject(const QJsonObject& obj, const QString& key, QString* errorMessage)
{
    const QJsonValue value = obj.value(key);
    if (!value.isObject()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("missing or invalid object field: %1").arg(key);
        }
        return {};
    }
    return value.toObject();
}

} // namespace JsonUtils
