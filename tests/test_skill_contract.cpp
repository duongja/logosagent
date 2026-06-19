#include <logos_test.h>

#include <QDir>
#include <QFile>
#include <QStringList>

LOGOS_TEST(default_skill_contract_is_registered)
{
    QFile source(QDir(QStringLiteral(LOGOS_AGENT_SOURCE_DIR)).filePath(QStringLiteral("src/agent_runtime.cpp")));
    LOGOS_ASSERT_TRUE(source.open(QIODevice::ReadOnly | QIODevice::Text));
    const QString text = QString::fromUtf8(source.readAll());

    const QStringList required{
        QStringLiteral("storage.upload"),
        QStringLiteral("storage.download"),
        QStringLiteral("storage.list"),
        QStringLiteral("storage.share"),
        QStringLiteral("messaging.send"),
        QStringLiteral("messaging.join"),
        QStringLiteral("messaging.create_group"),
        QStringLiteral("wallet.balance"),
        QStringLiteral("wallet.send"),
        QStringLiteral("wallet.history"),
        QStringLiteral("program.query"),
        QStringLiteral("program.call"),
        QStringLiteral("program.deploy"),
        QStringLiteral("agent.card"),
        QStringLiteral("agent.discover"),
        QStringLiteral("agent.task"),
        QStringLiteral("agent.subscribe"),
        QStringLiteral("agent.cancel"),
        QStringLiteral("meta.skills"),
        QStringLiteral("meta.status"),
        QStringLiteral("meta.configure")
    };

    for (const QString& skill : required) {
        LOGOS_ASSERT_TRUE(text.contains(QStringLiteral("QStringLiteral(\"%1\")").arg(skill)));
    }
}

LOGOS_TEST(a2a_task_lifecycle_hooks_are_wired)
{
    QFile adapter(QDir(QStringLiteral(LOGOS_AGENT_SOURCE_DIR)).filePath(QStringLiteral("src/a2a_adapter.cpp")));
    LOGOS_ASSERT_TRUE(adapter.open(QIODevice::ReadOnly | QIODevice::Text));
    const QString adapterText = QString::fromUtf8(adapter.readAll());

    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("task.submit")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("TASK_STATE_WORKING")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("TASK_STATE_COMPLETED")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("TASK_STATE_INPUT_REQUIRED")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("TASK_STATE_FAILED")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("m_taskExecutor")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("isTaskSubmitAddressedToSelf")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("isTaskTopicForSelf")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("payForTask(params)")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("payment_recipient")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("a2a.task.payment.received")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("refundForCanceledTask")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("a2a.task.payment.refund")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("payer")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("deliverySend(statusTopic(taskId)")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("/logos-agent/1/task-%1/json")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("/logos-agent/1/status-%1/json")));
    LOGOS_ASSERT_FALSE(adapterText.contains(QStringLiteral("/logos-agent/1/task/%1/json")));
    LOGOS_ASSERT_FALSE(adapterText.contains(QStringLiteral("/logos-agent/1/status/%1/json")));

    QFile runtime(QDir(QStringLiteral(LOGOS_AGENT_SOURCE_DIR)).filePath(QStringLiteral("src/agent_runtime.cpp")));
    LOGOS_ASSERT_TRUE(runtime.open(QIODevice::ReadOnly | QIODevice::Text));
    const QString runtimeText = QString::fromUtf8(runtime.readAll());
    LOGOS_ASSERT_TRUE(runtimeText.contains(QStringLiteral("setTaskExecutor")));
    LOGOS_ASSERT_TRUE(runtimeText.contains(QStringLiteral("m_a2a.start()")));
}

LOGOS_TEST(delivery_topics_follow_lip23_short_format)
{
    QFile adapter(QDir(QStringLiteral(LOGOS_AGENT_SOURCE_DIR)).filePath(QStringLiteral("src/a2a_adapter.cpp")));
    LOGOS_ASSERT_TRUE(adapter.open(QIODevice::ReadOnly | QIODevice::Text));
    const QString adapterText = QString::fromUtf8(adapter.readAll());

    QFile messaging(QDir(QStringLiteral(LOGOS_AGENT_SOURCE_DIR)).filePath(QStringLiteral("src/messaging_adapter.cpp")));
    LOGOS_ASSERT_TRUE(messaging.open(QIODevice::ReadOnly | QIODevice::Text));
    const QString messagingText = QString::fromUtf8(messaging.readAll());

    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("topicHash(address")));
    LOGOS_ASSERT_TRUE(adapterText.contains(QStringLiteral("topicHash(taskId")));
    LOGOS_ASSERT_TRUE(messagingText.contains(QStringLiteral("/logos-agent/1/group-%1/json")));
    LOGOS_ASSERT_FALSE(messagingText.contains(QStringLiteral("/logos-agent/1/group/%1/json")));
}
