#include <logos_test.h>

#include "amount_utils.h"
#include "agent_state.h"
#include "policy_engine.h"

#include <QDir>
#include <QJsonObject>

LOGOS_TEST(amount_to_le16_hex)
{
    QString err;
    const QString one = AmountUtils::decimalToLe16Hex(QStringLiteral("1"), &err);
    LOGOS_ASSERT(err.isEmpty());
    LOGOS_ASSERT_EQ(one.toStdString(), std::string("01000000000000000000000000000000"));

    const QString twoFiftySix = AmountUtils::decimalToLe16Hex(QStringLiteral("256"), &err);
    LOGOS_ASSERT(err.isEmpty());
    LOGOS_ASSERT_EQ(twoFiftySix.toStdString(), std::string("00010000000000000000000000000000"));
}

LOGOS_TEST(policy_requires_approval_above_limits)
{
    AgentState state;
    state.setPersistencePath(QDir::tempPath() + QStringLiteral("/logos-agent-test-policy"));
    state.load();
    state.setConfig(QJsonObject{
        {QStringLiteral("policy"), QJsonObject{
            {QStringLiteral("per_transaction_limit"), QStringLiteral("10")},
            {QStringLiteral("period_limit"), QStringLiteral("25")},
            {QStringLiteral("period_seconds"), 86400}
        }}
    });

    PolicyEngine policy(&state);
    QJsonObject allowed = policy.checkSpend(QStringLiteral("wallet.send"), QStringLiteral("9"), QJsonObject{});
    LOGOS_ASSERT_FALSE(allowed.value(QStringLiteral("requires_approval")).toBool());

    QJsonObject blocked = policy.checkSpend(QStringLiteral("wallet.send"), QStringLiteral("11"), QJsonObject{});
    LOGOS_ASSERT_TRUE(blocked.value(QStringLiteral("requires_approval")).toBool());
}

LOGOS_TEST(policy_default_fails_closed)
{
    AgentState state;
    state.setPersistencePath(QDir::tempPath() + QStringLiteral("/logos-agent-test-policy-default"));
    state.load();
    state.setConfig(QJsonObject{
        {QStringLiteral("policy"), QJsonObject{
            {QStringLiteral("per_transaction_limit"), QStringLiteral("0")},
            {QStringLiteral("period_limit"), QStringLiteral("0")},
            {QStringLiteral("period_seconds"), 86400}
        }}
    });

    PolicyEngine policy(&state);
    QJsonObject blocked = policy.checkSpend(QStringLiteral("wallet.send"), QStringLiteral("1"), QJsonObject{});
    LOGOS_ASSERT_TRUE(blocked.value(QStringLiteral("requires_approval")).toBool());
}
