#ifndef LOGOS_AGENT_MESSAGING_ADAPTER_H
#define LOGOS_AGENT_MESSAGING_ADAPTER_H

#include <QJsonObject>
#include <QString>
#include <functional>

class AgentState;
class LogosModules;

class MessagingAdapter
{
public:
    using InboundHandler = std::function<void(const QString& channel, const QJsonObject& payload)>;
    using StartCallback = std::function<void(const QJsonObject& result)>;

    void setLogosModules(LogosModules* modules);
    void setState(AgentState* state);
    void setInboundHandler(InboundHandler handler);

    void wireEvents();
    QJsonObject init(const QJsonObject& config);
    QJsonObject init(const QJsonObject& config, bool asyncStart, StartCallback callback = {});
    QJsonObject send(const QJsonObject& params);
    QJsonObject join(const QJsonObject& params);
    QJsonObject createGroup(const QJsonObject& params);
    QJsonObject status() const;

    QJsonObject deliverySend(const QString& topic, const QJsonObject& payload);
    QJsonObject deliverySubscribe(const QString& topic);

private:
    QJsonObject initChat(const QJsonObject& chatCfg);
    QJsonObject initDelivery(const QJsonObject& deliveryCfg, bool asyncStart, StartCallback callback = {});
    void recordMessage(const QJsonObject& message);
    void recordDeliveryConnectionState(const QString& status);

    LogosModules* m_logos = nullptr;
    AgentState* m_state = nullptr;
    InboundHandler m_inboundHandler;
    bool m_chatStarting = false;
    bool m_chatStarted = false;
    bool m_deliveryStarting = false;
    bool m_deliveryStarted = false;
    QString m_deliveryConnectionStatus;
    QString m_chatLastError;
    QString m_deliveryLastError;
};

#endif
