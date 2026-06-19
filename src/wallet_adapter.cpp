#include "wallet_adapter.h"

#include "agent_state.h"
#include "amount_utils.h"
#include "json_utils.h"
#include "logos_sdk.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>

namespace {

QString stripAccountPrefix(QString value, bool* isPublicFromPrefix = nullptr)
{
    value = value.trimmed();
    if (value.startsWith(QStringLiteral("Public/"))) {
        if (isPublicFromPrefix) {
            *isPublicFromPrefix = true;
        }
        return value.mid(QStringLiteral("Public/").size());
    }
    if (value.startsWith(QStringLiteral("Private/"))) {
        if (isPublicFromPrefix) {
            *isPublicFromPrefix = false;
        }
        return value.mid(QStringLiteral("Private/").size());
    }
    return value;
}

bool isHexBytes32(const QString& value)
{
    QString trimmed = value.trimmed();
    if (trimmed.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive)) {
        trimmed = trimmed.mid(2);
    }
    if (trimmed.size() != 64) {
        return false;
    }
    for (const QChar ch : trimmed) {
        if (!ch.isDigit()
            && (ch < QLatin1Char('a') || ch > QLatin1Char('f'))
            && (ch < QLatin1Char('A') || ch > QLatin1Char('F'))) {
            return false;
        }
    }
    return true;
}

QString normalizeHexBytes32(QString value)
{
    value = value.trimmed();
    if (value.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive)) {
        value = value.mid(2);
    }
    return value.toLower();
}

QJsonObject parseFfiResult(const QString& response)
{
    QJsonObject parsed;
    if (response.trimmed().startsWith(QLatin1Char('{'))) {
        QString err;
        parsed = JsonUtils::parseObject(response, &err);
    }
    if (parsed.isEmpty()) {
        parsed.insert(QStringLiteral("raw"), response);
        parsed.insert(QStringLiteral("success"), !response.startsWith(QStringLiteral("Error:"), Qt::CaseInsensitive));
    }
    return parsed;
}

} // namespace

void WalletAdapter::setLogosModules(LogosModules* modules)
{
    m_logos = modules;
}

void WalletAdapter::setState(AgentState* state)
{
    m_state = state;
}

