#include <logos_test.h>

#include "agent_state.h"
#include "skill_registry.h"

#include <QDir>

LOGOS_TEST(state_persists_files_and_approvals)
{
    const QString path = QDir::tempPath() + QStringLiteral("/logos-agent-test-state");
    AgentState state;
    state.setPersistencePath(path);
    LOGOS_ASSERT_TRUE(state.load());
    state.addFile(QJsonObject{{QStringLiteral("address"), QStringLiteral("cid-1")}, {QStringLiteral("label"), QStringLiteral("doc")}});
    state.addApproval(QJsonObject{{QStringLiteral("approval_id"), QStringLiteral("appr-1")}, {QStringLiteral("status"), QStringLiteral("pending")}});
    LOGOS_ASSERT_TRUE(state.save());

    AgentState reloaded;
    reloaded.setPersistencePath(path);
    LOGOS_ASSERT_TRUE(reloaded.load());
    LOGOS_ASSERT_EQ(reloaded.files().size(), 1);
    LOGOS_ASSERT_EQ(reloaded.approvals().size(), 1);
}

LOGOS_TEST(state_persists_replay_nonces)
{
    const QString path = QDir::tempPath() + QStringLiteral("/logos-agent-test-replay-state");
    AgentState state;
    state.setPersistencePath(path);
    LOGOS_ASSERT_TRUE(state.load());
    state.addReplayNonce(QStringLiteral("ed25519:key"), QStringLiteral("msg_1"), QStringLiteral("2026-06-09T00:00:00Z"));
    state.addReplayNonce(QStringLiteral("ed25519:key"), QStringLiteral("msg_1"), QStringLiteral("2026-06-09T00:00:01Z"));
    LOGOS_ASSERT_TRUE(state.save());

    AgentState reloaded;
    reloaded.setPersistencePath(path);
    LOGOS_ASSERT_TRUE(reloaded.load());
    LOGOS_ASSERT_TRUE(reloaded.hasReplayNonce(QStringLiteral("ed25519:key"), QStringLiteral("msg_1")));
    LOGOS_ASSERT_FALSE(reloaded.hasReplayNonce(QStringLiteral("ed25519:key"), QStringLiteral("msg_2")));
    LOGOS_ASSERT_EQ(reloaded.replayNonces().size(), 1);
}

LOGOS_TEST(skill_registry_describes_registered_skill)
{
    SkillRegistry registry;
    registry.registerSkill(SkillDefinition{
        QStringLiteral("meta.status"),
        QStringLiteral("meta"),
        QStringLiteral("status"),
        QJsonObject{},
        QJsonObject{},
        QStringLiteral("0"),
        false,
        {}
    });
    LOGOS_ASSERT_TRUE(registry.contains(QStringLiteral("meta.status")));
    LOGOS_ASSERT_EQ(registry.describe().size(), 1);
}
