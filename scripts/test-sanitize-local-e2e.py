#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SANITIZER = ROOT / "scripts" / "sanitize-local-e2e.py"


def main():
    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        source = root / "raw"
        output = root / "public"
        (source / "run" / "core" / "data" / "agent").mkdir(parents=True)
        (source / "run" / "e2e.log").write_text(
            'Recovery phrase:\n  alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu\n'
            + json.dumps({
                "stdout": "Recovery phrase:\n  one two three four five six seven eight nine ten eleven twelve"
            })
            + "\n"
            '{"ok":true,"password":"secret","private_key_hex":"abcd"}\n',
            encoding="utf-8",
        )
        (source / "run" / "result.json").write_text(
            json.dumps({"ok": True, "tx_hash": "abc123", "password": "secret"}),
            encoding="utf-8",
        )
        (source / "run" / "core" / "data" / "agent" / "audit.jsonl").write_text(
            json.dumps({"ok": True, "skill": "agent.task", "private_key_hex": "abcd"}) + "\n",
            encoding="utf-8",
        )
        (source / "run" / "core" / "data" / "agent" / "state.json").write_text(
            json.dumps({"private_key_hex": "abcd"}), encoding="utf-8"
        )
        (source / "run" / "input.txt").write_text("plaintext payload", encoding="utf-8")

        subprocess.run([str(SANITIZER), str(source), str(output)], check=True)

        assert not (output / "run" / "core" / "data" / "agent" / "state.json").exists()
        assert not (output / "run" / "input.txt").exists()
        assert (output / "run" / "core" / "data" / "agent" / "audit.jsonl").is_file()
        combined = "\n".join(
            path.read_text(encoding="utf-8")
            for path in output.rglob("*")
            if path.is_file()
        )
        assert "secret" not in combined
        assert "abcd" not in combined
        assert "alpha beta gamma" not in combined
        assert "one two three" not in combined
        assert "abc123" in combined
        assert '"sanitized": true' in combined
    print("local E2E artifact sanitizer tests passed")


if __name__ == "__main__":
    main()
