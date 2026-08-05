#!/usr/bin/env python3
"""Run one persistent Logos Agent and expose sanitized readiness evidence."""

from __future__ import annotations

import json
import os
import pathlib
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


LOGOSCORE = os.environ.get("LOGOSCORE", "/opt/logos/runtime/logoscore/AppRun")
MODULES_DIR = pathlib.Path(os.environ.get("LOGOS_MODULES_DIR", "/opt/logos/modules"))
DATA_DIR = pathlib.Path(os.environ.get("LOGOS_DATA_DIR", "/data"))
CORE_DIR = DATA_DIR / "core"
STATE_DIR = DATA_DIR / "state"
AGENT_DIR = DATA_DIR / "agent"
WALLET_DIR = DATA_DIR / "wallet"
PORT = int(os.environ.get("PORT", "8080"))

PUBLIC_STATE: dict[str, Any] = {
    "ok": False,
    "service": "logos-agent",
    "network": "logos-testnet-v0.2",
    "delivery_preset": "logos.test",
    "phase": "booting",
}
STATE_LOCK = threading.Lock()
STOP_EVENT = threading.Event()


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def update_public(**values: Any) -> None:
    with STATE_LOCK:
        PUBLIC_STATE.update(values)
        PUBLIC_STATE["checked_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run_core(*args: str, check: bool = True) -> str:
    command = [LOGOSCORE, "--config-dir", str(CORE_DIR), *args]
    result = subprocess.run(command, text=True, capture_output=True, timeout=60)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"logoscore {' '.join(args)} failed ({result.returncode}): "
            f"{result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout.strip()


def parse_call(raw: str) -> dict[str, Any]:
    outer = json.loads(raw)
    value = outer.get("result", outer)
    if isinstance(value, str):
        return json.loads(value)
    if isinstance(value, dict):
        return value
    raise RuntimeError("unexpected logoscore call response")


def module_versions() -> dict[str, str]:
    versions: dict[str, str] = {}
    for name in ("delivery_module", "storage_module", "chat_module", "lez_core", "logos_agent"):
        manifest = json.loads((MODULES_DIR / name / "manifest.json").read_text(encoding="utf-8"))
        versions[name] = str(manifest.get("version", ""))
    return versions


def write_config() -> pathlib.Path:
    network = os.environ.get("LOGOS_NETWORK", "logos-testnet-v0.2")
    delivery = os.environ.get("DELIVERY_PRESET", "logos.test")
    storage_network = os.environ.get("STORAGE_NETWORK", "logos.test")
    if (network, delivery, storage_network) != ("logos-testnet-v0.2", "logos.test", "logos.test"):
        raise RuntimeError("Railway deployment refuses localnet or logos.dev configuration")

    for path in (CORE_DIR, STATE_DIR, AGENT_DIR, WALLET_DIR, DATA_DIR / "storage", DATA_DIR / "home"):
        path.mkdir(parents=True, exist_ok=True)

    wallet_config = WALLET_DIR / "wallet_config.json"
    wallet_storage = WALLET_DIR / "wallet_storage.json"
    wallet_config.write_text(
        json.dumps(
            {
                "sequencer_addr": "https://testnet.lez.logos.co/",
                "seq_poll_timeout": "30s",
                "seq_tx_poll_max_blocks": 30,
                "seq_poll_max_retries": 20,
                "seq_block_poll_max_amount": 100,
            },
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
    wallet_config.chmod(0o600)

    create_wallet = not wallet_storage.exists()
    wallet_password = os.environ.get("LOGOS_WALLET_PASSWORD", "")
    if create_wallet and len(wallet_password) < 16:
        raise RuntimeError("LOGOS_WALLET_PASSWORD must contain at least 16 characters on first boot")
    agent_id = os.environ.get("AGENT_ID", "logos-agent-railway")
    agent_name = os.environ.get("AGENT_NAME", "Logos Agent v0.2")
    persisted_account = ""
    persisted_identity: dict[str, Any] = {}
    if not create_wallet:
        state_files = sorted((STATE_DIR / "logos_agent").glob("*/state.json"))
        if state_files:
            persisted = json.loads(state_files[-1].read_text(encoding="utf-8"))
            persisted_identity = persisted.get("config", {}).get("identity", {})
            persisted_account = str(
                persisted_identity.get("lez_account")
                or persisted_identity.get("lez_account_hex")
                or ""
            )
        if not persisted_account:
            raise RuntimeError("wallet storage exists but the persisted agent account is missing")
    identity = {
        "agent_id": agent_id,
        "messaging_address": agent_id,
        "lez_account": persisted_account,
        "lez_account_is_public": bool(persisted_account),
    }
    for key in ("signing", "encryption"):
        if isinstance(persisted_identity.get(key), dict):
            identity[key] = persisted_identity[key]
    config = {
        "network": network,
        "identity": identity,
        "wallet": {
            "config_path": str(wallet_config),
            "storage_path": str(wallet_storage),
            "password": wallet_password if create_wallet else "",
            "create": create_wallet,
            "create_agent_account": create_wallet,
            "create_agent_account_type": "public",
        },
        "policy": {
            "per_transaction_limit": os.environ.get("PER_TX_LIMIT", "0"),
            "period_limit": os.environ.get("PERIOD_LIMIT", "0"),
            "period_seconds": int(os.environ.get("PERIOD_SECONDS", "86400")),
        },
        "security": {
            "allow_dev_file_cipher": False,
            "allow_dev_a2a_secret": False,
        },
        "runtime": {"async_start": True},
        "autostart_storage": env_bool("AUTOSTART_STORAGE", True),
        "chat": {
            "name": agent_name,
            "delivery_preset": delivery,
            "log_level": os.environ.get("LOG_LEVEL", "info").lower(),
            "publish_address": True,
            "owner_conversation_id": "",
        },
        "storage": {
            "data-dir": str(DATA_DIR / "storage"),
            "log-level": os.environ.get("LOG_LEVEL", "INFO").upper(),
            "log-file": str(DATA_DIR / "storage.log"),
            "network": storage_network,
        },
        "delivery": {
            "logLevel": os.environ.get("LOG_LEVEL", "INFO").upper(),
            "mode": "Core",
            "preset": delivery,
        },
        "a2a": {
            "discovery_topic": os.environ.get("DISCOVERY_TOPIC", "/logos-agent/1/discovery/json"),
            "publish_on_start": True,
        },
        "agent_card": {
            "name": agent_name,
            "description": os.environ.get(
                "AGENT_DESCRIPTION", "Persistent Logos Agent connected to Testnet v0.2"
            ),
            "version": "0.2.0",
        },
    }
    path = AGENT_DIR / "agent-config.json"
    path.write_text(json.dumps(config, separators=(",", ":")), encoding="utf-8")
    path.chmod(0o600)
    return path


def sanitized_status() -> dict[str, Any]:
    status = parse_call(run_core("call", "logos_agent", "status"))
    messaging = status.get("messaging", {}) if isinstance(status.get("messaging"), dict) else {}
    storage = status.get("storage", {}) if isinstance(status.get("storage"), dict) else {}
    identity = status.get("identity", {}) if isinstance(status.get("identity"), dict) else {}
    chat_started = bool(messaging.get("chat_started", False))
    storage_started = bool(storage.get("started", storage.get("running", False)))
    wallet_account = identity.get("lez_account", "")
    ready = bool(status.get("ok", True)) and chat_started and storage_started and bool(wallet_account)
    return {
        "ok": ready,
        "phase": "ready" if ready else "starting-agent",
        "agent_id": status.get("agent_id", os.environ.get("AGENT_ID", "logos-agent-railway")),
        "network": status.get("network", "logos-testnet-v0.2"),
        "delivery_preset": status.get("delivery_preset", "logos.test"),
        "chat_started": chat_started,
        "chat_address": messaging.get("chat_address", ""),
        "storage_started": storage_started,
        "wallet_account": wallet_account,
        "module_versions": module_versions(),
    }


def agent_card() -> dict[str, Any]:
    return parse_call(run_core("call", "logos_agent", "invoke", "agent.card", "{}"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        try:
            if self.path in {"/", "/healthz", "/status"}:
                with STATE_LOCK:
                    payload = dict(PUBLIC_STATE)
                code = 200 if payload.get("ok") else 503
            elif self.path == "/agent-card":
                payload = agent_card()
                code = 200 if payload.get("ok", True) else 503
            else:
                payload = {"ok": False, "error": "not found"}
                code = 404
        except Exception as exc:  # Public response excludes command output and state paths.
            payload = {"ok": False, "error": type(exc).__name__}
            code = 503
        body = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: Any) -> None:
        print("health:", fmt % args, flush=True)


def monitor() -> None:
    while not STOP_EVENT.wait(10):
        try:
            update_public(**sanitized_status())
        except Exception as exc:
            update_public(ok=False, phase="degraded", error=type(exc).__name__)


def wait_for_daemon() -> None:
    for _ in range(60):
        try:
            status = json.loads(run_core("status"))
            if status.get("daemon", {}).get("status") == "running":
                return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("logoscore daemon did not become ready")


def main() -> int:
    if pathlib.Path(LOGOSCORE).name != "AppRun" or not pathlib.Path(LOGOSCORE).is_file():
        raise RuntimeError(f"portable logoscore AppRun is missing: {LOGOSCORE}")
    versions = module_versions()
    expected = {
        "delivery_module": "0.1.3",
        "storage_module": "2.0.1",
        "chat_module": "0.2.1",
        "lez_core": "0.2.0",
        "logos_agent": "0.2.0",
    }
    if versions != expected:
        raise RuntimeError(f"module version mismatch: {versions}")

    config_path = write_config()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    update_public(module_versions=versions, phase="starting-core")

    core = subprocess.Popen(
        [
            LOGOSCORE,
            "--config-dir",
            str(CORE_DIR),
            "--persistence-path",
            str(STATE_DIR),
            "-m",
            str(MODULES_DIR),
            "daemon",
        ]
    )

    def stop(signum: int, _frame: Any) -> None:
        print(f"received signal {signum}; stopping Logos Core", flush=True)
        STOP_EVENT.set()
        try:
            run_core("call", "logos_agent", "stop", check=False)
            run_core("stop", check=False)
        finally:
            if core.poll() is None:
                core.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        wait_for_daemon()
        update_public(phase="loading-modules")
        run_core("load-module", "logos_agent")
        update_public(phase="initializing-agent")
        init = parse_call(run_core("call", "logos_agent", "init", config_path.read_text(encoding="utf-8")))
        if not init.get("ok", False):
            raise RuntimeError(f"logos_agent init failed: {init.get('code', 'unknown')}")
        started = parse_call(run_core("call", "logos_agent", "start"))
        if not started.get("ok", False):
            raise RuntimeError(f"logos_agent start failed: {started.get('code', 'unknown')}")

        for _ in range(90):
            current = sanitized_status()
            update_public(**current)
            if current.get("ok"):
                break
            time.sleep(2)
        else:
            raise RuntimeError("agent did not finish Chat, Storage, and wallet startup")

        print(json.dumps({"event": "logos_agent_ready", **sanitized_status()}), flush=True)
        threading.Thread(target=monitor, daemon=True).start()
        return core.wait()
    finally:
        STOP_EVENT.set()
        server.shutdown()
        if core.poll() is None:
            core.terminate()
            try:
                core.wait(timeout=15)
            except subprocess.TimeoutExpired:
                core.kill()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        update_public(ok=False, phase="failed", error=type(exc).__name__)
        print(f"startup failed: {exc}", file=sys.stderr, flush=True)
        raise
