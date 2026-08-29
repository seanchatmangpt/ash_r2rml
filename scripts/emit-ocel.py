#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT
"""Emit one chatgpt-cloud-ocel/1 observation using only Python stdlib."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import socket
import sys
import urllib.error
import urllib.request
import uuid


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def load_receipt(path):
    if not path:
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--activity", required=True)
    parser.add_argument("--lifecycle", default="complete")
    parser.add_argument("--standing", default="UNKNOWN")
    parser.add_argument("--authority-domain", default="OBSERVE")
    parser.add_argument("--agent-id")
    parser.add_argument("--run-id")
    parser.add_argument("--sequence", type=int)
    parser.add_argument("--repo")
    parser.add_argument("--sha")
    parser.add_argument("--receipt")
    parser.add_argument("--payload-json", default="{}")
    args = parser.parse_args()

    now = dt.datetime.now(dt.timezone.utc)
    timestamp = now.isoformat().replace("+00:00", "Z")
    agent_id = args.agent_id or os.getenv("CHATGPT_AGENT_ID") or f"host:{socket.gethostname()}"
    run_id = args.run_id or os.getenv("CHATGPT_RUN_ID") or os.getenv("GITHUB_RUN_ID") or str(uuid.uuid4())
    sequence = args.sequence or int(now.timestamp() * 1_000_000)
    repo = args.repo or os.getenv("GITHUB_REPOSITORY")
    sha = args.sha or os.getenv("GITHUB_SHA")
    payload = json.loads(args.payload_json)
    receipt = load_receipt(args.receipt)

    event_id = str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            f"chatgpt-cloud:{agent_id}:{run_id}:{sequence}:{args.activity}",
        )
    )

    objects = []
    if repo:
        objects.append(
            {"id": f"repo:{repo}", "type": "Repository", "label": repo, "qualifier": "target"}
        )
    if sha:
        objects.append(
            {
                "id": f"commit:{sha}",
                "type": "Commit",
                "label": sha[:12],
                "qualifier": "subject",
                "attributes": {"repository": repo},
            }
        )

    event = {
        "id": event_id,
        "activity": args.activity,
        "lifecycle": args.lifecycle,
        "sequence": sequence,
        "standing": args.standing,
        "authority_domain": args.authority_domain,
        "timestamp": timestamp,
        "objects": objects,
        "payload": payload,
    }
    event["digest"] = digest(event)

    envelope = {
        "schema": "chatgpt-cloud-ocel/1",
        "producer": {
            "agent_id": agent_id,
            "run_id": str(run_id),
            "status": "complete" if args.lifecycle in {"complete", "stop", "error"} else "running",
            "subject_repo": repo,
            "subject_sha": sha,
            "metadata": {
                "github_workflow": os.getenv("GITHUB_WORKFLOW"),
                "github_job": os.getenv("GITHUB_JOB"),
                "github_run_attempt": os.getenv("GITHUB_RUN_ATTEMPT"),
            },
        },
        "sequence": sequence,
        "events": [event],
        "objects": objects,
        "receipts": [],
    }

    if receipt is not None:
        receipt_digest = digest(receipt)
        envelope["receipts"].append(
            {
                "id": f"receipt:{receipt_digest}",
                "standing": receipt.get("standing", args.standing),
                "subject_sha": receipt.get("subject_sha") or sha,
                "subject_tree_sha": receipt.get("subject_tree_sha"),
                "digest": receipt_digest,
                "timestamp": timestamp,
                "payload": receipt,
            }
        )

    body = (canonical(envelope) + "\n").encode()
    endpoint = os.getenv("OCEL_INGEST_URL")
    token = os.getenv("OCEL_INGEST_TOKEN")
    strict = os.getenv("OCEL_STRICT") == "1"
    spool = os.getenv("OCEL_SPOOL_DIR")

    if spool:
        path = pathlib.Path(spool)
        path.mkdir(parents=True, exist_ok=True)
        (path / f"{event_id}.json").write_bytes(body)

    if not endpoint or not token:
        sys.stdout.buffer.write(body)
        if strict:
            print("BLOCKED: OCEL_INGEST_URL/OCEL_INGEST_TOKEN are not configured", file=sys.stderr)
            return 69
        return 0

    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "content-type": "application/json",
            "authorization": f"Bearer {token}",
            "user-agent": "chatgpt-cloud-ocel-producer/1",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            result = response.read().decode()
            print(result)
            return 0 if 200 <= response.status < 300 else 1
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"BLOCKED: OCEL relay failed: {exc}", file=sys.stderr)
        if not spool:
            sys.stdout.buffer.write(body)
        return 69 if strict else 0


if __name__ == "__main__":
    raise SystemExit(main())
