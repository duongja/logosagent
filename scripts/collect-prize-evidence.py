#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import re
import shutil
from datetime import datetime, timezone


TX_RE = re.compile(r"\b[a-fA-F0-9]{64}\b")
TX_FIELD_NAMES = {"tx_hash", "transaction_hash", "payment_tx_hash", "refund_tx_hash"}
CONTENT_ADDRESS_FIELD_NAMES = {"address", "content_address"}
PROGRAM_ID_FIELD_NAMES = {"program_id", "program"}
SENSITIVE_PATH_PARTS = {
    "key",
    "keys",
    "secret",
    "secrets",
    "state.json",
    "storage.json",
    "tokens",
    "tokens.json",
    "wallet",
    "wallet_config.json",
}


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def sha256_file(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def is_sensitive_path(path, copy_mode=False):
    for part in path.parts:
        lower = part.lower()
        if lower in SENSITIVE_PATH_PARTS:
            return True
        if any(token in lower for token in ("secret", "key")):
            return True
        if copy_mode and "wallet" in lower:
            return True
    return False


def find_semantic_values(value, wanted_keys, validator, path=""):
    matches = []
    if isinstance(value, dict):
        for key, item in value.items():
            next_path = f"{path}.{key}" if path else key
            if key in wanted_keys and isinstance(item, str) and validator(item):
                matches.append({"path": next_path, "value": item})
            matches.extend(find_semantic_values(item, wanted_keys, validator, next_path))
    elif isinstance(value, list):
        for idx, item in enumerate(value):
            matches.extend(find_semantic_values(item, wanted_keys, validator, f"{path}[{idx}]"))
    return matches


def is_tx_hash(value):
    return bool(TX_RE.fullmatch(value))


def is_content_address(value):
    return value.startswith("z") and len(value) >= 32


def is_program_id(value):
    return len(value) >= 32 and not value.startswith("/")


def receipt_kind(field_path):
    lower_path = field_path.lower()
    if "refund" in lower_path:
        return "refund"
    if "payment" in lower_path:
        return "payment"
    return "transaction"


def receipt_priority(receipt):
    path = receipt["field"].lower()
    file_name = receipt["file"].lower()
    if receipt["kind"] == "refund":
        return 0
    if receipt["kind"] == "payment":
        return 1
    if "wallet-send" in file_name:
        return 2
    if "transactions" in path:
        return 4
    return 3


def collect_json_files(root):
    if not root or not root.exists():
        return []
    return sorted(p for p in root.rglob("*.json") if p.is_file() and not is_sensitive_path(p.relative_to(root)))


def summarize_run(label, root):
    summary = {
        "label": label,
        "root": str(root) if root else "",
        "exists": bool(root and root.exists()),
        "json_files": [],
        "tx_hashes": [],
        "tx_receipts": [],
        "content_addresses": [],
        "program_ids": [],
    }
    if not root or not root.exists():
        return summary

    seen_tx = set()
    seen_ca = set()
    seen_program = set()
    for path in collect_json_files(root):
        rel = str(path.relative_to(root))
        payload = load_json(path)
        entry = {"path": rel}
        if isinstance(payload, dict):
            if "ok" in payload:
                entry["ok"] = payload.get("ok")
            for match in find_semantic_values(payload, TX_FIELD_NAMES, is_tx_hash):
                tx = match["value"].lower()
                if tx not in seen_tx:
                    seen_tx.add(tx)
                    summary["tx_hashes"].append(tx)
                summary["tx_receipts"].append({
                    "file": rel,
                    "field": match["path"],
                    "kind": receipt_kind(match["path"]),
                    "tx_hash": tx,
                })
            for match in find_semantic_values(payload, CONTENT_ADDRESS_FIELD_NAMES, is_content_address):
                seen_ca.add(match["value"])
            for match in find_semantic_values(payload, PROGRAM_ID_FIELD_NAMES, is_program_id):
                seen_program.add(match["value"])
        summary["json_files"].append(entry)

    summary["content_addresses"] = sorted(seen_ca)
    summary["program_ids"] = sorted(seen_program)
    deduped_receipts = {}
    for receipt in summary["tx_receipts"]:
        key = receipt["tx_hash"]
        current = deduped_receipts.get(key)
        if current is None or receipt_priority(receipt) < receipt_priority(current):
            deduped_receipts[key] = receipt
    summary["tx_receipts"] = sorted(
        deduped_receipts.values(),
        key=lambda item: (receipt_priority(item), item["file"], item["field"]),
    )
    return summary


def latest_child(path):
    if not path.exists():
        return None
    dirs = [p for p in path.iterdir() if p.is_dir()]
    if not dirs:
        return None
    return sorted(dirs, key=lambda p: p.stat().st_mtime)[-1]


def ignore_sensitive(dirpath, names):
    ignored = []
    for name in names:
        if is_sensitive_path(pathlib.Path(name), copy_mode=True):
            ignored.append(name)
    return ignored


def copy_if_exists(src, dst_dir):
    if not src or not src.exists():
        return None
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    if src.is_dir():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst, ignore=ignore_sensitive)
    else:
        shutil.copy2(src, dst)
    return dst