QJsonObject WalletAdapter::init(const QJsonObject& config)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("wallet.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }

    const QJsonObject walletCfg = config.value(QStringLiteral("wallet")).toObject();
    const QString configPath = walletCfg.value(QStringLiteral("config_path")).toString();
    const QString storagePath = walletCfg.value(QStringLiteral("storage_path")).toString();
    const QString password = walletCfg.value(QStringLiteral("password")).toString();

    int rc = 0;
    if (!configPath.isEmpty() && !storagePath.isEmpty()) {
        if (walletCfg.value(QStringLiteral("create")).toBool(false)) {
            rc = m_logos->logos_execution_zone.create_new(configPath, storagePath, password);
        } else {
            rc = m_logos->logos_execution_zone.open(configPath, storagePath);
        }
        if (rc != 0) {
            return JsonUtils::error(QStringLiteral("wallet.open_failed"), QStringLiteral("LEZ wallet open/create failed"), QJsonObject{{QStringLiteral("code"), rc}});
        }
        m_walletOpen = true;
    }

    QJsonObject registration;
    if (m_walletOpen) {
        const QString importPrivateKey = walletCfg.value(QStringLiteral("public_import_private_key_hex")).toString();
        const QStringList publicAccountsBeforeImport = ownedAccountHexes(true);
        QString importedPublicAccount;
        if (!importPrivateKey.trimmed().isEmpty()) {
            const int importRc = m_logos->logos_execution_zone.import_public_account(importPrivateKey);
            if (importRc != 0) {
                return JsonUtils::error(
                    QStringLiteral("wallet.import_public_failed"),
                    QStringLiteral("LEZ wallet public account import failed"),
                    QJsonObject{{QStringLiteral("code"), importRc}});
            }
            m_logos->logos_execution_zone.save();

            const QStringList publicAccountsAfterImport = ownedAccountHexes(true);
            for (const QString& accountHex : publicAccountsAfterImport) {
                if (!publicAccountsBeforeImport.contains(accountHex)) {
                    importedPublicAccount = accountHex;
                    break;
                }
            }
        }

        const QString configuredAccount = walletCfg.value(QStringLiteral("public_import_account")).toString();
        if (!configuredAccount.isEmpty()) {
            QString normalizeErr;
            const QString accountHex = normalizeAccountIdForFfi(configuredAccount, &normalizeErr);
            if (accountHex.isEmpty()) {
                return JsonUtils::error(QStringLiteral("wallet.invalid_import_account"), normalizeErr);
            }
            if (!walletOwnsAccount(accountHex, true)) {
                return JsonUtils::error(
                    QStringLiteral("wallet.import_account_not_owned"),
                    QStringLiteral("configured public_import_account is not owned by the opened LEZ wallet"),
                    QJsonObject{
                        {QStringLiteral("configured_account"), configuredAccount},
                        {QStringLiteral("account_hex"), accountHex},
                        {QStringLiteral("wallet_accounts"), ownedAccountsDiagnostic()}
                    });
            }
            setAgentAccount(accountHex, true);
        } else if (!importedPublicAccount.isEmpty()) {
            setAgentAccount(importedPublicAccount, true);
        } else if (!importPrivateKey.trimmed().isEmpty()) {
            return JsonUtils::error(
                QStringLiteral("wallet.import_public_unverified"),
                QStringLiteral("public key import returned success, but no imported public account was visible in list_accounts"),
                QJsonObject{{QStringLiteral("wallet_accounts"), ownedAccountsDiagnostic()}});
        }

        if (agentAccount().isEmpty() && walletCfg.value(QStringLiteral("create_agent_account")).toBool(true)) {
            const QString type = walletCfg.value(QStringLiteral("create_agent_account_type")).toString(QStringLiteral("private"));
            const bool isPublic = type == QStringLiteral("public");
            const QString account = isPublic
                ? m_logos->logos_execution_zone.create_account_public()
                : m_logos->logos_execution_zone.create_account_private();
            if (!account.isEmpty()) {
                setAgentAccount(account, isPublic);
                if (isPublic && walletCfg.value(QStringLiteral("register_agent_account")).toBool(false)) {
                    sync();
                    const QJsonObject result = parseFfiResult(m_logos->logos_execution_zone.register_public_account(account));
                    QJsonObject tx{
                        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
                        {QStringLiteral("type"), QStringLiteral("wallet.register_public_account")},
                        {QStringLiteral("account"), account},
                        {QStringLiteral("result"), result}
                    };
                    if (m_state) {
                        m_state->addTransaction(tx);
                        m_state->save();
                    }
                    registration = tx;
                    if (!result.value(QStringLiteral("success")).toBool(false)) {
                        return JsonUtils::error(
                            QStringLiteral("wallet.registration_failed"),
                            result.value(QStringLiteral("error")).toString(QStringLiteral("LEZ wallet account registration failed")),
                            QJsonObject{{QStringLiteral("registration"), registration}});
                    }
                    sync();
                }
            }
        }
    }

    QJsonObject out{
        {QStringLiteral("wallet_open"), m_walletOpen},
        {QStringLiteral("account"), account()}
    };
    if (!registration.isEmpty()) {
        out.insert(QStringLiteral("registration"), registration);
    }
    return JsonUtils::ok(out);
}

QJsonObject WalletAdapter::balance()
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("wallet.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    if (!m_walletOpen) {
        return JsonUtils::error(QStringLiteral("wallet.not_open"), QStringLiteral("LEZ wallet is not open"));
    }
    QString normalizeErr;
    const QString accountId = normalizeAccountIdForFfi(agentAccount(), &normalizeErr);
    if (accountId.isEmpty()) {
        return JsonUtils::error(
            QStringLiteral("wallet.no_account"),
            normalizeErr.isEmpty() ? QStringLiteral("agent LEZ account is not configured") : normalizeErr);
    }
    sync();
    const QString bal = m_logos->logos_execution_zone.get_balance(accountId, agentAccountIsPublic());
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("account"), accountId},
        {QStringLiteral("is_public"), agentAccountIsPublic()},
        {QStringLiteral("balance"), bal}
    });
}

