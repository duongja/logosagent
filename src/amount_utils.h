#ifndef LOGOS_AGENT_AMOUNT_UTILS_H
#define LOGOS_AGENT_AMOUNT_UTILS_H

#include <QString>

namespace AmountUtils {

QString decimalToLe16Hex(const QString& amountDecimal, QString* errorMessage = nullptr);
bool leqDecimal(const QString& lhs, const QString& rhs);
QString addDecimal(const QString& lhs, const QString& rhs);

} // namespace AmountUtils

#endif
