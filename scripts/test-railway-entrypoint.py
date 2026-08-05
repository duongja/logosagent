#!/usr/bin/env python3
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "railway_entrypoint", ROOT / "deploy" / "railway" / "entrypoint.py"
)
ENTRYPOINT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(ENTRYPOINT)


class RailwayEntrypointTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        data = pathlib.Path(self.temp.name)
        self.env = mock.patch.dict(
            os.environ,
            {
                "LOGOS_NETWORK": "logos-testnet-v0.2",
                "DELIVERY_PRESET": "logos.test",
                "STORAGE_NETWORK": "logos.test",
                "LOGOS_WALLET_PASSWORD": "test-only-password-1234",
                "AGENT_ID": "railway-test-agent",
            },
            clear=False,
        )
        self.env.start()
        self.original_paths = (
            ENTRYPOINT.DATA_DIR,
            ENTRYPOINT.CORE_DIR,
            ENTRYPOINT.STATE_DIR,
            ENTRYPOINT.AGENT_DIR,
            ENTRYPOINT.WALLET_DIR,
        )
        ENTRYPOINT.DATA_DIR = data
        ENTRYPOINT.CORE_DIR = data / "core"
        ENTRYPOINT.STATE_DIR = data / "state"
        ENTRYPOINT.AGENT_DIR = data / "agent"
        ENTRYPOINT.WALLET_DIR = data / "wallet"

    def tearDown(self):
        (
            ENTRYPOINT.DATA_DIR,
            ENTRYPOINT.CORE_DIR,
            ENTRYPOINT.STATE_DIR,
            ENTRYPOINT.AGENT_DIR,
            ENTRYPOINT.WALLET_DIR,
        ) = self.original_paths
        self.env.stop()
        self.temp.cleanup()

    def config(self):
        return json.loads(ENTRYPOINT.write_config().read_text(encoding="utf-8"))

    def test_first_boot_is_public_testnet_and_requires_password(self):
        config = self.config()
        self.assertEqual(config["network"], "logos-testnet-v0.2")
        self.assertEqual(config["delivery"]["preset"], "logos.test")
        self.assertEqual(config["storage"]["network"], "logos.test")
        self.assertTrue(config["wallet"]["create"])
        with mock.patch.dict(os.environ, {"LOGOS_WALLET_PASSWORD": "short"}):
            with self.assertRaisesRegex(RuntimeError, "at least 16"):
                ENTRYPOINT.write_config()

    def test_refuses_local_delivery_preset(self):
        with mock.patch.dict(os.environ, {"DELIVERY_PRESET": "logos.dev"}):
            with self.assertRaisesRegex(RuntimeError, "refuses localnet"):
                ENTRYPOINT.write_config()

    def test_restart_restores_wallet_and_signing_identity(self):
        ENTRYPOINT.WALLET_DIR.mkdir(parents=True)
        (ENTRYPOINT.WALLET_DIR / "wallet_storage.json").write_text("{}")
        state_dir = ENTRYPOINT.STATE_DIR / "logos_agent" / "instance"
        state_dir.mkdir(parents=True)
        state_dir.joinpath("state.json").write_text(
            json.dumps(
                {
                    "config": {
                        "identity": {
                            "lez_account_hex": "ab" * 32,
                            "signing": {"public_key_hex": "12" * 32, "private_key_hex": "34" * 32},
                            "encryption": {"public_key_hex": "56" * 32, "private_key_hex": "78" * 32},
                        }
                    }
                }
            )
        )
        config = self.config()
        self.assertFalse(config["wallet"]["create"])
        self.assertEqual(config["wallet"]["password"], "")
        self.assertEqual(config["identity"]["lez_account"], "ab" * 32)
        self.assertEqual(config["identity"]["signing"]["public_key_hex"], "12" * 32)
        self.assertEqual(config["identity"]["encryption"]["public_key_hex"], "56" * 32)

    def test_status_is_not_ready_without_all_public_components(self):
        status = {
            "ok": True,
            "agent_id": "railway-test-agent",
            "network": "logos-testnet-v0.2",
            "delivery_preset": "logos.test",
            "identity": {"lez_account": "public-account", "private_key_hex": "never-public"},
            "messaging": {"chat_started": True, "chat_address": "chat-address"},
            "storage": {"started": True},
        }
        outer = json.dumps({"result": json.dumps(status)})
        with mock.patch.object(ENTRYPOINT, "run_core", return_value=outer), mock.patch.object(
            ENTRYPOINT, "module_versions", return_value={"logos_agent": "0.2.0"}
        ):
            public = ENTRYPOINT.sanitized_status()
        self.assertTrue(public["ok"])
        self.assertNotIn("private_key_hex", json.dumps(public))


if __name__ == "__main__":
    unittest.main()