def first_tx(run, kind=None):
    for receipt in run["tx_receipts"]:
        if kind is None or receipt.get("kind") == kind:
            return receipt["tx_hash"]
    return "TBD"


def summarize_three_agent_manifest(path):
    summary = {
        "path": str(path) if path else "",
        "exists": bool(path and path.exists()),
        "network": "",
        "agents": [],
    }
    if not path or not path.exists():
        return summary
    payload = load_json(path)
    if not isinstance(payload, dict):
        return summary
    summary["network"] = str(payload.get("network", ""))
    for agent in payload.get("agents", []):
        if not isinstance(agent, dict):
            continue
        summary["agents"].append({
            "category": str(agent.get("category", "")),
            "agent_id": str(agent.get("agent_id", "")),
            "name": str(agent.get("name", "")),
            "config": str(agent.get("config", "")),
            "deploy_script": str(agent.get("deploy_script", "")),
        })
    return summary


def summarize_testnet_compatibility(path):
    summary = {
        "path": str(path) if path else "",
        "exists": bool(path and path.exists()),
        "ok": False,
        "endpoint_health_ok": False,
        "transaction_submission_allowed": False,
        "current_block_id": "",
        "check_health_exit_code": "",
        "program_id_matches": {},
        "testnet_url": "",
        "wallet_transfer": {},
        "program_evidence": {},
        "a2a_payment": {},
    }
    if not path or not path.exists():
        return summary
    payload = load_json(path / "summary.json")
    if not isinstance(payload, dict):
        return summary
    summary.update({
        "ok": bool(payload.get("ok")),
        "endpoint_health_ok": bool(payload.get("endpoint_health_ok")),
        "transaction_submission_allowed": bool(payload.get("transaction_submission_allowed")),
        "current_block_id": str(payload.get("current_block_id", "")),
        "check_health_exit_code": str(payload.get("check_health_exit_code", "")),
        "program_id_matches": dict(payload.get("program_id_matches") or {}),
        "testnet_url": str(payload.get("testnet_url", "")),
    })
    transfer = load_json(path / "testnet-wallet-transfer-summary.json")
    if isinstance(transfer, dict):
        summary["wallet_transfer"] = {
            "ok": bool(transfer.get("ok")),
            "tx_hash": str(transfer.get("tx_hash", "")),
            "from": str(transfer.get("from", "")),
            "to": str(transfer.get("to", "")),
            "amount": str(transfer.get("amount", "")),
            "risc0_dev_mode": str(transfer.get("risc0_dev_mode", "")),
            "lez_ref": str(transfer.get("lez_ref", "")),
            "lez_commit": str(transfer.get("lez_commit", "")),
            "transaction_lookup_returned_some": bool(transfer.get("transaction_lookup_returned_some")),
        }
    program = load_json(path / "testnet-program-evidence-summary.json")
    if isinstance(program, dict):
        deploy = program.get("program_deploy") or {}
        call = program.get("program_call") or {}
        summary["program_evidence"] = {
            "ok": bool(program.get("ok")),
            "risc0_dev_mode": str(program.get("risc0_dev_mode", "")),
            "lez_ref": str(program.get("lez_ref", "")),
            "lez_commit": str(program.get("lez_commit", "")),
            "deploy_ok": bool(deploy.get("ok")),
            "deploy_tx_hash": str(deploy.get("tx_hash", "")),
            "deploy_lookup_returned_some": bool(deploy.get("transaction_lookup_returned_some")),
            "deploy_program_binary_size": str(deploy.get("program_binary_size", "")),
            "call_ok": bool(call.get("ok")),
            "call_tx_hash": str(call.get("tx_hash", "")),
            "call_lookup_returned_some": bool(call.get("transaction_lookup_returned_some")),
            "call_program_id": str(call.get("program_id", "")),
            "call_account_id": str(call.get("account_id", "")),
            "call_instruction_ascii": str(call.get("instruction_ascii", "")),
            "call_account_data_ascii": str(call.get("account_data_ascii", "")),
            "call_account_nonce": str((call.get("account_state") or {}).get("nonce", "")),
        }
    a2a_payment = load_json(path / "testnet-a2a-payment-summary.json")
    if isinstance(a2a_payment, dict):
        summary["a2a_payment"] = {
            "ok": bool(a2a_payment.get("ok")),
            "payment_tx_hash": str(a2a_payment.get("payment_tx_hash", "")),
            "task_id": str(a2a_payment.get("task_id", "")),
            "skill_id": str(a2a_payment.get("skill_id", "")),
            "from": str(a2a_payment.get("from", "")),
            "to": str(a2a_payment.get("to", "")),
            "amount": str(a2a_payment.get("amount", "")),
            "risc0_dev_mode": str(a2a_payment.get("risc0_dev_mode", "")),
            "lez_ref": str(a2a_payment.get("lez_ref", "")),
            "lez_commit": str(a2a_payment.get("lez_commit", "")),
            "transaction_lookup_returned_some": bool(a2a_payment.get("transaction_lookup_returned_some")),
            "balance_delta_ok": bool(a2a_payment.get("balance_delta_ok")),
            "nonce_delta_ok": bool(a2a_payment.get("nonce_delta_ok")),
            "binding_status": str(a2a_payment.get("binding_status", "")),
        }
    return summary


