#include "owner_message_utils.h"

#include "json_utils.h"

#include <QByteArray>
#include <QJsonValue>

namespace {

bool looksLikeCommand(const QJsonObject& obj)
{
    return obj.contains(QStringLiteral("skill")) || obj.contains(QStringLiteral("approval_id"));
}

QJsonObject parseObjectString(const QString& text, QString* errorMessage)
{
    QString err;
    QJsonObject parsed = JsonUtils::parseObject(text, &err);
    if (!err.isEmpty()) {
        if (errorMessage) {
            *errorMessage = err;
        }
        return {};
    }
    return parsed;
}

QJsonObject parseHexObjectString(const QString& hex, QString* errorMessage)
{
    if ((hex.size() % 2) != 0) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("owner chat content is not valid hex");
        }
        return {};
    }
    for (const QChar ch : hex) {
        const ushort c = ch.unicode();
        const bool isHex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!isHex) {
            if (errorMessage) {
                *errorMessage = QStringLiteral("owner chat content is not valid hex");
            }
            return {};
        }
    }
    const QByteArray bytes = QByteArray::fromHex(hex.toUtf8());
    if (bytes.isEmpty() && !hex.isEmpty()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("owner chat content is not valid hex");
        }
        return {};
    }
    return parseObjectString(QString::fromUtf8(bytes), errorMessage);
}

QString conversationIdFromObject(const QJsonObject& obj)
{
    const QString camel = obj.value(QStringLiteral("conversationId")).toString();
    if (!camel.isEmpty()) {
        return camel;
    }
    return obj.value(QStringLiteral("conversation_id")).toString();
}

QJsonObject nestedPayloadObject(const QJsonObject& payload)
{
    const QJsonValue wrappedPayload = payload.value(QStringLiteral("payload"));
    if (wrappedPayload.isObject()) {
        return wrappedPayload.toObject();
    }
    if (wrappedPayload.isString()) {
        return parseObjectString(wrappedPayload.toString(), nullptr);
    }
    return {};
}

QJsonObject normalizeNestedChatPayload(const QJsonObject& wrapped, QString* errorMessage)
{
    const QString rawPayload = wrapped.value(QStringLiteral("payload")).toString();
    if (rawPayload.isEmpty()) {
        return {};
    }

    QString nestedErr;
    const QJsonObject event = parseObjectString(rawPayload, &nestedErr);
    if (event.isEmpty()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("owner chat payload could not be parsed: %1").arg(nestedErr);
        }
        return {};
    }

    if (looksLikeCommand(event)) {
        return event;
    }

    const QString contentHex = event.value(QStringLiteral("content")).toString();
    if (!contentHex.isEmpty()) {
        return parseHexObjectString(contentHex, errorMessage);
    }

    const QString message = event.value(QStringLiteral("message")).toString();
    if (!message.isEmpty()) {
        return parseObjectString(message, errorMessage);
    }

    return event;
}

} // namespace

namespace OwnerMessageUtils {

QJsonObject normalizeOwnerMessage(const QJsonObject& payload, QString* errorMessage)
{
    if (looksLikeCommand(payload)) {
        return payload;
    }

    const QString contentHex = payload.value(QStringLiteral("content")).toString();
    if (!contentHex.isEmpty()) {
        return parseHexObjectString(contentHex, errorMessage);
    }

    const QJsonValue wrappedPayload = payload.value(QStringLiteral("payload"));
    if (wrappedPayload.isObject()) {
        return normalizeOwnerMessage(wrappedPayload.toObject(), errorMessage);
    }
    if (wrappedPayload.isString()) {
        return normalizeNestedChatPayload(payload, errorMessage);
    }

    const QString message = payload.value(QStringLiteral("message")).toString();
    if (!message.isEmpty()) {
        return parseObjectString(message, errorMessage);
    }

    if (errorMessage) {
        *errorMessage = QStringLiteral("owner message did not contain a skill call or approval decision");
    }
    return {};
}

QString ownerConversationId(const QJsonObject& payload)
{
    const QString direct = conversationIdFromObject(payload);
    if (!direct.isEmpty()) {
        return direct;
    }

    const QJsonObject nested = nestedPayloadObject(payload);
    if (!nested.isEmpty()) {
        return ownerConversationId(nested);
    }

    return {};
}

} // namespace OwnerMessageUtils
