#ifndef LOGOS_AGENT_OWNER_MESSAGE_UTILS_H
#define LOGOS_AGENT_OWNER_MESSAGE_UTILS_H

#include <QJsonObject>
#include <QString>

namespace OwnerMessageUtils {

QJsonObject normalizeOwnerMessage(const QJsonObject& payload, QString* errorMessage = nullptr);
QString ownerConversationId(const QJsonObject& payload);

} // namespace OwnerMessageUtils

#endif
