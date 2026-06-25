#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
from datetime import datetime, timezone


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DOCS = [
    "README.md",
    "LICENSE",
    "metadata.json",
    "module.json",
    "demo.sh",
    "docs/architecture.md",
    "docs/skill-interface.md",
    "docs/a2a-logos-messaging-binding.md",
    "docs/security-model.md",
    "docs/deployment-guide.md",
    "docs/owner-channel-basecamp.md",
    "docs/demo-video-links.md",
    "docs/basecamp-owner-chat-evidence-20260622.md",
    "docs/basecamp-v012-agent-evidence-20260622.md",
    "docs/localnet-prize-evidence-refresh-20260622.md",
    "docs/cu-report.md",
    "docs/environment-setup.md",
    "docs/submission-readiness.md",
    "docs/prize-submission-dossier.md",
    "docs/testnet-evidence-runbook.md",
    "docs/testnet-redeploy-note-20260625.md",
    "docs/testnet-compatibility-evidence-20260619.md",
    "docs/testnet-wallet-transfer-evidence-20260619.md",
    "docs/testnet-program-evidence-20260619.md",
    "docs/testnet-a2a-payment-evidence-20260619.md",
    "docs/localnet-a2a-discovery-payment-evidence-20260620.md",
    "docs/three-agent-headless-evidence-20260620.md",
    "docs/manual-intervention-checklist.md",
    ".github/workflows/ci.yml",
]
DEMO_VIDEOS = [
    ("Video 1", "Repository readiness, package/evidence bundle, hosted-testnet transaction evidence, and submission overview", "https://www.youtube.com/watch?v=fYlokf7NIfI"),
    ("Video 2", "Basecamp owner-to-agent Chat flow and owner-channel skill calls", "https://www.youtube.com/watch?v=nS8928doTkE"),
    ("Video 3", "Live skill proofs: Storage, wallet spending controls and transfer history, Messaging/Delivery, paid A2A, and program operations", "https://www.youtube.com/watch?v=hxRQejaBhxo"),
]
MANUAL_ITEMS = [
    "Run the official clean Nix package build on a stable machine or GitHub workflow: nix build --impure .#lgx -L.",
]


