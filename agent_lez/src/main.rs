use anyhow::{Context, Result};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::io::{self, Read};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

fn main() {
    if let Err(err) = run() {
        println!(
            "{}",
            json!({"ok": false, "code": "agent_lez.error", "error": err.to_string()})
        );
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let command = env::args().nth(1).unwrap_or_else(|| "help".to_string());
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let params: Value = if input.trim().is_empty() {
        json!({})
    } else {
        serde_json::from_str(&input).context("stdin must be a JSON object")?
    };

    let output = match command.as_str() {
        "deploy" => deploy(&params)?,
        "call" => call(&params)?,
        "query" => query(&params)?,
        "inspect" => inspect(&params)?,
        _ => json!({
            "ok": false,
            "code": "agent_lez.unknown_command",
            "error": "expected one of deploy, call, query, inspect"
        }),
    };
    println!("{}", serde_json::to_string(&output)?);
    if !output.get("ok").and_then(Value::as_bool).unwrap_or(false) {
        std::process::exit(2);
    }
    Ok(())
}

fn deploy(params: &Value) -> Result<Value> {
    let path = required_str(params, "binary_path")?;
    let bytes = fs::read(path).with_context(|| format!("failed to read {path}"))?;
    let fallback_program_id = sha256_hex(&bytes);
    let program_id =
        inspect_program_id(params, path).unwrap_or_else(|| fallback_program_id.clone());

    let wallet = binary(params, "wallet_bin", "wallet");
    let output = run_tool(
        params,
        &wallet,
        ["deploy-program".to_string(), path.to_string()],
        &format!("failed to execute `{wallet} deploy-program`"),
    )?;

    Ok(json!({
        "ok": output.success,
        "mode": "wallet-cli",
        "program_id": program_id,
        "program_id_source": if program_id == fallback_program_id { "sha256-fallback" } else { "spel" },
        "binary_path": path,
        "exit_code": output.exit_code,
        "timed_out": output.timed_out,
        "stdout": output.stdout.trim(),
        "stderr": output.stderr.trim()
    }))
}

fn call(params: &Value) -> Result<Value> {
    if let Some(wallet_args) = wallet_call_args(params)? {
        let wallet = binary(params, "wallet_bin", "wallet");
        let output = run_tool(
            params,
            &wallet,
            wallet_args.clone(),
            &format!("failed to execute wallet call with `{wallet}`"),
        )?;

        return Ok(json!({
            "ok": output.success,
            "mode": "wallet-cli",
            "wallet": wallet,
            "wallet_args": wallet_args,
            "exit_code": output.exit_code,
            "timed_out": output.timed_out,
            "stdout": output.stdout.trim(),
            "stderr": output.stderr.trim()
        }));
    }

    let runner = params.get("runner").and_then(Value::as_str).context(
        "program.call requires wallet_args, wallet_command, a known program/instruction facade, or runner",
    )?;
    let args = string_array(params, "args")?;

    let output = run_tool(
        params,
        runner,
        args.clone(),
        &format!("failed to execute program runner `{runner}`"),
    )?;

    Ok(json!({
        "ok": output.success,
        "mode": "runner-cli",
        "runner": runner,
        "args": args,
        "exit_code": output.exit_code,
        "timed_out": output.timed_out,
        "stdout": output.stdout.trim(),
        "stderr": output.stderr.trim()
    }))
}

fn query(params: &Value) -> Result<Value> {
    let wallet = binary(params, "wallet_bin", "wallet");
    let target = params
        .get("target")
        .and_then(Value::as_str)
        .unwrap_or("latest_block");

    let args = match target {
        "account" => vec![
            "account".to_string(),
            "get".to_string(),
            "--account-id".to_string(),
            required_str(params, "account_id")?.to_string(),
        ],
        "block" => vec![
            "chain-info".to_string(),
            "block".to_string(),
            "--id".to_string(),
            required_str(params, "block_id")?.to_string(),
        ],
        "transaction" => vec![
            "chain-info".to_string(),
            "transaction".to_string(),
            "--hash".to_string(),
            required_str(params, "tx_hash")?.to_string(),
        ],
        "health" => vec!["check-health".to_string()],
        other => {
            return Ok(json!({
                "ok": false,
                "code": "agent_lez.unsupported_query_target",
                "error": format!("unsupported query target for wallet CLI bridge: {other}")
            }));
        }
    };

    let output = run_tool(
        params,
        &wallet,
        args,
        &format!("failed to execute wallet query with `{wallet}`"),
    )?;

    Ok(json!({
        "ok": output.success,
        "mode": "wallet-cli",
        "target": target,
        "exit_code": output.exit_code,
        "timed_out": output.timed_out,
        "stdout": output.stdout.trim(),
        "stderr": output.stderr.trim()
    }))
}

fn inspect(params: &Value) -> Result<Value> {
    let path = required_str(params, "binary_path")?;
    let bytes = fs::read(path).with_context(|| format!("failed to read {path}"))?;
    let fallback_program_id = sha256_hex(&bytes);
    let program_id = inspect_program_id(params, path);
    Ok(json!({
        "ok": true,
        "binary_path": path,
        "program_id": program_id.clone().unwrap_or_else(|| fallback_program_id.clone()),
        "program_id_source": if program_id.is_some() { "spel" } else { "sha256-fallback" },
        "sha256": fallback_program_id
    }))
}

fn inspect_program_id(params: &Value, path: &str) -> Option<String> {
    let spel = binary(params, "spel_bin", "spel");
    let output = Command::new(spel)
        .arg("inspect")
        .arg(path)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        if let Some((_, value)) = line.split_once("program_id") {
            let cleaned = value
                .trim_matches(|c: char| c == ':' || c == '"' || c.is_whitespace())
                .to_string();
            if !cleaned.is_empty() {
                return Some(cleaned);
            }
        }
    }
    text.split_whitespace()
        .find(|token| token.len() >= 32)
        .map(|s| s.trim_matches('"').to_string())
}

