#!/usr/bin/env python3
import argparse
import json
import pathlib
import subprocess
from datetime import datetime, timezone


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def parse_core_result(path):
    payload = load_json(path)
    if not isinstance(payload, dict):
        return None, None
    result = payload.get("result")
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except Exception:
            pass
    return payload, result


def logoscore_status(logoscore, config_dir):
    if not logoscore:
        return {"checked": False}
    proc = subprocess.run(
        [logoscore, "--config-dir", str(config_dir), "status"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return {
        "checked": True,
        "exit_code": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }


def summarize_agent(agent_dir, logoscore):
    agent_dir = pathlib.Path(agent_dir)
    category_file = agent_dir / "category.txt"
    entry = {
        "agent_id": agent_dir.name,
        "dir": str(agent_dir),
        "category": category_file.read_text(encoding="utf-8").strip() if category_file.exists() else "",
    }

    files = {
        "deployment_summary": "deployment-summary.json",
        "agent_card": "agent-card.json",
        "meta_skills": "meta-skills.json",
        "meta_status": "meta-status.json",
    }
    for key, name in files.items():
        path = agent_dir / name
        entry[f"{key}_path"] = str(path)
        entry[f"{key}_exists"] = path.exists()
        payload, result = parse_core_result(path)
        if isinstance(payload, dict):
            entry[f"{key}_status"] = payload.get("status") or payload.get("ok")
        if key == "agent_card" and isinstance(result, dict):
            card = result.get("card") or {}
            logos = card.get("logos") or {}
            entry["agent_card_signed"] = bool(card.get("signature"))
            entry["discovery_topic"] = str(logos.get("discovery_topic", ""))
            entry["task_topic"] = str(logos.get("task_topic", ""))
        if key == "meta_status" and isinstance(result, dict):
            identity = result.get("identity") or {}
            messaging = result.get("messaging") or {}
            wallet = result.get("wallet") or {}
            entry["lez_account"] = str(identity.get("lez_account") or wallet.get("account") or "")
            entry["lez_account_is_public"] = bool(identity.get("lez_account_is_public", False))
            entry["delivery_started"] = bool(messaging.get("delivery_started"))
            entry["chat_started"] = bool(messaging.get("chat_started"))
            entry["pending_approvals"] = len(result.get("pending_approvals") or [])
            entry["started"] = bool(result.get("started"))

    pid_file = agent_dir / "logoscore.pid"
    entry["pid_file"] = str(pid_file)
    entry["pid_file_exists"] = pid_file.exists()
    if pid_file.exists():
        entry["pid"] = pid_file.read_text(encoding="utf-8").strip()
    entry["post_run_status"] = logoscore_status(logoscore, agent_dir / "core")
    return entry


def main():
    parser = argparse.ArgumentParser(description="Summarize three LP-0008 agent deployment evidence.")
    parser.add_argument("--root", default=".local/testnet-agents/latest")
    parser.add_argument("--logoscore", default=".local/logoscore-bin/bin/logoscore")
    parser.add_argument("--out")
    args = parser.parse_args()

    root = pathlib.Path(args.root)
    logoscore = pathlib.Path(args.logoscore)
    logoscore_arg = str(logoscore) if logoscore.exists() else ""
    manifest = load_json(root / "manifest.json") or {}
    agents = []
    for agent in manifest.get("agents", []):
        config = pathlib.Path(str(agent.get("config", "")))
        agent_dir = config.parent if config.name else root / str(agent.get("agent_id", ""))
        agents.append(summarize_agent(agent_dir, logoscore_arg))

    summary = {
        "ok": all(
            all(agent.get(f"{key}_exists") for key in ("deployment_summary", "agent_card", "meta_skills", "meta_status"))
            for agent in agents
        ),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "network": str(manifest.get("network", "")),
        "delivery_preset": str((manifest.get("delivery") or {}).get("preset", "")),
        "risc0_dev_mode": "0",
        "agents": agents,
        "scope_note": (
            "Headless deployment evidence generated agent cards, skills, status, "
            "wallet identities, and Delivery startup for three category agents. "
            "Basecamp GUI owner-channel recording remains separate."
        ),
    }
    out = pathlib.Path(args.out) if args.out else root / "three-agent-deployment-evidence.json"
    out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
