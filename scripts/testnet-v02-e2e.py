#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import shlex
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid

TRANSCRIPT = []


def run(command, *, input_text=None, transcript=None):
    TRANSCRIPT.append(transcript or ("$ " + shlex.join(command)))
    proc = subprocess.run(command, input=input_text, text=True, capture_output=True)
    if proc.returncode:
        raise RuntimeError(f"command failed ({proc.returncode}): {shlex.join(command)}\n{proc.stderr}")
    return proc.stdout.strip()


def remote(agent, command):
    transport = agent.get("transport") or {"kind": "ssh"}
    kind = transport.get("kind", "ssh")
    if kind == "ssh":
        return run(["ssh", "-o", "BatchMode=yes", agent["host"], command])
    if kind == "railway-sandbox":
        required = ("cli", "sandbox_id", "project", "environment")
        missing = [key for key in required if not transport.get(key)]
        if missing:
            raise RuntimeError(f"Railway transport lacks: {', '.join(missing)}")
        return run([
            transport["cli"], "sandbox", "exec",
            "--id", transport["sandbox_id"],
            "--project", transport["project"],
            "--environment", transport["environment"],
            "--", command,
        ], transcript=f"$ railway-sandbox {shlex.quote(agent['host'])} -- {command}")
    raise RuntimeError(f"unsupported remote transport: {kind}")


def core_call(agent, method, *args):
    command = [agent["logoscore"], "--config-dir", agent["config_dir"], "--json", "call", "logos_agent", method, *args]
    raw = remote(agent, shlex.join(command))
    outer = json.loads(raw)
    if outer.get("status") != "ok":
        raise RuntimeError(f"{agent['agent_id']} {method} failed: {raw}")
    result = outer.get("result")
    if isinstance(result, str):
        result = json.loads(result)
    if not isinstance(result, dict) or result.get("ok") is not True:
        raise RuntimeError(f"{agent['agent_id']} {method} returned an error: {result!r}")
    return result


def invoke(agent, skill, params, run_id):
    payload = dict(params)
    payload["run_id"] = run_id
    return core_call(agent, "invoke", skill, json.dumps(payload, separators=(",", ":")))


def find_value(value, key):
    if isinstance(value, dict):
        if value.get(key):
            return value[key]
        for child in value.values():
            found = find_value(child, key)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_value(child, key)
            if found:
                return found
    return None


def installed_versions(agent, expected):
    modules_dir = agent.get("modules_dir")
    if not modules_dir:
        raise RuntimeError(f"{agent['agent_id']} config lacks modules_dir")
    versions = {}
    for name in expected:
        manifest = json.loads(remote(agent, f"cat {shlex.quote(modules_dir + '/' + name + '/manifest.json')}"))
        if manifest.get("name") != name or not manifest.get("version"):
            raise RuntimeError(f"invalid installed manifest for {name} on {agent['agent_id']}")
        versions[name] = manifest["version"]
    return versions


def wait_for(predicate, timeout, description):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(3)
    raise RuntimeError(f"timed out waiting for {description}")