def summarize_basecamp_profile_install(path):
    summary = {
        "path": str(path) if path else "",
        "exists": bool(path and path.exists()),
        "ok": False,
        "profiles": {},
    }
    if not path or not path.exists():
        return summary
    payload = load_json(path / "summary.json")
    if not isinstance(payload, dict):
        return summary
    summary["ok"] = bool(payload.get("ok"))
    for profile, data in (payload.get("profiles") or {}).items():
        if not isinstance(data, dict):
            continue
        summary["profiles"][profile] = {
            "ok": bool(data.get("ok")),
            "modules_dir": str(data.get("modules_dir", "")),
            "installed_modules": list(data.get("installed_modules") or []),
        }
    return summary


def markdown_report(report):
    lines = [
        "# LP-0008 Evidence Report",
        "",
        f"- Generated: `{report['generated_at']}`",
        f"- Network label: `{report['network']}`",
        "",
        "## Package Artifacts",
        "",
    ]
    if report["artifacts"]:
        for artifact in report["artifacts"]:
            lines.append(
                f"- `{artifact['path']}` ({artifact['bytes']} bytes, sha256 `{artifact['sha256']}`)"
            )
    else:
        lines.append("- No package artifacts found.")

    manifest = report.get("three_agent_manifest", {})
    lines.extend(["", "## Three-Agent Deployment", ""])
    lines.append(f"- Manifest: `{manifest.get('path', '')}`")
    lines.append(f"- Exists: `{manifest.get('exists', False)}`")
    if manifest.get("network"):
        lines.append(f"- Manifest network: `{manifest['network']}`")
    if manifest.get("agents"):
        for agent in manifest["agents"]:
            lines.append(
                f"- {agent['category']}: `{agent['name']}` / `{agent['agent_id']}` (`{agent['deploy_script']}`)"
            )
    else:
        lines.append("- No three-agent deployment manifest found.")

    compatibility = report.get("testnet_compatibility", {})
    if compatibility.get("path") or report["network"].lower() in {"testnet", "devnet"}:
        lines.extend(["", "## Hosted Testnet Compatibility", ""])
        lines.append(f"- Run: `{compatibility.get('path', '')}`")
        lines.append(f"- Exists: `{compatibility.get('exists', False)}`")
        lines.append(f"- Endpoint: `{compatibility.get('testnet_url', '')}`")
        lines.append(f"- Endpoint health OK: `{compatibility.get('endpoint_health_ok', False)}`")
        lines.append(f"- Current block: `{compatibility.get('current_block_id', '')}`")
        lines.append(f"- Wallet check-health exit: `{compatibility.get('check_health_exit_code', '')}`")
        lines.append(
            f"- Transaction submission allowed: `{compatibility.get('transaction_submission_allowed', False)}`"
        )
        matches = compatibility.get("program_id_matches") or {}
        if matches:
            for program, matched in matches.items():
                lines.append(f"- Program ID match `{program}`: `{matched}`")
        transfer = compatibility.get("wallet_transfer") or {}
        if transfer:
            lines.append(f"- Wallet transfer OK: `{transfer.get('ok', False)}`")
            lines.append(f"- Wallet transfer tx: `{transfer.get('tx_hash', '')}`")
            lines.append(f"- Wallet transfer amount: `{transfer.get('amount', '')}`")
            lines.append(f"- Wallet transfer RISC0_DEV_MODE: `{transfer.get('risc0_dev_mode', '')}`")
            lines.append(f"- Wallet transfer LEZ ref: `{transfer.get('lez_ref', '')}` / `{transfer.get('lez_commit', '')}`")
            lines.append(
                f"- Wallet transfer lookup returned transaction: `{transfer.get('transaction_lookup_returned_some', False)}`"
            )
        program = compatibility.get("program_evidence") or {}
        if program:
            lines.append(f"- Program evidence OK: `{program.get('ok', False)}`")
            lines.append(f"- Program deploy tx: `{program.get('deploy_tx_hash', '')}`")
            lines.append(
                f"- Program deploy lookup returned transaction: `{program.get('deploy_lookup_returned_some', False)}`"
            )
            lines.append(f"- Program call tx: `{program.get('call_tx_hash', '')}`")
            lines.append(
                f"- Program call lookup returned transaction: `{program.get('call_lookup_returned_some', False)}`"
            )
            lines.append(f"- Program call account: `{program.get('call_account_id', '')}`")
            lines.append(f"- Program call instruction: `{program.get('call_instruction_ascii', '')}`")
            lines.append(f"- Program call account data: `{program.get('call_account_data_ascii', '')}`")
            lines.append(f"- Program evidence RISC0_DEV_MODE: `{program.get('risc0_dev_mode', '')}`")
        a2a_payment = compatibility.get("a2a_payment") or {}
        if a2a_payment:
            lines.append(f"- A2A payment evidence OK: `{a2a_payment.get('ok', False)}`")
            lines.append(f"- A2A payment task: `{a2a_payment.get('task_id', '')}` / `{a2a_payment.get('skill_id', '')}`")
            lines.append(f"- A2A payment tx: `{a2a_payment.get('payment_tx_hash', '')}`")
            lines.append(f"- A2A payment amount: `{a2a_payment.get('amount', '')}`")
            lines.append(
                f"- A2A payment lookup returned transaction: `{a2a_payment.get('transaction_lookup_returned_some', False)}`"
            )
            lines.append(f"- A2A payment balance delta OK: `{a2a_payment.get('balance_delta_ok', False)}`")
            lines.append(f"- A2A payment nonce delta OK: `{a2a_payment.get('nonce_delta_ok', False)}`")
            lines.append(f"- A2A payment RISC0_DEV_MODE: `{a2a_payment.get('risc0_dev_mode', '')}`")
            lines.append(f"- A2A payment scope: {a2a_payment.get('binding_status', '')}")

    basecamp_install = report.get("basecamp_profile_install", {})
    lines.extend(["", "## Basecamp Profile Install", ""])
    lines.append(f"- Run: `{basecamp_install.get('path', '')}`")
    lines.append(f"- Exists: `{basecamp_install.get('exists', False)}`")
    lines.append(f"- OK: `{basecamp_install.get('ok', False)}`")
    for profile, data in (basecamp_install.get("profiles") or {}).items():
        modules = ", ".join(data.get("installed_modules") or [])
        lines.append(f"- {profile}: `{data.get('ok', False)}` modules `{modules}`")

    lines.extend(["", "## Runs", ""])
    for run in report["runs"]:
        lines.append(f"### {run['label']}")
        lines.append("")
        lines.append(f"- Root: `{run['root']}`")
        lines.append(f"- Exists: `{run['exists']}`")
        if run["tx_hashes"]:
            for receipt in run["tx_receipts"]:
                lines.append(f"- Tx hash: `{receipt['tx_hash']}` ({receipt['kind']}, `{receipt['file']}` -> `{receipt['field']}`)")
        if run["content_addresses"]:
            for address in run["content_addresses"]:
                lines.append(f"- Content address: `{address}`")
        if run["program_ids"]:
            for program_id in run["program_ids"]:
                lines.append(f"- Program ID: `{program_id}`")
        lines.append(f"- JSON evidence files: `{len(run['json_files'])}`")
        lines.append("")

    lines.extend([
        "## CU Measurements",
        "",
        "Fill these from devnet/testnet transaction/explorer output. Local proof runs may leave CU blank.",
        "Raw run directories are not copied by default because they can contain wallet keys and runtime state.",
        "",
        "| Operation | Network | Tx Hash | CU / Cycles | Notes |",
        "| --- | --- | --- | --- | --- |",
    ])
    for row in report["cu_rows"]:
        lines.append(
            f"| {row['operation']} | {row['network']} | {row['tx_hash']} | {row['cu']} | {row['notes']} |"
        )
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Collect LP-0008 prize evidence into JSON and Markdown.")
    parser.add_argument("--out-dir", default=".local/evidence/latest")
    parser.add_argument("--network", default="localnet")
    parser.add_argument("--wallet-run")
    parser.add_argument("--storage-run")
    parser.add_argument("--messaging-run")
    parser.add_argument("--a2a-run")
    parser.add_argument("--program-run")
    parser.add_argument("--preflight-run")
    parser.add_argument("--testnet-compatibility-run")
    parser.add_argument("--basecamp-project", default=".local/basecamp-owner-channel")
    parser.add_argument("--basecamp-profile-install-run")
    parser.add_argument("--three-agent-manifest", default=".local/testnet-agents/latest/manifest.json")
    parser.add_argument("--copy-runs", action="store_true", help="Copy selected run directories with known secret files filtered out.")
    args = parser.parse_args()

    root = pathlib.Path.cwd()
    out_dir = (root / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    defaults = {
        "wallet": latest_child(root / ".local/agent-wallet-smoke"),
        "storage": latest_child(root / ".local/agent-storage-smoke"),
        "messaging": latest_child(root / ".local/agent-messaging-smoke"),
        "a2a": latest_child(root / ".local/agent-a2a-paid-smoke"),
        "program": latest_child(root / ".local/agent-program-smoke"),
        "preflight": latest_child(root / ".local/test-runs"),
        "basecamp_profile_install": latest_child(root / ".local/basecamp-profile-install-smoke"),
    }
    live_network = args.network.lower() in {"testnet", "devnet"}
    selected = {
        "wallet": pathlib.Path(args.wallet_run) if args.wallet_run else (None if live_network else defaults["wallet"]),
        "storage": pathlib.Path(args.storage_run) if args.storage_run else (None if live_network else defaults["storage"]),
        "messaging": pathlib.Path(args.messaging_run) if args.messaging_run else (None if live_network else defaults["messaging"]),
        "paid_a2a": pathlib.Path(args.a2a_run) if args.a2a_run else (None if live_network else defaults["a2a"]),
        "program": pathlib.Path(args.program_run) if args.program_run else (None if live_network else defaults["program"]),
        "preflight": pathlib.Path(args.preflight_run) if args.preflight_run else (None if live_network else defaults["preflight"]),
        "basecamp": pathlib.Path(args.basecamp_project) if args.basecamp_project else None,
        "basecamp_profile_install": pathlib.Path(args.basecamp_profile_install_run) if args.basecamp_profile_install_run else defaults["basecamp_profile_install"],
    }
    testnet_compatibility_run = (
        pathlib.Path(args.testnet_compatibility_run)
        if args.testnet_compatibility_run
        else latest_child(root / ".local/testnet-evidence")
    )

    artifacts = []
    for path in [
        root / "result/logos-logos_agent-module-lib.lgx",
        root / ".local/artifacts/basecamp-lgx/delivery_module/delivery_module.lgx",
        root / ".local/artifacts/basecamp-lgx/storage_module/storage_module.lgx",
        root / ".local/artifacts/basecamp-lgx/chat_module/chat_module.lgx",
        root / ".local/artifacts/basecamp-lgx/logos_execution_zone/logos_execution_zone.lgx",
        root / ".local/artifacts/basecamp-lgx/logos_agent/logos_agent.lgx",
    ]:
        if path.exists():
            artifacts.append({
                "path": str(path),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })

    runs = [summarize_run(label, path) for label, path in selected.items()]

    runs_by_label = {run["label"]: run for run in runs}
    compatibility_summary = summarize_testnet_compatibility(testnet_compatibility_run)
    compatibility_wallet_transfer = compatibility_summary.get("wallet_transfer") or {}
    compatibility_program = compatibility_summary.get("program_evidence") or {}
    compatibility_a2a_payment = compatibility_summary.get("a2a_payment") or {}
    wallet_tx = first_tx(runs_by_label["wallet"])
    if wallet_tx == "TBD" and compatibility_wallet_transfer.get("ok"):
        wallet_tx = compatibility_wallet_transfer.get("tx_hash") or "TBD"
    program_deploy_tx = first_tx(runs_by_label["program"])
    if program_deploy_tx == "TBD" and compatibility_program.get("deploy_ok"):
        program_deploy_tx = compatibility_program.get("deploy_tx_hash") or "TBD"
    program_call_tx = "TBD"
    if compatibility_program.get("call_ok"):
        program_call_tx = compatibility_program.get("call_tx_hash") or "TBD"
    paid_a2a_payment_tx = first_tx(runs_by_label["paid_a2a"], "payment")
    if paid_a2a_payment_tx == "TBD" and compatibility_a2a_payment.get("ok"):
        paid_a2a_payment_tx = compatibility_a2a_payment.get("payment_tx_hash") or "TBD"
    paid_a2a_refund_tx = first_tx(runs_by_label["paid_a2a"], "refund")

    cu_rows = [
        {"operation": "wallet.send", "network": args.network, "tx_hash": wallet_tx, "cu": "TBD", "notes": "fill from devnet/testnet explorer or sequencer output"},
        {"operation": "agent.task payment", "network": args.network, "tx_hash": paid_a2a_payment_tx, "cu": "TBD", "notes": "LEZ payment attached to A2A task receipt"},
        {"operation": "agent.task refund", "network": args.network, "tx_hash": paid_a2a_refund_tx, "cu": "TBD", "notes": "LEZ refund attached to A2A cancellation receipt when present"},
        {"operation": "program.deploy", "network": args.network, "tx_hash": program_deploy_tx, "cu": "TBD", "notes": "hosted testnet ProgramDeploymentTransaction; CU not exposed by wallet/RPC output"},
        {"operation": "program.call", "network": args.network, "tx_hash": program_call_tx, "cu": "TBD", "notes": "hosted testnet signed public call; account data confirms instruction output"},
    ]

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "network": args.network,
        "artifacts": artifacts,
        "three_agent_manifest": summarize_three_agent_manifest(pathlib.Path(args.three_agent_manifest) if args.three_agent_manifest else None),
        "testnet_compatibility": compatibility_summary,
        "basecamp_profile_install": summarize_basecamp_profile_install(selected["basecamp_profile_install"]),
        "runs": runs,
        "cu_rows": cu_rows,
    }

    (out_dir / "evidence.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (out_dir / "evidence.md").write_text(markdown_report(report), encoding="utf-8")

    if args.copy_runs:
        copied = out_dir / "copies"
        for label, path in selected.items():
            if path and path.exists():
                copy_if_exists(path, copied / label)

    print(json.dumps({"ok": True, "out_dir": str(out_dir), "runs": len(runs), "artifacts": len(artifacts)}, indent=2))


if __name__ == "__main__":
    main()
