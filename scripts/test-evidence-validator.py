#!/usr/bin/env python3
import hashlib
import json
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


with tempfile.TemporaryDirectory(prefix="logos-agent-evidence-") as temporary:
    root = pathlib.Path(temporary)
    audit = root / "client-audit.jsonl"
    run_id = "run_validator_test"
    events = []
    for index, skill in enumerate(("agent.discover", "agent.publish", "agent.subscribe", "storage.upload", "storage.download", "agent.task")):
        events.append({
            "schema": "logos.agent.evidence.v1",
            "event": "skill.completed",
            "run_id": run_id,
            "invocation_id": f"inv_{index}",
            "agent_id": "server" if skill == "agent.publish" else "client",
            "skill": skill,
            "network": "logos-testnet-v0.2",
            "delivery_preset": "logos.test",
            "ok": True,
        })
    audit.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")
    tx_hash = "01" * 32
    confirmation = root / "transaction-confirmation.json"
    confirmation.write_text(json.dumps({
        "endpoint": "https://testnet.lez.logos.co/",
        "query": {"method": "getTransaction", "tx_hash": tx_hash},
        "response": {"jsonrpc": "2.0", "id": 1, "result": "base64-chain-transaction"},
    }) + "\n", encoding="utf-8")
    client_core_log = root / "client-core.log"
    server_core_log = root / "server-core.log"
    client_core_log.write_text("[info] Module loaded: logos_agent; preset=logos.test\n", encoding="utf-8")
    server_core_log.write_text("[info] Module loaded: logos_agent; preset=logos.test\n", encoding="utf-8")
    task_id = "task_test"
    module_status = root / "module-status.json"
    module_status.write_text(json.dumps({
        "client": {"run_id": run_id, "task_id": task_id, "tx_hash": tx_hash},
        "server": {"run_id": run_id, "task_id": task_id, "tx_hash": tx_hash},
    }) + "\n", encoding="utf-8")
    summary = {
        "schema": "logos.agent.testnet-e2e.v1",
        "network": "logos-testnet-v0.2",
        "delivery_preset": "logos.test",
        "storage_network": "logos.test",
        "sequencer_rpc": "https://testnet.lez.logos.co/",
        "execution_path": "logos_agent",
        "simulated": False,
        "run_id": run_id,
        "agents": [{"agent_id": "client"}, {"agent_id": "server"}],
        "module_versions": {"delivery_module": "0.1.3", "storage_module": "2.0.1", "chat_module": "0.2.1", "lez_core": "0.2.0", "logos_agent": "0.2.0"},
        "topics": {"discovery": "/discovery", "task": "/task", "status": "/status"},
        "audit_files": [audit.name],
        "core_logs": [client_core_log.name, server_core_log.name],
        "task": {"task_id": task_id, "state": "TASK_STATE_COMPLETED"},
        "storage": {"address": "zExample", "source_sha256": "abc", "download_sha256": "abc"},
        "payment": {"tx_hash": tx_hash, "confirmed": True, "invocation_id": "inv_5"},
        "files": [
            {"path": audit.name, "sha256": digest(audit)},
            {"path": confirmation.name, "sha256": digest(confirmation)},
            {"path": client_core_log.name, "sha256": digest(client_core_log)},
            {"path": server_core_log.name, "sha256": digest(server_core_log)},
            {"path": module_status.name, "sha256": digest(module_status)},
        ],
    }
    (root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    subprocess.run(["python3", str(ROOT / "scripts/verify-evidence.py"), str(root)], check=True)

    confirmation_data = json.loads(confirmation.read_text(encoding="utf-8"))
    confirmation_data["query"]["tx_hash"] = "02" * 32
    confirmation.write_text(json.dumps(confirmation_data), encoding="utf-8")
    altered = subprocess.run(
        ["python3", str(ROOT / "scripts/verify-evidence.py"), str(root)],
        stdout=subprocess.DEVNULL,
    )
    if altered.returncode == 0:
        raise SystemExit("validator accepted an altered transaction link")
    confirmation_data["query"]["tx_hash"] = tx_hash
    confirmation.write_text(json.dumps(confirmation_data) + "\n", encoding="utf-8")
    summary["files"][1]["sha256"] = digest(confirmation)

    summary["delivery_preset"] = "logos.dev"
    (root / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
    rejected = subprocess.run(
        ["python3", str(ROOT / "scripts/verify-evidence.py"), str(root)],
        stdout=subprocess.DEVNULL,
    )
    if rejected.returncode == 0:
        raise SystemExit("validator accepted logos.dev as public-testnet evidence")
    summary["delivery_preset"] = "logos.test"

    events[0]["details"] = {"api_key": "must-not-appear"}
    audit.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")
    summary["files"][0]["sha256"] = digest(audit)
    (root / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
    leaked = subprocess.run(
        ["python3", str(ROOT / "scripts/verify-evidence.py"), str(root)],
        stdout=subprocess.DEVNULL,
    )
    if leaked.returncode == 0:
        raise SystemExit("validator accepted an audit event containing a secret field")
    del events[0]["details"]
    audit.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")
    transcript = root / "command-transcript.txt"
    transcript.write_text('$ command --json \'{"token":"must-not-appear"}\'\n', encoding="utf-8")
    summary["files"][0]["sha256"] = digest(audit)
    summary["files"].append({"path": transcript.name, "sha256": digest(transcript)})
    (root / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
    transcript_leak = subprocess.run(
        ["python3", str(ROOT / "scripts/verify-evidence.py"), str(root)],
        stdout=subprocess.DEVNULL,
    )
    if transcript_leak.returncode == 0:
        raise SystemExit("validator accepted a transcript containing a secret field")

print("evidence validator tests passed")
