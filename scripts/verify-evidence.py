#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import re
import sys


REQUIRED_SKILLS = {"agent.discover", "agent.publish", "agent.subscribe", "storage.upload", "storage.download", "agent.task"}
FORBIDDEN_KEYS = {
    "a2a_secret", "api_key", "file_key", "key_hex", "mnemonic", "params",
    "password", "payload", "plaintext", "private_key", "private_key_hex",
    "seed", "token", "wallet_password", "wallet_secret",
}
HEX_SECRET = re.compile(r'(?i)"(?:private_key_hex|key_hex|seed)"\s*:\s*"[0-9a-f]+"')
GLOBAL_FORBIDDEN_KEYS = FORBIDDEN_KEYS - {"params"}
FORBIDDEN_FIELD = re.compile(
    r'(?i)"(?:' + "|".join(re.escape(key) for key in sorted(GLOBAL_FORBIDDEN_KEYS)) + r')"\s*:'
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk_keys(value):
    if isinstance(value, dict):
        for key, child in value.items():
            yield key.lower()
            yield from walk_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_keys(child)


def walk_values(value):
    if isinstance(value, dict):
        for child in value.values():
            yield from walk_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_values(child)
    else:
        yield value


def fail(errors, message):
    errors.append(message)


def main():
    parser = argparse.ArgumentParser(description="Verify a sanitized Logos Agent evidence bundle.")
    parser.add_argument("evidence_dir", type=pathlib.Path)
    parser.add_argument("--allow-localnet", action="store_true")
    args = parser.parse_args()
    root = args.evidence_dir.resolve()
    errors = []
    summary_path = root / "summary.json"
    if not summary_path.is_file():
        print(json.dumps({"ok": False, "errors": [f"missing {summary_path}"]}, indent=2))
        return 1
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(json.dumps({"ok": False, "errors": [f"invalid summary.json: {exc}"]}, indent=2))
        return 1

    if summary.get("schema") != "logos.agent.testnet-e2e.v1":
        fail(errors, "summary schema must be logos.agent.testnet-e2e.v1")

    network = summary.get("network")
    if args.allow_localnet:
        if network not in {"localnet", "logos-testnet-v0.2"}:
            fail(errors, "network must be localnet or logos-testnet-v0.2")
    elif network != "logos-testnet-v0.2":
        fail(errors, "public evidence must use network logos-testnet-v0.2")
    if network == "logos-testnet-v0.2":
        if summary.get("delivery_preset") != "logos.test":
            fail(errors, "public evidence must use delivery_preset logos.test")
        if summary.get("storage_network") != "logos.test":
            fail(errors, "public evidence must use storage_network logos.test")
        if summary.get("execution_path") != "logos_agent":
            fail(errors, "execution_path must be logos_agent, not a standalone wallet")
        if summary.get("sequencer_rpc") != "https://testnet.lez.logos.co/":
            fail(errors, "public evidence must use the v0.2 sequencer RPC")
        if summary.get("simulated") is not False:
            fail(errors, "public evidence must explicitly set simulated=false")
        versions = summary.get("module_versions") or {}
        expected_versions = {"delivery_module": "0.1.3", "storage_module": "2.0.1", "chat_module": "0.2.1", "lez_core": "0.2.0", "logos_agent": "0.2.0"}
        for name, version in expected_versions.items():
            if versions.get(name) != version:
                fail(errors, f"module_versions.{name} must be {version}")

    run_id = summary.get("run_id", "")
    if not isinstance(run_id, str) or not run_id.startswith("run_"):
        fail(errors, "run_id must be a non-empty run_ identifier")
    agents = summary.get("agents") or []
    summary_agent_ids = {item.get("agent_id") for item in agents if isinstance(item, dict) and item.get("agent_id")}
    if len(summary_agent_ids) < 2:
        fail(errors, "evidence must identify at least two distinct agents")

    audit_files = summary.get("audit_files") or []
    events = []
    for rel in audit_files:
        path = root / rel
        if not path.is_file():
            fail(errors, f"missing audit file: {rel}")
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except Exception as exc:
                fail(errors, f"invalid JSONL {rel}:{number}: {exc}")
                continue
            if event.get("schema") != "logos.agent.evidence.v1":
                fail(errors, f"unexpected evidence schema in {rel}:{number}")
            if event.get("run_id") != run_id:
                fail(errors, f"run_id mismatch in {rel}:{number}")
            if FORBIDDEN_KEYS.intersection(walk_keys(event)):
                fail(errors, f"secret field present in {rel}:{number}")
            events.append(event)

    if len(summary_agent_ids.intersection({event.get("agent_id") for event in events})) < 2:
        fail(errors, "audit events must contain activity from both identified agents")

    core_logs = summary.get("core_logs") or []
    if len(core_logs) != 2:
        fail(errors, "evidence must identify two sanitized Core log artifacts")
    for rel in core_logs:
        path = root / rel
        if not path.is_file() or not path.read_text(encoding="utf-8", errors="ignore").strip():
            fail(errors, f"missing or empty Core log artifact: {rel}")

    skills = {event.get("skill") for event in events if event.get("ok") is True}
    missing_skills = sorted(REQUIRED_SKILLS - skills)
    if missing_skills:
        fail(errors, f"missing successful correlated skills: {', '.join(missing_skills)}")
    task = summary.get("task") or {}
    if task.get("state") != "TASK_STATE_COMPLETED" or not task.get("task_id"):
        fail(errors, "task must have a task_id and TASK_STATE_COMPLETED")
    storage = summary.get("storage") or {}
    if not storage.get("address") or storage.get("source_sha256") != storage.get("download_sha256"):
        fail(errors, "storage address and matching source/download hashes are required")
    topics = summary.get("topics") or {}
    if not all(topics.get(name) for name in ("discovery", "task", "status")):
        fail(errors, "discovery, task, and status Delivery topics are required")
    payment = summary.get("payment") or {}
    if not payment.get("tx_hash") or payment.get("confirmed") is not True:
        fail(errors, "confirmed agent-correlated payment tx_hash is required")
    if payment.get("invocation_id") not in {event.get("invocation_id") for event in events}:
        fail(errors, "payment invocation_id is not present in audit events")
    module_status_path = root / "module-status.json"
    if not module_status_path.is_file():
        fail(errors, "missing module-status.json")
    else:
        try:
            module_status = json.loads(module_status_path.read_text(encoding="utf-8"))
            status_values = set(walk_values(module_status))
            for label, expected in (
                ("run_id", run_id),
                ("task_id", task.get("task_id")),
                ("tx_hash", payment.get("tx_hash")),
            ):
                if expected not in status_values:
                    fail(errors, f"module-status.json does not contain the correlated {label}")
        except Exception as exc:
            fail(errors, f"invalid module-status.json: {exc}")
    confirmation_path = root / "transaction-confirmation.json"
    if not confirmation_path.is_file():
        fail(errors, "missing transaction-confirmation.json")
    else:
        try:
            confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
            query = confirmation.get("query") or {}
            response = confirmation.get("response") or {}
            if confirmation.get("endpoint") != summary.get("sequencer_rpc"):
                fail(errors, "transaction confirmation endpoint does not match summary")
            if query.get("method") != "getTransaction" or query.get("tx_hash") != payment.get("tx_hash"):
                fail(errors, "transaction confirmation query does not match payment tx_hash")
            if response.get("error") or not response.get("result"):
                fail(errors, "transaction confirmation lacks a chain result")
        except Exception as exc:
            fail(errors, f"invalid transaction-confirmation.json: {exc}")

    manifest = summary.get("files") or []
    for item in manifest:
        path = root / item.get("path", "")
        if not path.is_file():
            fail(errors, f"missing evidence artifact: {item.get('path')}")
        elif sha256(path) != item.get("sha256"):
            fail(errors, f"checksum mismatch: {item.get('path')}")

    for path in root.rglob("*"):
        if path.is_file() and path.stat().st_size <= 10 * 1024 * 1024:
            text = path.read_text(encoding="utf-8", errors="ignore")
            if HEX_SECRET.search(text) or FORBIDDEN_FIELD.search(text):
                fail(errors, f"secret-like value found in {path.relative_to(root)}")

    result = {"ok": not errors, "run_id": run_id, "events": len(events), "errors": errors}
    print(json.dumps(result, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
