#ifndef LOGOS_AGENT_JSON_UTILS_H
#define LOGOS_AGENT_JSON_UTILS_H

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

namespace JsonUtils {

QJsonObject ok(const QJsonObject& data = QJsonObject{});
QJsonObject error(const QString& code, const QString& message, const QJsonObject& data = QJsonObject{});

QJsonObject parseObject(const QString& json, QString* errorMessage = nullptr);
QJsonArray parseArray(const QString& json, QString* errorMessage = nullptr);
QString toString(const QJsonObject& obj, QJsonDocument::JsonFormat format = QJsonDocument::Compact);
QString toString(const QJsonArray& arr, QJsonDocument::JsonFormat format = QJsonDocument::Compact);

QJsonObject readObjectFile(const QString& path, QString* errorMessage = nullptr);
bool writeObjectFile(const QString& path, const QJsonObject& obj, QString* errorMessage = nullptr);

QString requireString(const QJsonObject& obj, const QString& key, QString* errorMessage);
qulonglong requireUInt64(const QJsonObject& obj, const QString& key, QString* errorMessage);
QJsonObject requireObject(const QJsonObject& obj, const QString& key, QString* errorMessage);

} // namespace JsonUtils

#endif
