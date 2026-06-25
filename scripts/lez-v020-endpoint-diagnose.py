#!/usr/bin/env python3
import argparse
import json
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone


SEQUENCER_METHODS = [
    "checkHealth",
    "getProgramIds",
    "getLastBlockId",
    "sendTransaction",
    "getTransaction",
    "getAccount",
]
INDEXER_METHODS = [
    "getSchema",
    "getLastFinalizedBlockId",
    "getBlockById",
    "getBlockByHash",
]
PATH_CANDIDATES = [
    "",
    "/",
    "/rpc",
    "/jsonrpc",
    "/sequencer",
    "/sequencer/rpc",
    "/api",
    "/api/rpc",
    "/api/v1/rpc",
    "/v1/rpc",
    "/lez/rpc",
    "/lee/rpc",
    "/indexer",
    "/indexer/rpc",
]


def url_with_path(base, path):
    parsed = urllib.parse.urlparse(base)
    if not parsed.scheme or not parsed.netloc:
        raise SystemExit(f"invalid URL: {base}")
    return urllib.parse.urlunparse(
        (parsed.scheme, parsed.netloc, path or parsed.path or "/", "", "", "")
    )


def rpc_call(url, method, timeout):
    payload = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": []}
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"content-type": "application/json", "user-agent": "logos-agent-endpoint-diagnose"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read(2048).decode("utf-8", "replace")
            return {
                "ok": True,
                "http_status": resp.status,
                "headers": {
                    "server": resp.headers.get("server", ""),
                    "content_type": resp.headers.get("content-type", ""),
                },
                "body": parse_json_or_text(body),
            }
    except urllib.error.HTTPError as err:
        return {
            "ok": False,
            "http_status": err.code,
            "body": parse_json_or_text(err.read(2048).decode("utf-8", "replace")),
        }
    except Exception as err:
        return {"ok": False, "error_type": type(err).__name__, "error": str(err)}


def parse_json_or_text(text):
    if not text:
        return ""
    try:
        return json.loads(text)
    except Exception:
        return text[:1000]


def method_result_kind(result):
    body = result.get("body")
    if isinstance(body, dict):
        if "result" in body and "error" not in body:
            return "result"
        error = body.get("error")
        if isinstance(error, dict):
            cause = error.get("cause")
            if isinstance(cause, dict) and cause.get("name"):
                return str(cause.get("name"))
            if error.get("message"):
                return str(error.get("message"))
    if result.get("http_status") == 404:
        return "http_404"
    if result.get("error_type"):
        return result["error_type"]
    return "unknown"


def resolve_hosts(base):
    parsed = urllib.parse.urlparse(base)
    hosts = [parsed.hostname]
    if parsed.hostname and parsed.hostname.startswith("testnet."):
        hosts.append("explorer." + parsed.hostname)
    resolved = {}
    for host in filter(None, dict.fromkeys(hosts)):
        try:
            resolved[host] = sorted({
                entry[4][0]
                for entry in socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
            })
        except Exception as err:
            resolved[host] = {"error": str(err)}
    return resolved


def main():
    parser = argparse.ArgumentParser(
        description="Diagnose whether a URL exposes the LEZ v0.2 sequencer/indexer JSON-RPC methods."
    )
    parser.add_argument("--url", default="https://testnet.lez.logos.co/")
    parser.add_argument("--timeout", type=float, default=6.0)
    parser.add_argument("--all-paths", action="store_true", help="Probe common alternate RPC paths.")
    args = parser.parse_args()

    base = args.url
    root = url_with_path(base, urllib.parse.urlparse(base).path or "/")
    methods = SEQUENCER_METHODS + INDEXER_METHODS
    root_results = {method: rpc_call(root, method, args.timeout) for method in methods}

    path_results = {}
    if args.all_paths:
        for path in PATH_CANDIDATES:
            url = url_with_path(base, path)
            path_results[url] = rpc_call(url, "checkHealth", args.timeout)

    sequencer_available = any(
        method_result_kind(root_results[m]) == "result" for m in SEQUENCER_METHODS[:3]
    )
    method_kinds = {method: method_result_kind(result) for method, result in root_results.items()}
    summary = {
        "ok": sequencer_available,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "url": base,
        "root_url": root,
        "dns": resolve_hosts(base),
        "method_kinds": method_kinds,
        "sequencer_methods_available": sequencer_available,
        "diagnosis": (
            "LEZ sequencer RPC is available"
            if sequencer_available
            else "URL does not expose the LEZ v0.2 sequencer RPC methods"
        ),
        "root_results": root_results,
        "path_probe": path_results,
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if sequencer_available else 1


if __name__ == "__main__":
    sys.exit(main())
