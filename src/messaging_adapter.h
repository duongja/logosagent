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

    void setLogosModules(LogosModules* modules);
    void setState(AgentState* state);
    void setInboundHandler(InboundHandler handler);

    void wireEvents();
    QJsonObject init(const QJsonObject& config);
    QJsonObject send(const QJsonObject& params);
    QJsonObject join(const QJsonObject& params);
    QJsonObject createGroup(const QJsonObject& params);
    QJsonObject status() const;

    QJsonObject deliverySend(const QString& topic, const QJsonObject& payload);
    QJsonObject deliverySubscribe(const QString& topic);

private:
    QJsonObject initChat(const QJsonObject& chatCfg);
    QJsonObject initDelivery(const QJsonObject& deliveryCfg);
    void recordMessage(const QJsonObject& message);

    LogosModules* m_logos = nullptr;
    AgentState* m_state = nullptr;
    InboundHandler m_inboundHandler;
    bool m_chatStarted = false;
    bool m_deliveryStarted = false;
};

#endif
