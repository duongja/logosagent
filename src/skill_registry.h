#ifndef LOGOS_AGENT_SKILL_REGISTRY_H
#define LOGOS_AGENT_SKILL_REGISTRY_H

#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QString>
#include <QStringList>
#include <functional>

class AgentRuntime;

struct SkillDefinition
{
    QString name;
    QString category;
    QString description;
    QJsonObject inputSchema;
    QJsonObject outputSchema;
    QString price;
    bool spendsTokens = false;
    std::function<QJsonObject(AgentRuntime&, const QJsonObject&, const QString&)> handler;
};

class SkillRegistry
{
public:
    void registerSkill(const SkillDefinition& definition);
    bool contains(const QString& name) const;
    SkillDefinition definition(const QString& name) const;
    QJsonArray describe() const;
    QStringList names() const;

private:
    QMap<QString, SkillDefinition> m_skills;
};

#endif
