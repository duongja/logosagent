#include "policy_engine.h"

#include "agent_state.h"
#include "amount_utils.h"
#include "crypto_utils.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>

PolicyEngine::PolicyEngine(AgentState* state)
    : m_state(state)
{
}

void PolicyEngine::setState(AgentState* state)
{
    m_state = state;
}

QJsonObject PolicyEngine::checkSpend(const QString& skillName, const QString& amount, const QJsonObject& request) const
{
    Q_UNUSED(request);
    const QString txLimit = perTxLimit();
    const QString period = periodLimit();
    const QString spent = spentThisPeriod();
    const QString after = AmountUtils::addDecimal(spent, amount);

    const bool perTxOk = AmountUtils::leqDecimal(amount, txLimit);
    const bool periodOk = !after.isEmpty() && AmountUtils::leqDecimal(after, period);

    return QJsonObject{
        {QStringLiteral("allowed"), perTxOk && periodOk},
        {QStringLiteral("requires_approval"), !(perTxOk && periodOk)},
        {QStringLiteral("skill"), skillName},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("per_transaction_limit"), txLimit},
        {QStringLiteral("period_limit"), period},
        {QStringLiteral("spent_this_period"), spent}
    };
}

QJsonObject PolicyEngine::createApproval(const QString& skillName, const QString& amount, const QJsonObject& request) const
{
    return QJsonObject{
        {QStringLiteral("approval_id"), CryptoUtils::randomId(QStringLiteral("appr"))},
        {QStringLiteral("status"), QStringLiteral("pending")},
        {QStringLiteral("skill"), skillName},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("request"), request},
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("expires_at"), QDateTime::currentDateTimeUtc().addSecs(3600).toString(Qt::ISODate)}
    };
}

QString PolicyEngine::perTxLimit() const
{
    if (!m_state) {
        return {};
    }
    return m_state->policy().value(QStringLiteral("per_transaction_limit")).toString(QStringLiteral("0"));
}

QString PolicyEngine::periodLimit() const
{
    if (!m_state) {
        return {};
    }
    return m_state->policy().value(QStringLiteral("period_limit")).toString(QStringLiteral("0"));
}

QString PolicyEngine::spentThisPeriod() const
{
    if (!m_state) {
        return QStringLiteral("0");
    }
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const QDateTime start = now.addSecs(-m_state->policy().value(QStringLiteral("period_seconds")).toInt(86400));
    qulonglong total = 0;
    const QJsonArray txs = m_state->transactions();
    for (const QJsonValue& value : txs) {
        const QJsonObject tx = value.toObject();
        if (!tx.value(QStringLiteral("spending_controlled")).toBool(false)) {
            continue;
        }
        const QDateTime at = QDateTime::fromString(tx.value(QStringLiteral("created_at")).toString(), Qt::ISODate);
        if (!at.isValid() || at < start) {
            continue;
        }
        bool ok = false;
        const qulonglong amount = tx.value(QStringLiteral("amount")).toString().toULongLong(&ok);
        if (ok) {
            total += amount;
        }
    }
    return QString::number(total);
}
