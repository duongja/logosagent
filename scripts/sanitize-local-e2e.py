#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import re
import sys


FORBIDDEN_KEYS = {
    "a2a_secret",
    "api_key",
    "file_key",
    "key_hex",
    "mnemonic",
    "params",
    "password",
    "payload",
    "plaintext",
    "private_key",
    "private_key_hex",
    "seed",
    "token",
    "wallet_password",
    "wallet_secret",
}
PRIVATE_PARTS = {"client", "daemon", "data", "dht", "meta", "repo", "tmp"}
PRIVATE_NAMES = {
    "agent-config.json",
    "auto.json",
    "config.json",
    "state.json",
    "storage.json",
    "tokens.json",
    "wallet_config.json",
}
PLAINTEXT_NAMES = {"downloaded.txt", "input.txt"}
TEXT_SUFFIXES = {".err", ".json", ".jsonl", ".log", ".out", ".txt"}
SECRET_FIELD = re.compile(
    r'(?i)"(?:' + "|".join(re.escape(key) for key in sorted(FORBIDDEN_KEYS))
    + r')"\s*:\s*(?:"(?:\\.|[^"\\])*"|[^,}\]\r\n]+)'
)
SECRET_ASSIGNMENT = re.compile(
    r'(?i)\b(?:' + "|".join(re.escape(key) for key in sorted(FORBIDDEN_KEYS))
    + r')\s*=\s*\S+'
)
RECOVERY_PHRASE = re.compile(
    r'(?is)(recovery phrase\s*:\s*\n\s*)(?:[a-z]+(?:\s+|\n\s*)){11,}[a-z]+'
)
ESCAPED_RECOVERY_PHRASE = re.compile(
    r'(?i)(recovery phrase\s*:\\n\s*)(?:[a-z]+[ \t]+){11,}[a-z]+'
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def scrub_value(value):
    if isinstance(value, dict):
        return {
            key: scrub_value(child)
            for key, child in value.items()
            if key.lower() not in FORBIDDEN_KEYS
        }
    if isinstance(value, list):
        return [scrub_value(child) for child in value]
    if isinstance(value, str):
        return scrub_text(value)
    return value


def scrub_text(text):
    text = RECOVERY_PHRASE.sub(r"\1[REDACTED]", text)
    text = ESCAPED_RECOVERY_PHRASE.sub(r"\1[REDACTED]", text)
    text = SECRET_FIELD.sub('"redacted_field":"[REDACTED]"', text)
    return SECRET_ASSIGNMENT.sub("redacted_field=[REDACTED]", text)


def should_copy(relative):
    if relative.name in PLAINTEXT_NAMES or relative.name in PRIVATE_NAMES:
        return False
    if relative.suffix.lower() not in TEXT_SUFFIXES:
        return False
    if relative.name == "audit.jsonl":
        return True
    return not PRIVATE_PARTS.intersection(part.lower() for part in relative.parts)


def sanitize_file(source, destination):
    text = source.read_text(encoding="utf-8", errors="replace")
    if source.suffix.lower() == ".json":
        try:
            text = json.dumps(scrub_value(json.loads(text)), indent=2) + "\n"
        except json.JSONDecodeError:
            text = scrub_text(text)
    elif source.suffix.lower() == ".jsonl":
        lines = []
        for line in text.splitlines():
            if not line.strip():
                continue
            try:
                lines.append(json.dumps(scrub_value(json.loads(line)), separators=(",", ":")))
            except json.JSONDecodeError:
                lines.append(scrub_text(line))
        text = "\n".join(lines) + ("\n" if lines else "")
    else:
        text = scrub_text(text)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")


def validate_output(root):
    errors = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if relative.name in PRIVATE_NAMES or relative.name in PLAINTEXT_NAMES:
            errors.append(f"private artifact retained: {relative}")
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if SECRET_FIELD.search(text) or SECRET_ASSIGNMENT.search(text):
            errors.append(f"secret field retained: {relative}")
        if RECOVERY_PHRASE.search(text) or ESCAPED_RECOVERY_PHRASE.search(text):
            errors.append(f"recovery phrase retained: {relative}")
    return errors


def main():
    parser = argparse.ArgumentParser(description="Create sanitized CI-local E2E artifacts.")
    parser.add_argument("input_dir", type=pathlib.Path)
    parser.add_argument("output_dir", type=pathlib.Path)
    args = parser.parse_args()

    source_root = args.input_dir.resolve()
    output_root = args.output_dir.resolve()
    if not source_root.is_dir():
        raise SystemExit(f"input evidence directory is missing: {source_root}")
    if output_root == source_root or source_root in output_root.parents:
        raise SystemExit("output directory must be outside the raw evidence directory")

    if output_root.exists():
        raise SystemExit(f"output evidence directory already exists: {output_root}")
    output_root.mkdir(parents=True)

    copied = []
    for source in sorted(source_root.rglob("*")):
        if not source.is_file():
            continue
        relative = source.relative_to(source_root)
        if not should_copy(relative):
            continue
        destination = output_root / relative
        sanitize_file(source, destination)
        copied.append({
            "path": relative.as_posix(),
            "sha256": sha256(destination),
            "bytes": destination.stat().st_size,
        })

    manifest = {
        "schema": "logos.agent.local-e2e-artifacts.v1",
        "sanitized": True,
        "source": source_root.name,
        "files": copied,
    }
    (output_root / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    errors = validate_output(output_root)
    result = {"ok": not errors, "files": len(copied), "errors": errors}
    print(json.dumps(result, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
