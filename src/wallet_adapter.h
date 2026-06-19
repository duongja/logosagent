#ifndef LOGOS_AGENT_WALLET_ADAPTER_H
#define LOGOS_AGENT_WALLET_ADAPTER_H

#include <QJsonObject>
#include <QString>
#include <QStringList>

class AgentState;
class LogosModules;

class WalletAdapter
{
public:
    void setLogosModules(LogosModules* modules);
    void setState(AgentState* state);

    QJsonObject init(const QJsonObject& config);
    QJsonObject balance();
    QJsonObject send(const QJsonObject& params);
    QJsonObject history() const;
    QJsonObject sync();
    QJsonObject account() const;

private:
    QJsonObject parseTransferResult(const QString& response, const QString& amount, const QString& recipient);
    QStringList ownedAccountHexes(bool isPublic) const;
    QJsonArray ownedAccountsDiagnostic() const;
    bool walletOwnsAccount(const QString& accountHex, bool isPublic) const;
    QString agentAccount() const;
    bool agentAccountIsPublic() const;
    QJsonObject setAgentAccount(const QString& accountHex, bool isPublic);
    QString normalizeAccountIdForFfi(const QString& account, QString* errorMessage = nullptr) const;

    LogosModules* m_logos = nullptr;
    AgentState* m_state = nullptr;
    bool m_walletOpen = false;
};

#endif