def confirm_transaction(endpoint, tx_hash):
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme != "https" or parsed.hostname != "testnet.lez.logos.co":
        raise RuntimeError("sequencer_rpc must be the public v0.2 HTTPS endpoint")
    request_body = {
        "jsonrpc": "2.0",
        "method": "getTransaction",
        "params": [tx_hash],
        "id": 1,
    }
    TRANSCRIPT.append(f"$ POST {endpoint} getTransaction {tx_hash}")
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(request_body, separators=(",", ":")).encode(),
        headers={"content-type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode())
    if payload.get("error") or not payload.get("result"):
        raise RuntimeError(f"transaction is not confirmed by the sequencer: {payload!r}")
    return {
        "endpoint": endpoint,
        "query": {"method": "getTransaction", "tx_hash": tx_hash},
        "response": payload,
    }


def main():
    parser = argparse.ArgumentParser(description="Run correlated two-agent Logos Testnet v0.2 evidence.")
    parser.add_argument("--config", required=True, type=pathlib.Path)
    parser.add_argument("--out-dir", required=True, type=pathlib.Path)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    cfg = json.loads(args.config.read_text(encoding="utf-8"))
    if cfg.get("network") != "logos-testnet-v0.2" or cfg.get("delivery_preset") != "logos.test":
        raise SystemExit("config must explicitly select logos-testnet-v0.2 and logos.test")
    sequencer_rpc = cfg.get("sequencer_rpc")
    if sequencer_rpc != "https://testnet.lez.logos.co/":
        raise SystemExit("config must use the public v0.2 sequencer_rpc")
    required_versions = {"delivery_module": "0.1.3", "storage_module": "2.0.1", "chat_module": "0.2.1", "lez_core": "0.2.0", "logos_agent": "0.2.0"}
    if cfg.get("module_versions") != required_versions:
        raise SystemExit("config module_versions must match the released v0.2 dependency set")
    client, server = cfg["client"], cfg["server"]
    if client["host"] == server["host"] and client["config_dir"] == server["config_dir"]:
        raise SystemExit("client and server must use isolated Core state")
    run_id = "run_" + uuid.uuid4().hex
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    client_versions = installed_versions(client, required_versions)
    server_versions = installed_versions(server, required_versions)
    if client_versions != required_versions or server_versions != required_versions:
        raise RuntimeError(f"installed module versions differ from v0.2 lock: client={client_versions}, server={server_versions}")

    client_status = core_call(client, "status")
    server_status = core_call(server, "status")
    client_agent_id = (client_status.get("identity") or {}).get("agent_id")
    server_agent_id = (server_status.get("identity") or {}).get("agent_id")
    if not client_agent_id or not server_agent_id or client_agent_id == server_agent_id:
        raise RuntimeError("client and server status must expose distinct top-level identity.agent_id values")
    for name, status in (("client", client_status), ("server", server_status)):
        preset = find_value(status, "preset") or find_value(status, "delivery_preset")
        network = find_value(status, "network")
        if preset != "logos.test" or network != "logos-testnet-v0.2":
            raise RuntimeError(
                f"{name} reports network={network!r}, delivery_preset={preset!r}; "
                "expected logos-testnet-v0.2 and logos.test"
            )

    invoke(client, "agent.discover", {}, run_id)
    server_card = invoke(server, "agent.card", {}, run_id)
    server_address = find_value(server_card, "agent_address")
    payment_recipient = find_value(server_card, "lez_account")
    if not server_address or not payment_recipient:
        raise RuntimeError("server Agent Card lacks agent_address or lez_account")
    if not find_value(server_card, "signature"):
        raise RuntimeError("server Agent Card is not signed")
    invoke(server, "agent.publish", {}, run_id)

    def discovered_card():
        discovery = invoke(client, "agent.discover", {}, run_id)
        for card in find_value(discovery, "agents") or []:
            if find_value(card, "agent_address") == server_address:
                return card
        return None

    wait_for(discovered_card, args.timeout, "the server's signed Agent Card")

    fixture = f"logos-agent-v02-{run_id}\n"
    remote_fixture = f"/tmp/{run_id}.txt"
    remote_download = f"/tmp/{run_id}.download.txt"
    remote(client, f"umask 077; printf %s {shlex.quote(fixture)} > {shlex.quote(remote_fixture)}")
    source_hash = hashlib.sha256(fixture.encode()).hexdigest()
    invoke(client, "storage.upload", {"path": remote_fixture, "label": run_id}, run_id)

    def completed_upload():
        listing = invoke(client, "storage.list", {}, run_id)
        for item in find_value(listing, "files") or []:
            if item.get("label") == run_id and item.get("status") == "uploaded" and item.get("address"):
                return item
        return None

    uploaded = wait_for(completed_upload, args.timeout, "Storage upload completion")
    address = uploaded["address"]
    downloaded = invoke(client, "storage.download", {"address": address, "path": remote_download}, run_id)
    download_hash = remote(client, f"sha256sum {shlex.quote(remote_download)} | cut -d' ' -f1")
    if source_hash != download_hash:
        raise RuntimeError("downloaded fixture hash differs from source")

    balance_before = invoke(client, "wallet.balance", {}, run_id)
    task_id = "task_" + uuid.uuid4().hex
    subscription = invoke(client, "agent.subscribe", {"task_id": task_id}, run_id)
    task_result = invoke(client, "agent.task", {
        "task_id": task_id,
        "agent_address": server_address,
        "payment_recipient": payment_recipient,
        "skill": "meta.status",
        "params": {},
        "amount": str(cfg["payment_amount"]),
        "payment_mode": cfg.get("payment_mode", "public"),
    }, run_id)
    invocation_id = task_result.get("invocation_id")
    returned_task_id = find_value(task_result, "task_id")
    tx_hash = find_value(task_result, "tx_hash")
    if returned_task_id != task_id or not tx_hash:
        raise RuntimeError("paid agent.task lacks task_id or tx_hash")

    def completed():
        status = core_call(client, "status")
        for task in find_value(status, "active_tasks") or []:
            if task.get("task_id") == task_id and task.get("state") == "TASK_STATE_COMPLETED":
                return task
        return None
    terminal_task = wait_for(completed, args.timeout, "TASK_STATE_COMPLETED")
    confirmation = confirm_transaction(sequencer_rpc, tx_hash)
    balance_after = invoke(client, "wallet.balance", {}, run_id)
    final_client_status = core_call(client, "status")
    final_server_status = core_call(server, "status")

    audit_files = []
    for name, agent, status in (("client", client, client_status), ("server", server, server_status)):
        persistence = find_value(status, "persistence_path")
        if not persistence:
            raise RuntimeError(f"{name} status lacks persistence_path")
        raw = remote(agent, f"cat {shlex.quote(persistence + '/audit.jsonl')}")
        selected = [line for line in raw.splitlines() if json.loads(line).get("run_id") == run_id]
        path = out / f"{name}-audit.jsonl"
        path.write_text("\n".join(selected) + "\n", encoding="utf-8")
        audit_files.append(path.name)

    core_logs = []
    log_filter = (
        r"Module loaded:|logos\.test|StorageModuleImpl::(init|start)|"
        r"DeliveryModuleImpl::(createNode|start)|lez_core|logos_agent"
    )
    for name, agent in (("client", client), ("server", server)):
        core_log = agent.get("core_log")
        if not core_log:
            raise RuntimeError(f"{name} config lacks core_log for sanitized runtime evidence")
        command = (
            f"grep -E {shlex.quote(log_filter)} {shlex.quote(core_log)} "
            "| tail -n 500"
        )
        raw = remote(agent, command)
        if not raw.strip():
            raise RuntimeError(f"{name} Core log contains no v0.2 module/network evidence")
        path = out / f"{name}-core.log"
        path.write_text(raw.rstrip() + "\n", encoding="utf-8")
        core_logs.append(path.name)

    (out / "module-status.json").write_text(
        json.dumps({"client": final_client_status, "server": final_server_status}, indent=2) + "\n"
    )
    (out / "transaction-confirmation.json").write_text(json.dumps(confirmation, indent=2) + "\n")
    (out / "command-transcript.txt").write_text("\n".join(TRANSCRIPT) + "\n", encoding="utf-8")
    files = []
    for path in sorted(out.iterdir()):
        files.append({"path": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    summary = {
        "schema": "logos.agent.testnet-e2e.v1", "network": "logos-testnet-v0.2",
        "delivery_preset": "logos.test", "storage_network": "logos.test",
        "sequencer_rpc": sequencer_rpc,
        "execution_path": "logos_agent", "simulated": False, "run_id": run_id,
        "agents": [
            {"agent_id": client_agent_id, "host": client["host"]},
            {"agent_id": server_agent_id, "host": server["host"]},
        ],
        "topics": {
            "discovery": find_value(server_card, "discovery_topic"),
            "task": find_value(server_card, "task_topic"),
            "status": find_value(subscription, "topic"),
        },
        "module_versions": client_versions,
        "audit_files": audit_files,
        "core_logs": core_logs,
        "storage": {"address": address, "source_sha256": source_hash, "download_sha256": download_hash},
        "task": {"task_id": task_id, "state": terminal_task["state"]},
        "payment": {
            "tx_hash": tx_hash, "confirmed": bool(confirmation["response"].get("result")),
            "invocation_id": invocation_id, "balance_before": balance_before,
            "balance_after": balance_after,
        },
        "files": files,
    }
    summary_path = out / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    verification = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).with_name("verify-evidence.py")), str(out)],
        check=False,
    )
    if verification.returncode:
        summary_path.replace(out / "summary.failed.json")
        raise RuntimeError("generated evidence did not pass independent validation")
    print(json.dumps({"ok": True, "run_id": run_id, "out_dir": str(out)}, indent=2))


if __name__ == "__main__":
    main()
