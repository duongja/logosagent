#ifndef LOGOS_AGENT_A2A_ADAPTER_H
#define LOGOS_AGENT_A2A_ADAPTER_H

#include <QJsonObject>
#include <QString>
#include <functional>

class AgentState;
class MessagingAdapter;
class WalletAdapter;

class A2AAdapter
{
public:
    using TaskExecutor = std::function<QJsonObject(const QString& skill, const QJsonObject& params, const QString& origin)>;

    void setState(AgentState* state);
    void setMessaging(MessagingAdapter* messaging);
    void setWallet(WalletAdapter* wallet);
    void setTaskExecutor(TaskExecutor executor);

    QJsonObject card() const;
    QJsonObject publishCard();
    QJsonObject start();
    QJsonObject discover(const QJsonObject& params);
    QJsonObject task(const QJsonObject& params);
    QJsonObject subscribe(const QJsonObject& params);
    QJsonObject cancel(const QJsonObject& params);
    void handleInbound(const QString& topic, const QJsonObject& payload);

private:
    QString discoveryTopic(const QJsonObject& params = QJsonObject{}) const;
    QString taskTopic(const QString& address) const;
    QString statusTopic(const QString& taskId) const;
    QString localAgentAddress() const;
    bool isTaskTopicForSelf(const QString& topic) const;
    bool isTaskSubmitAddressedToSelf(const QString& topic, const QJsonObject& task) const;
    bool amountIsPositive(const QString& amount) const;
    QString paymentRecipientFromParams(const QJsonObject& params) const;
    QString paymentModeFromParams(const QJsonObject& params) const;
    QJsonObject payForTask(const QJsonObject& params);
    QJsonObject refundForCanceledTask(const QJsonObject& task);
    QJsonObject signingIdentity() const;
    QJsonObject envelope(const QString& kind, QJsonObject payload) const;
    QJsonObject statusEnvelopePayload(const QJsonObject& task, const QString& state, const QJsonObject& result = QJsonObject{}) const;
    void executeSubmittedTask(const QString& topic, const QJsonObject& task);
    bool verifyEnvelope(const QJsonObject& envelope) const;
    bool rememberEnvelopeNonce(const QJsonObject& envelope);

    AgentState* m_state = nullptr;
    MessagingAdapter* m_messaging = nullptr;
    WalletAdapter* m_wallet = nullptr;
    TaskExecutor m_taskExecutor;
};

#endif
