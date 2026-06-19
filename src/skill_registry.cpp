#include "skill_registry.h"

void SkillRegistry::registerSkill(const SkillDefinition& definition)
{
    m_skills.insert(definition.name, definition);
}

bool SkillRegistry::contains(const QString& name) const
{
    return m_skills.contains(name);
}

SkillDefinition SkillRegistry::definition(const QString& name) const
{
    return m_skills.value(name);
}

QJsonArray SkillRegistry::describe() const
{
    QJsonArray out;
    for (auto it = m_skills.constBegin(); it != m_skills.constEnd(); ++it) {
        const SkillDefinition& d = it.value();
        out.append(QJsonObject{
            {QStringLiteral("name"), d.name},
            {QStringLiteral("category"), d.category},
            {QStringLiteral("description"), d.description},
            {QStringLiteral("input_schema"), d.inputSchema},
            {QStringLiteral("output_schema"), d.outputSchema},
            {QStringLiteral("price"), d.price},
            {QStringLiteral("spends_tokens"), d.spendsTokens}
        });
    }
    return out;
}

QStringList SkillRegistry::names() const
{
    return m_skills.keys();
}