QJsonObject WalletAdapter::send(const QJsonObject& params)
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("wallet.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    if (!m_walletOpen) {
        return JsonUtils::error(QStringLiteral("wallet.not_open"), QStringLiteral("LEZ wallet is not open"));
    }
    QString err;
    const QString recipient = JsonUtils::requireString(params, QStringLiteral("recipient"), &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("wallet.invalid_params"), err);
    }
    const QString amount = params.value(QStringLiteral("amount")).toVariant().toString();
    const QString from = params.value(QStringLiteral("from")).toString(agentAccount());
    const QString mode = params.value(QStringLiteral("mode")).toString(QStringLiteral("private_owned"));
    QString amountErr;
    const QString amountHex = AmountUtils::decimalToLe16Hex(amount, &amountErr);
    if (!amountErr.isEmpty()) {
        return JsonUtils::error(QStringLiteral("wallet.invalid_amount"), amountErr);
    }
    if (from.isEmpty()) {
        return JsonUtils::error(QStringLiteral("wallet.no_account"), QStringLiteral("agent LEZ account is not configured"));
    }
    QString normalizeErr;
    const QString fromForFfi = normalizeAccountIdForFfi(from, &normalizeErr);
    if (fromForFfi.isEmpty()) {
        return JsonUtils::error(QStringLiteral("wallet.invalid_account"), normalizeErr);
    }

    sync();

    QString response;
    if (mode == QStringLiteral("public")) {
        const QString recipientForFfi = normalizeAccountIdForFfi(recipient, &normalizeErr);
        if (recipientForFfi.isEmpty()) {
            return JsonUtils::error(QStringLiteral("wallet.invalid_recipient"), normalizeErr);
        }
        if (!walletOwnsAccount(fromForFfi, true)) {
            return JsonUtils::error(
                QStringLiteral("wallet.account_not_owned"),
                QStringLiteral("source public account is not owned by the opened LEZ wallet"),
                QJsonObject{
                    {QStringLiteral("from"), from},
                    {QStringLiteral("from_hex"), fromForFfi},
                    {QStringLiteral("wallet_accounts"), ownedAccountsDiagnostic()}
                });
        }
        response = m_logos->logos_execution_zone.transfer_public(fromForFfi, recipientForFfi, amountHex);
    } else if (mode == QStringLiteral("private")) {
        QString keysPayload = recipient;
        if (!keysPayload.trimmed().startsWith(QLatin1Char('{'))) {
            const QString recipientForFfi = normalizeAccountIdForFfi(recipient, &normalizeErr);
            if (recipientForFfi.isEmpty()) {
                return JsonUtils::error(QStringLiteral("wallet.invalid_recipient"), normalizeErr);
            }
            const QString resolved = m_logos->logos_execution_zone.get_private_account_keys(recipientForFfi);
            if (!resolved.isEmpty()) {
                keysPayload = resolved;
            }
        }
        response = m_logos->logos_execution_zone.transfer_private(fromForFfi, keysPayload, amountHex);
    } else if (mode == QStringLiteral("shielded")) {
        response = m_logos->logos_execution_zone.transfer_shielded(fromForFfi, recipient, amountHex);
    } else if (mode == QStringLiteral("deshielded")) {
        const QString recipientForFfi = normalizeAccountIdForFfi(recipient, &normalizeErr);
        if (recipientForFfi.isEmpty()) {
            return JsonUtils::error(QStringLiteral("wallet.invalid_recipient"), normalizeErr);
        }
        response = m_logos->logos_execution_zone.transfer_deshielded(fromForFfi, recipientForFfi, amountHex);
    } else if (mode == QStringLiteral("shielded_owned")) {
        const QString recipientForFfi = normalizeAccountIdForFfi(recipient, &normalizeErr);
        if (recipientForFfi.isEmpty()) {
            return JsonUtils::error(QStringLiteral("wallet.invalid_recipient"), normalizeErr);
        }
        response = m_logos->logos_execution_zone.transfer_shielded_owned(fromForFfi, recipientForFfi, amountHex);
    } else {
        const QString recipientForFfi = normalizeAccountIdForFfi(recipient, &normalizeErr);
        if (recipientForFfi.isEmpty()) {
            return JsonUtils::error(QStringLiteral("wallet.invalid_recipient"), normalizeErr);
        }
        response = m_logos->logos_execution_zone.transfer_private_owned(fromForFfi, recipientForFfi, amountHex);
    }

    return parseTransferResult(response, amount, recipient);
}

QJsonObject WalletAdapter::history() const
{
    if (!m_state) {
        return JsonUtils::error(QStringLiteral("wallet.unavailable"), QStringLiteral("state is not initialized"));
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("transactions"), m_state->transactions()}});
}

QJsonObject WalletAdapter::sync()
{
    if (!m_logos) {
        return JsonUtils::error(QStringLiteral("wallet.unavailable"), QStringLiteral("LogosModules is not initialized"));
    }
    if (!m_walletOpen) {
        return JsonUtils::error(QStringLiteral("wallet.not_open"), QStringLiteral("LEZ wallet is not open"));
    }
    const int current = m_logos->logos_execution_zone.get_current_block_height();
    int rc = 0;
    if (current > 0) {
        rc = m_logos->logos_execution_zone.sync_to_block(QString::number(current));
    }
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("current_block_height"), current},
        {QStringLiteral("last_synced_block"), m_logos->logos_execution_zone.get_last_synced_block()},
        {QStringLiteral("sync_code"), rc}
    });
}

QJsonObject WalletAdapter::account() const
{
    return QJsonObject{
        {QStringLiteral("account"), agentAccount()},
        {QStringLiteral("is_public"), agentAccountIsPublic()}
    };
}

