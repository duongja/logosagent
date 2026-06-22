#include <logos_test.h>

#include "json_utils.h"
#include "owner_message_utils.h"

#include <QJsonObject>

LOGOS_TEST(owner_message_accepts_direct_skill_call)
{
    QString err;
    const QJsonObject msg = OwnerMessageUtils::normalizeOwnerMessage(QJsonObject{
        {QStringLiteral("skill"), QStringLiteral("meta.status")},
        {QStringLiteral("params"), QJsonObject{}}
    }, &err);

    LOGOS_ASSERT(err.isEmpty());
    LOGOS_ASSERT_EQ(msg.value(QStringLiteral("skill")).toString().toStdString(), std::string("meta.status"));
}

LOGOS_TEST(owner_message_decodes_chat_module_hex_content)
{
    const QString command = JsonUtils::toString(QJsonObject{
        {QStringLiteral("skill"), QStringLiteral("wallet.balance")},
        {QStringLiteral("params"), QJsonObject{}}
    });
    const QString contentHex = QString::fromLatin1(command.toUtf8().toHex());
    const QString chatPayload = JsonUtils::toString(QJsonObject{
        {QStringLiteral("eventType"), QStringLiteral("new_message")},
        {QStringLiteral("conversationId"), QStringLiteral("conv-owner")},
        {QStringLiteral("content"), contentHex}
    });

    QString err;
    const QJsonObject msg = OwnerMessageUtils::normalizeOwnerMessage(QJsonObject{
        {QStringLiteral("payload"), chatPayload},
        {QStringLiteral("timestamp"), QStringLiteral("2026-06-09T00:00:00Z")}
    }, &err);

    LOGOS_ASSERT(err.isEmpty());
    LOGOS_ASSERT_EQ(msg.value(QStringLiteral("skill")).toString().toStdString(), std::string("wallet.balance"));
}

LOGOS_TEST(owner_message_extracts_wrapped_chat_conversation_id)
{
    const QString command = JsonUtils::toString(QJsonObject{
        {QStringLiteral("skill"), QStringLiteral("meta.status")},
        {QStringLiteral("params"), QJsonObject{}}
    });
    const QString chatPayload = JsonUtils::toString(QJsonObject{
        {QStringLiteral("eventType"), QStringLiteral("new_message")},
        {QStringLiteral("conversationId"), QStringLiteral("conv-owner-agent")},
        {QStringLiteral("content"), QString::fromLatin1(command.toUtf8().toHex())}
    });

    const QString conversationId = OwnerMessageUtils::ownerConversationId(QJsonObject{
        {QStringLiteral("payload"), chatPayload},
        {QStringLiteral("timestamp"), QStringLiteral("2026-06-22T00:00:00Z")}
    });

    LOGOS_ASSERT_EQ(conversationId.toStdString(), std::string("conv-owner-agent"));
}

LOGOS_TEST(owner_message_accepts_approval_decision)
{
    const QString decision = JsonUtils::toString(QJsonObject{
        {QStringLiteral("approval_id"), QStringLiteral("appr_123")},
        {QStringLiteral("approved"), true}
    });

    QString err;
    const QJsonObject msg = OwnerMessageUtils::normalizeOwnerMessage(QJsonObject{
        {QStringLiteral("message"), decision}
    }, &err);

    LOGOS_ASSERT(err.isEmpty());
    LOGOS_ASSERT_EQ(msg.value(QStringLiteral("approval_id")).toString().toStdString(), std::string("appr_123"));
    LOGOS_ASSERT_TRUE(msg.value(QStringLiteral("approved")).toBool());
}

LOGOS_TEST(owner_message_rejects_invalid_hex)
{
    QString err;
    const QJsonObject msg = OwnerMessageUtils::normalizeOwnerMessage(QJsonObject{
        {QStringLiteral("content"), QStringLiteral("not-hex")}
    }, &err);

    LOGOS_ASSERT_TRUE(msg.isEmpty());
    LOGOS_ASSERT_TRUE(err.contains(QStringLiteral("hex")));
}