fn tool_env(params: &Value) -> Vec<(String, String)> {
    let mut envs = Vec::new();
    if let Some(home) = params
        .get("wallet_home")
        .or_else(|| params.pointer("/wallet/home"))
        .and_then(Value::as_str)
    {
        envs.push(("LEE_WALLET_HOME_DIR".to_string(), home.to_string()));
        envs.push(("NSSA_WALLET_HOME_DIR".to_string(), home.to_string()));
    }
    if let Some(extra) = params.get("env").and_then(Value::as_object) {
        for (k, v) in extra {
            if let Some(s) = v.as_str() {
                envs.push((k.clone(), s.to_string()));
            }
        }
    }
    envs
}

fn binary(params: &Value, key: &str, default: &str) -> String {
    params
        .get(key)
        .or_else(|| params.pointer(&format!("/tools/{key}")))
        .and_then(Value::as_str)
        .unwrap_or(default)
        .to_string()
}

struct ToolOutput {
    success: bool,
    exit_code: Option<i32>,
    timed_out: bool,
    stdout: String,
    stderr: String,
}

fn run_tool<I>(params: &Value, program: &str, args: I, context: &str) -> Result<ToolOutput>
where
    I: IntoIterator<Item = String>,
{
    let timeout = timeout(params);
    let mut child = Command::new(program)
        .args(args)
        .envs(tool_env(params))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| context.to_string())?;

    let deadline = Instant::now() + timeout;
    let mut timed_out = false;
    loop {
        if child.try_wait()?.is_some() {
            break;
        }
        if Instant::now() >= deadline {
            timed_out = true;
            child.kill().ok();
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }

    let output = child.wait_with_output()?;
    Ok(ToolOutput {
        success: !timed_out && output.status.success(),
        exit_code: output.status.code(),
        timed_out,
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

fn timeout(params: &Value) -> Duration {
    let millis = params
        .get("timeout_ms")
        .and_then(Value::as_u64)
        .filter(|value| *value > 0)
        .unwrap_or(120_000);
    Duration::from_millis(millis)
}

fn wallet_call_args(params: &Value) -> Result<Option<Vec<String>>> {
    if params.get("wallet_args").is_some() {
        return Ok(Some(string_array(params, "wallet_args")?));
    }

    if let Some(command) = params.get("wallet_command") {
        let mut args = command_tokens(command)?;
        args.extend(string_array(params, "args")?);
        return Ok(Some(args));
    }

    let program = params
        .get("program")
        .or_else(|| params.get("program_id"))
        .and_then(Value::as_str);
    let instruction = params.get("instruction").and_then(Value::as_str);
    let Some(program) = program else {
        return Ok(None);
    };
    let Some(instruction) = instruction else {
        return Ok(None);
    };

    let facade = program.trim().to_ascii_lowercase();
    if matches!(facade.as_str(), "auth-transfer" | "auth_transfer") {
        return Ok(Some(auth_transfer_args(instruction, params)?));
    }
    if matches!(facade.as_str(), "token" | "ata" | "amm" | "pinata") {
        let mut args = vec![facade, instruction.to_string()];
        args.extend(flag_args(params.get("params").unwrap_or(params))?);
        return Ok(Some(args));
    }

    Ok(None)
}

fn auth_transfer_args(instruction: &str, params: &Value) -> Result<Vec<String>> {
    let mut args = vec!["auth-transfer".to_string(), instruction.to_string()];
    let call_params = params.get("params").unwrap_or(params);
    args.extend(flag_args(call_params)?);
    Ok(args)
}

fn command_tokens(value: &Value) -> Result<Vec<String>> {
    if let Some(s) = value.as_str() {
        let tokens = s
            .split_whitespace()
            .filter(|token| !token.is_empty())
            .map(str::to_owned)
            .collect::<Vec<_>>();
        if tokens.is_empty() {
            anyhow::bail!("wallet_command cannot be empty");
        }
        return Ok(tokens);
    }
    if value.is_array() {
        return string_array_from_value(value, "wallet_command");
    }
    anyhow::bail!("wallet_command must be a string or array of strings")
}

fn string_array(params: &Value, key: &str) -> Result<Vec<String>> {
    match params.get(key) {
        Some(value) => string_array_from_value(value, key),
        None => Ok(Vec::new()),
    }
}

fn string_array_from_value(value: &Value, key: &str) -> Result<Vec<String>> {
    let values = value
        .as_array()
        .with_context(|| format!("{key} must be an array of strings"))?;
    let mut out = Vec::with_capacity(values.len());
    for value in values {
        let s = value
            .as_str()
            .with_context(|| format!("{key} must contain only strings"))?;
        out.push(s.to_string());
    }
    Ok(out)
}

fn flag_args(value: &Value) -> Result<Vec<String>> {
    let obj = value
        .as_object()
        .context("instruction params must be a JSON object")?;
    let mut out = Vec::new();
    for (key, value) in obj {
        if matches!(
            key.as_str(),
            "amount"
                | "env"
                | "helper_path"
                | "instruction"
                | "program"
                | "program_id"
                | "runner"
                | "timeout_ms"
                | "tools"
                | "wallet_bin"
                | "wallet_command"
                | "wallet_home"
        ) {
            continue;
        }
        let flag = format!("--{}", key.replace('_', "-"));
        match value {
            Value::Bool(true) => out.push(flag),
            Value::Bool(false) | Value::Null => {}
            Value::Array(values) => {
                for item in values {
                    out.push(flag.clone());
                    out.push(flag_value(item, key)?);
                }
            }
            other => {
                out.push(flag);
                out.push(flag_value(other, key)?);
            }
        }
    }
    Ok(out)
}

fn flag_value(value: &Value, key: &str) -> Result<String> {
    match value {
        Value::String(s) => Ok(s.to_string()),
        Value::Number(n) => Ok(n.to_string()),
        _ => anyhow::bail!("{key} flag value must be string, number, bool, or array"),
    }
}

fn required_str<'a>(params: &'a Value, key: &str) -> Result<&'a str> {
    params
        .get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.trim().is_empty())
        .with_context(|| format!("{key} is required"))
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}