QJsonObject WalletAdapter::parseTransferResult(const QString& response, const QString& amount, const QString& recipient)
{
    QJsonObject parsed = parseFfiResult(response);

    QJsonObject tx{
        {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("type"), QStringLiteral("wallet.send")},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("recipient"), recipient},
        {QStringLiteral("spending_controlled"), true},
        {QStringLiteral("result"), parsed}
    };
    if (m_state) {
        m_state->addTransaction(tx);
        m_state->save();
    }
    if (!parsed.value(QStringLiteral("success")).toBool(false)) {
        return JsonUtils::error(
            QStringLiteral("wallet.transfer_failed"),
            parsed.value(QStringLiteral("error")).toString(QStringLiteral("LEZ wallet transfer failed")),
            QJsonObject{{QStringLiteral("transaction"), tx}});
    }
    return JsonUtils::ok(QJsonObject{{QStringLiteral("transaction"), tx}});
}

QStringList WalletAdapter::ownedAccountHexes(bool isPublic) const
{
    QStringList accounts;
    if (!m_logos || !m_walletOpen) {
        return accounts;
    }
    const QJsonArray listed = m_logos->logos_execution_zone.list_accounts();
    for (const QJsonValue& value : listed) {
        const QJsonObject account = value.toObject();
        if (account.value(QStringLiteral("is_public")).toBool(false) != isPublic) {
            continue;
        }
        const QString accountHex = normalizeHexBytes32(account.value(QStringLiteral("account_id")).toString());
        if (!accountHex.isEmpty()) {
            accounts.append(accountHex);
        }
    }
    return accounts;
}

QJsonArray WalletAdapter::ownedAccountsDiagnostic() const
{
    QJsonArray out;
    if (!m_logos || !m_walletOpen) {
        return out;
    }
    const QJsonArray listed = m_logos->logos_execution_zone.list_accounts();
    for (const QJsonValue& value : listed) {
        const QJsonObject account = value.toObject();
        QJsonObject item = account;
        const QString accountHex = normalizeHexBytes32(account.value(QStringLiteral("account_id")).toString());
        if (!accountHex.isEmpty()) {
            item.insert(QStringLiteral("account_id"), accountHex);
            const QString base58 = m_logos->logos_execution_zone.account_id_to_base58(accountHex);
            if (!base58.isEmpty()) {
                item.insert(QStringLiteral("account"), base58);
            }
        }
        out.append(item);
    }
    return out;
}

bool WalletAdapter::walletOwnsAccount(const QString& accountHex, bool isPublic) const
{
    const QString normalized = normalizeHexBytes32(accountHex);
    if (normalized.isEmpty()) {
        return false;
    }
    return ownedAccountHexes(isPublic).contains(normalized);
}

QString WalletAdapter::agentAccount() const
{
    if (!m_state) {
        return {};
    }
    const QJsonObject identity = m_state->identity();
    return identity.value(QStringLiteral("lez_account")).toString(identity.value(QStringLiteral("lez_account_hex")).toString());
}

bool WalletAdapter::agentAccountIsPublic() const
{
    if (!m_state) {
        return false;
    }
    return m_state->identity().value(QStringLiteral("lez_account_is_public")).toBool(false);
}

QJsonObject WalletAdapter::setAgentAccount(const QString& accountHex, bool isPublic)
{
    if (!m_state) {
        return JsonUtils::error(QStringLiteral("wallet.unavailable"), QStringLiteral("state is not initialized"));
    }
    QJsonObject nextConfig = m_state->config();
    QJsonObject identity = nextConfig.value(QStringLiteral("identity")).toObject();
    const QString address = m_logos ? m_logos->logos_execution_zone.account_id_to_base58(accountHex) : QString();
    identity.insert(QStringLiteral("lez_account"), address.isEmpty() ? accountHex : address);
    identity.insert(QStringLiteral("lez_account_hex"), accountHex);
    identity.insert(QStringLiteral("lez_account_is_public"), isPublic);
    nextConfig.insert(QStringLiteral("identity"), identity);
    m_state->setConfig(nextConfig);
    m_state->save();
    return JsonUtils::ok(QJsonObject{
        {QStringLiteral("account"), identity.value(QStringLiteral("lez_account")).toString()},
        {QStringLiteral("account_hex"), accountHex},
        {QStringLiteral("is_public"), isPublic}
    });
}

QString WalletAdapter::normalizeAccountIdForFfi(const QString& account, QString* errorMessage) const
{
    if (!m_logos) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("LogosModules is not initialized");
        }
        return {};
    }

    const QString stripped = stripAccountPrefix(account);
    if (stripped.isEmpty()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("account id is empty");
        }
        return {};
    }
    if (isHexBytes32(stripped)) {
        return normalizeHexBytes32(stripped);
    }

    const QString converted = m_logos->logos_execution_zone.account_id_from_base58(stripped);
    if (converted.isEmpty()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("account id must be a 32-byte hex value or a valid LEZ base58 address");
        }
        return {};
    }
    return converted;
}
