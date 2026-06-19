#include "amount_utils.h"

#include <QByteArray>

namespace {

bool parseU64(const QString& value, qulonglong* out)
{
    bool ok = false;
    const qulonglong parsed = value.trimmed().toULongLong(&ok);
    if (ok && out) {
        *out = parsed;
    }
    return ok;
}

} // namespace

namespace AmountUtils {

QString decimalToLe16Hex(const QString& amountDecimal, QString* errorMessage)
{
    qulonglong value = 0;
    if (!parseU64(amountDecimal, &value)) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("amount must be an unsigned integer token unit value");
        }
        return {};
    }

    char bytes[16] = {0};
    for (int i = 0; i < 8; ++i) {
        bytes[i] = static_cast<char>((value >> (i * 8)) & 0xff);
    }
    return QString::fromLatin1(QByteArray(bytes, 16).toHex());
}

bool leqDecimal(const QString& lhs, const QString& rhs)
{
    qulonglong a = 0;
    qulonglong b = 0;
    if (!parseU64(lhs, &a) || !parseU64(rhs, &b)) {
        return false;
    }
    return a <= b;
}

QString addDecimal(const QString& lhs, const QString& rhs)
{
    qulonglong a = 0;
    qulonglong b = 0;
    if (!parseU64(lhs, &a) || !parseU64(rhs, &b)) {
        return {};
    }
    return QString::number(a + b);
}

} // namespace AmountUtils
