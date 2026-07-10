"""Command-line front door for Agent Governance Lab."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from typing import Sequence

from . import PRODUCT_NAME, RECEIPT_VERSION, VERSION
from .demo import run_demo
from .receipt import ReceiptError, verify_receipt


def _delegate(root: Path, command: list[str], *, env: dict[str, str] | None = None) -> int:
    completed = subprocess.run(command, cwd=root, env=env, check=False)
    return completed.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agl",
        description="Independent release governance and evidence for coding-agent work.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    identity = sub.add_parser("identity", help="print the canonical product identity")
    identity.add_argument("--json", action="store_true")

    demo = sub.add_parser("demo", help="run the real oracle-tampering catch")
    demo.add_argument("--receipt", type=Path, help="where to write the JSON receipt")

    verify = sub.add_parser(
        "verify-receipt",
        help="validate a receipt's schema, semantics, and content address",
    )
    verify.add_argument("receipt", type=Path)
    verify.add_argument(
        "--workspace",
        type=Path,
        help="also recompute the receipt's final candidate hashes from this workspace",
    )

    dispatch_verify = sub.add_parser("verify", help="run the existing release verifier")
    dispatch_verify.add_argument("dispatch_id")

    prove = sub.add_parser("prove", help="run the adversarial governor suite")
    prove.add_argument("--no-stamp", action="store_true", help="prove without updating registry")

    sub.add_parser("doctor", help="run installation preflight")
    sub.add_parser("status", help="show current governance state")
    return parser


def main(argv: Sequence[str] | None = None, *, repo_root: str | Path | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    root = Path(repo_root).resolve() if repo_root else Path(__file__).resolve().parents[2]
    try:
        if args.command == "identity":
            identity = {
                "name": PRODUCT_NAME,
                "cli": "agl",
                "version": VERSION,
                "receipt_schema": RECEIPT_VERSION,
            }
            print(json.dumps(identity, sort_keys=True) if args.json else f"{PRODUCT_NAME} (agl {VERSION})")
            return 0
        if args.command == "demo":
            run_demo(root, args.receipt)
            return 0
        if args.command == "verify-receipt":
            receipt = verify_receipt(args.receipt, args.workspace)
            print(
                "PASS: receipt is internally consistent and content-addressed "
                f"({receipt['receipt_sha256']})"
            )
            return 0
        if args.command == "verify":
            return _delegate(
                root,
                ["bash", "rails/verifier/verify.sh", args.dispatch_id],
            )
        if args.command == "prove":
            env = os.environ.copy()
            if args.no_stamp:
                env["RAILS_NO_STAMP"] = "1"
            return _delegate(root, ["bash", "rails/adversarial/run_eval.sh"], env=env)
        if args.command == "doctor":
            return _delegate(root, ["bash", "rails/verifier/doctor.sh"])
        if args.command == "status":
            return _delegate(root, ["bash", "rails/verifier/status.sh"])
    except ReceiptError as exc:
        print(f"FAIL: {exc}", file=os.sys.stderr)
        return 1
    parser.error(f"unknown command: {args.command}")
    return 2
