#include "program_adapter.h"

#include "agent_state.h"
#include "json_utils.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QProcess>

void ProgramAdapter::setState(AgentState* state)
{
    m_state = state;
}

QJsonObject ProgramAdapter::query(const QJsonObject& params)
{
    return runHelper(QStringLiteral("query"), params);
}

QJsonObject ProgramAdapter::call(const QJsonObject& params)
{
    QJsonObject result = runHelper(QStringLiteral("call"), params);
    if (m_state) {
        m_state->addTransaction(QJsonObject{
            {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
            {QStringLiteral("type"), QStringLiteral("program.call")},
            {QStringLiteral("amount"), params.value(QStringLiteral("amount")).toVariant().toString()},
            {QStringLiteral("spending_controlled"), true},
            {QStringLiteral("request"), params},
            {QStringLiteral("result"), result}
        });
        m_state->save();
    }
    return result;
}

QJsonObject ProgramAdapter::deploy(const QJsonObject& params)
{
    QJsonObject result = runHelper(QStringLiteral("deploy"), params);
    if (m_state) {
        m_state->addTransaction(QJsonObject{
            {QStringLiteral("created_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
            {QStringLiteral("type"), QStringLiteral("program.deploy")},
            {QStringLiteral("amount"), params.value(QStringLiteral("amount")).toVariant().toString().isEmpty()
                ? QStringLiteral("0")
                : params.value(QStringLiteral("amount")).toVariant().toString()},
            {QStringLiteral("spending_controlled"), true},
            {QStringLiteral("request"), params},
            {QStringLiteral("result"), result}
        });
        m_state->save();
    }
    return result;
}

QJsonObject ProgramAdapter::runHelper(const QString& command, const QJsonObject& params)
{
    const QString helper = params.value(QStringLiteral("helper_path")).toString(helperPath());
    if (helper.isEmpty()) {
        return JsonUtils::error(
            QStringLiteral("program.helper_missing"),
            QStringLiteral("agent_lez helper is not configured; build agent_lez and set program.helper_path"));
    }

    QProcess process;
    process.setProgram(helper);
    process.setArguments({command});
    process.start();
    if (!process.waitForStarted(5000)) {
        return JsonUtils::error(QStringLiteral("program.helper_start_failed"), process.errorString());
    }
    process.write(QJsonDocument(params).toJson(QJsonDocument::Compact));
    process.closeWriteChannel();
    if (!process.waitForFinished(params.value(QStringLiteral("timeout_ms")).toInt(120000))) {
        process.kill();
        return JsonUtils::error(QStringLiteral("program.helper_timeout"), QStringLiteral("agent_lez helper timed out"));
    }
    const QString stdoutText = QString::fromUtf8(process.readAllStandardOutput());
    const QString stderrText = QString::fromUtf8(process.readAllStandardError());
    QString err;
    QJsonObject parsed = JsonUtils::parseObject(stdoutText, &err);
    if (!err.isEmpty()) {
        return JsonUtils::error(QStringLiteral("program.helper_invalid_json"), err, QJsonObject{
            {QStringLiteral("stdout"), stdoutText.left(4096)},
            {QStringLiteral("stderr"), stderrText.left(4096)},
            {QStringLiteral("exit_code"), process.exitCode()}
        });
    }
    if (process.exitCode() != 0 && parsed.value(QStringLiteral("ok")).toBool(true)) {
        parsed.insert(QStringLiteral("ok"), false);
        parsed.insert(QStringLiteral("code"), QStringLiteral("program.helper_failed"));
        parsed.insert(QStringLiteral("stderr"), stderrText.left(4096));
    }
    return parsed;
}

QString ProgramAdapter::helperPath() const
{
    if (!m_state) {
        return {};
    }
    return m_state->config().value(QStringLiteral("program")).toObject().value(QStringLiteral("helper_path")).toString();
}