def run(cmd):
    subprocess.run(cmd, cwd=ROOT, check=True)


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def sha256_file(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git_commit():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""


def copy_public_file(src_rel, out_root):
    src = ROOT / src_rel
    if not src.exists() or not src.is_file():
        return None
    dst = out_root / "public-files" / src_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return dst


def artifact_rows():
    paths = [
        ROOT / "result/logos-logos_agent-module-lib.lgx",
        ROOT / ".local/artifacts/basecamp-lgx/delivery_module/delivery_module.lgx",
        ROOT / ".local/artifacts/basecamp-lgx/storage_module/storage_module.lgx",
        ROOT / ".local/artifacts/basecamp-lgx/chat_module/chat_module.lgx",
        ROOT / ".local/artifacts/basecamp-lgx/logos_execution_zone/logos_execution_zone.lgx",
        ROOT / ".local/artifacts/basecamp-lgx/logos_agent/logos_agent.lgx",
    ]
    rows = []
    for path in paths:
        if not path.exists():
            continue
        rows.append({
            "path": str(path.relative_to(ROOT)),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return rows


def run_collectors(out_dir):
    localnet_dir = out_dir / "evidence" / "localnet"
    testnet_dir = out_dir / "evidence" / "testnet"
    run(["python3", "scripts/collect-prize-evidence.py", "--network", "localnet", "--out-dir", str(localnet_dir)])
    run(["python3", "scripts/collect-prize-evidence.py", "--network", "testnet", "--out-dir", str(testnet_dir)])
    return {
        "localnet": load_json(localnet_dir / "evidence.json"),
        "testnet": load_json(testnet_dir / "evidence.json"),
    }


def tx_summary(testnet):
    compatibility = testnet.get("testnet_compatibility") or {}
    wallet = compatibility.get("wallet_transfer") or {}
    program = compatibility.get("program_evidence") or {}
    a2a = compatibility.get("a2a_payment") or {}
    rows = []
    if wallet.get("tx_hash"):
        rows.append(("wallet.send", wallet.get("tx_hash"), "hosted LEZ testnet transfer"))
    if program.get("deploy_tx_hash"):
        rows.append(("program.deploy", program.get("deploy_tx_hash"), "hosted LEZ testnet deployment"))
    if program.get("call_tx_hash"):
        rows.append(("program.call", program.get("call_tx_hash"), "hosted LEZ testnet signed call"))
    if a2a.get("payment_tx_hash"):
        rows.append(("agent.task payment", a2a.get("payment_tx_hash"), "hosted LEZ testnet A2A payment leg"))
    return rows


def local_evidence_summary(localnet):
    result = []
    for run in localnet.get("runs") or []:
        label = run.get("label", "")
        if not run.get("exists"):
            continue
        details = []
        if run.get("tx_hashes"):
            details.append(f"{len(run['tx_hashes'])} tx hash(es)")
        if run.get("content_addresses"):
            details.append(f"{len(run['content_addresses'])} content address(es)")
        if run.get("program_ids"):
            details.append(f"{len(run['program_ids'])} program id(s)")
        if not details:
            details.append(f"{len(run.get('json_files') or [])} JSON evidence file(s)")
        result.append((label, ", ".join(details), run.get("root", "")))
    return result


def write_index(out_dir, reports, artifacts):
    generated = datetime.now(timezone.utc).isoformat()
    commit = git_commit()
    localnet = reports.get("localnet") or {}
    testnet = reports.get("testnet") or {}
    tx_rows = tx_summary(testnet)
    local_rows = local_evidence_summary(localnet)

    lines = [
        "# LP-0008 Submission Bundle",
        "",
        f"- Generated: `{generated}`",
        f"- Git commit: `{commit}`",
        "",
        "## Contents",
        "",
        "- `public-files/`: public repo docs, metadata, README, and CI workflow copied for review convenience.",
        "- `evidence/localnet/evidence.md`: sanitized local module/storage/messaging/A2A/program evidence summary.",
        "- `evidence/testnet/evidence.md`: sanitized hosted-testnet transaction evidence summary.",
        "- `artifact-checksums.json`: local package artifact checksums when artifacts exist.",
        "- `manual-intervention-checklist.md`: tasks that still require user/UI/external action.",
        "",
        "## Hosted-Testnet Tx Evidence",
        "",
    ]
    if tx_rows:
        for operation, tx_hash, note in tx_rows:
            lines.append(f"- `{operation}`: `{tx_hash}` ({note})")
    else:
        lines.append("- No hosted-testnet tx hashes found in the current local evidence directory.")

    lines.extend(["", "## Narrated Demo Videos", ""])
    for label, focus, url in DEMO_VIDEOS:
        lines.append(f"- `{label}`: {focus}. {url}")

    lines.extend(["", "## Local Evidence Summary", ""])
    if local_rows:
        for label, details, root in local_rows:
            lines.append(f"- `{label}`: {details} from `{root}`")
    else:
        lines.append("- No local smoke evidence roots found.")

    lines.extend(["", "## Package Artifacts", ""])
    if artifacts:
        for artifact in artifacts:
            lines.append(
                f"- `{artifact['path']}`: {artifact['bytes']} bytes, sha256 `{artifact['sha256']}`"
            )
    else:
        lines.append("- No local LGX artifacts found. Build them before final submission.")

    lines.extend(["", "## Manual Intervention Remaining", ""])
    for item in MANUAL_ITEMS:
        lines.append(f"- {item}")
    lines.append("")

    (out_dir / "SUBMISSION-INDEX.md").write_text("\n".join(lines), encoding="utf-8")
    (out_dir / "manual-intervention-checklist.md").write_text(
        "# Manual Intervention Checklist\n\n" + "\n".join(f"- {item}" for item in MANUAL_ITEMS) + "\n",
        encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser(description="Create a sanitized LP-0008 submission evidence bundle.")
    parser.add_argument(
        "--out-dir",
        default=f".local/submission-bundle/{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
        help="Output directory. Default: .local/submission-bundle/<utc>",
    )
    args = parser.parse_args()

    out_dir = (ROOT / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    reports = run_collectors(out_dir)

    copied = []
    for rel in DEFAULT_DOCS:
        dst = copy_public_file(rel, out_dir)
        if dst:
            copied.append(str(dst.relative_to(out_dir)))

    artifacts = artifact_rows()
    (out_dir / "artifact-checksums.json").write_text(
        json.dumps(artifacts, indent=2) + "\n",
        encoding="utf-8",
    )
    write_index(out_dir, reports, artifacts)

    manifest = {
        "ok": True,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": git_commit(),
        "out_dir": str(out_dir),
        "copied_public_files": copied,
        "demo_videos": [
            {"label": label, "focus": focus, "url": url}
            for label, focus, url in DEMO_VIDEOS
        ],
        "artifacts": artifacts,
        "manual_items_remaining": MANUAL_ITEMS,
    }
    (out_dir / "bundle-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "out_dir": str(out_dir), "public_files": len(copied), "artifacts": len(artifacts)}, indent=2))


if __name__ == "__main__":
    main()
