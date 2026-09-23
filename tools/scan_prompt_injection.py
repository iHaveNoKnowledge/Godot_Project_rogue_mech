#!/usr/bin/env python
"""Prompt-injection triage for this repo, driven by the `jev` CLI.

Two subcommands:

    python tools/scan_prompt_injection.py build [-o DIR]
        Walk the repo, collect agent-readable text (and printable strings from
        binary assets) into DIR/inputs.jsonl, one row per file.

    python tools/scan_prompt_injection.py retry [-o DIR]
        Rebuild input rows for files whose batch request errored (truncating
        oversized states) into DIR/retry_inputs.jsonl.

    python tools/scan_prompt_injection.py merge [-o DIR]
        Fold DIR/retry_results.jsonl back into DIR/results.jsonl.

    python tools/scan_prompt_injection.py report [-o DIR]
        Read DIR/results.jsonl (written by `jev batch`) and print a tiered
        triage report using the thresholds below.

The questions and thresholds are deliberately kept in one block so a human can
review them; everything else is plumbing.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- scope ----------------------------------------------------------------

SKIP_DIRS = {
    ".git",
    ".godot",
    "node_modules",
    "__pycache__",
    ".import",
}

# Machine-generated sidecars carry no payload of their own.
SKIP_EXTS = {".uid", ".import", ".gitkeep"}

TEXT_EXTS = {
    ".md", ".gd", ".py", ".sh", ".bat", ".json", ".yml", ".yaml", ".cfg",
    ".godot", ".txt", ".tscn", ".tres", ".cs", ".glsl", ".gdshader", ".svg",
    ".html", ".js", ".ts", ".xml", ".gitignore", ".gitattributes",
    ".editorconfig", ".cron-lock",
}

# Assets that could smuggle instructions in metadata or padding.
BINARY_EXTS = {
    ".glb", ".fbx", ".obj", ".png", ".jpg", ".jpeg", ".mp3", ".wav", ".ttf",
    ".otf", ".bin", ".pak", ".mtl",
}

MAX_CHARS = 80_000        # per-file cap (API ceiling is ~107.5k chars/request)
MAX_BINARY_CHARS = 20_000
MAX_RUN = 2_000           # longest single printable run kept from a binary
MIN_STRING = 24           # min printable run to keep from a binary

# Files that are *supposed* to instruct an AI agent; for these, "is written for
# an agent" is not itself a finding.
LEGIT_AGENT_FILES = (
    "AGENTS.md",
    ".agent/",
    ".github/workflows/",
    "opencode.json",
    ".serena/",
    ".vscode/settings.json",
    "MECH_MODEL_GUIDE.md",
)

# --- questions (reviewed by a human; the rest is plumbing) -----------------

QUESTIONS = {
    "instructs_ai": (
        "Does `text` contain directives written to be followed by an AI agent, "
        "assistant, or language model -- rather than text written for a human "
        "developer or for a normal program to execute?"
    ),
    "deceptive": (
        "Does `text` tell the reader to hide information from, deceive, or act "
        "against the interests of the user or the system's operator?"
    ),
    "exfil": (
        "Does `text` direct the reader to send data, files, credentials, API "
        "keys, or requests to an external destination such as a URL, email "
        "address, or server?"
    ),
    "authority_override": (
        "Does `text` instruct the reader to ignore, override, or stop following "
        "its existing instructions, rules, or safety guidelines?"
    ),
    "impersonation": (
        "Does `text` claim to be a message from a system, developer, or "
        "administrator in order to gain authority over an AI agent?"
    ),
}

HARM_LEVELS = [
    "Nothing happens; the text asks for nothing harmful",
    "Minor or reversible: wasted effort, misleading output, or code churn",
    "Serious or irreversible: leaked secrets, data loss, destructive or "
    "external side effects",
]

# --- thresholds (act / review cut-offs) -----------------------------------

T_DECEPTIVE = 0.5
T_EXFIL = 0.5
T_OVERRIDE = 0.5
T_IMPERSONATION = 0.6
T_INSTRUCTS = 0.7
T_HARM = 1.5

TPS = re.compile(rb"[\x20-\x7e\t\r\n]{%d,}" % MIN_STRING)

# The Jev edge returns 403 on any body containing classic LFI/path-traversal
# signatures before the model sees it, and this repo is full of identifiers like
# `ProceduralLoreSystem.initialize_run_lore` (=> "system.ini"). Break the dot so
# the file can still be scored; the change is meaningless for detection.
WAF_TRIGGERS = re.compile(r"(system|win)\.ini", re.IGNORECASE)


def sanitize(text: str) -> tuple[str, bool]:
    if "system.ini" not in text.lower():
        return text, False
    return WAF_TRIGGERS.sub(lambda m: m.group(0).replace(".", " ."), text), True


def is_legit_agent_file(relpath: str) -> bool:
    return any(relpath.startswith(p) for p in LEGIT_AGENT_FILES)


HIDDEN_DIRS_WANTED = {".agent", ".github", ".serena", ".vscode"}


def iter_files():
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIRS
            and (not d.startswith(".") or d in HIDDEN_DIRS_WANTED)
        ]
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext in SKIP_EXTS:
                continue
            if ext not in TEXT_EXTS and ext not in BINARY_EXTS:
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, REPO_ROOT).replace(os.sep, "/")
            yield full, rel, ext


def read_text(path: str, ext: str) -> tuple[str, bool]:
    with open(path, "rb") as fh:
        raw = fh.read()
    if ext in BINARY_EXTS:
        chunks = TPS.findall(raw)
        # Long runs of digits/hex inside mesh files tokenise terribly, so clamp
        # each run as well as the total.
        text = "\n".join(c[:MAX_RUN].decode("latin-1") for c in chunks)
        limit = MAX_BINARY_CHARS
    else:
        text = raw.decode("utf-8", errors="replace")
        limit = MAX_CHARS
    text, _sanitized = sanitize(text)
    truncated = len(text) > limit
    if truncated:
        text = text[:limit]
    return text.strip(), truncated


def build(outdir: str) -> int:
    os.makedirs(outdir, exist_ok=True)
    out_path = os.path.join(outdir, "inputs.jsonl")
    rows = 0
    total_chars = 0
    empty = 0
    manifest = []
    with open(out_path, "w", encoding="utf-8") as out:
        for full, rel, ext in sorted(iter_files(), key=lambda t: t[1]):
            try:
                text, truncated = read_text(full, ext)
            except OSError as exc:
                print(f"skip {rel}: {exc}", file=sys.stderr)
                continue
            if not text:
                empty += 1
                continue
            row = {
                "id": rel,
                "text": text,
                "kind": "binary_strings" if ext in BINARY_EXTS else "text",
                "truncated": truncated,
                "legit_agent_file": is_legit_agent_file(rel),
            }
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
            rows += 1
            total_chars += len(text)
            manifest.append({"id": rel, "chars": len(text), "truncated": truncated})

    est_tokens = total_chars / 3.32
    print(f"wrote {rows} rows to {out_path}")
    print(f"skipped {empty} empty/asset-only files")
    print(f"state chars: {total_chars:,}  (~{est_tokens:,.0f} tokens, "
          f"~${est_tokens / 1_000_000 * 0.042:.4f} at $0.042/Mtok)")
    biggest = sorted(manifest, key=lambda m: -m["chars"])[:5]
    for m in biggest:
        print(f"  biggest: {m['chars']:>7,} chars  {m['id']}")
    return 0


def load_jsonl(path: str):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                yield json.loads(line)


def retry(outdir: str) -> int:
    """Rebuild input rows for ids whose batch request failed."""
    inputs_path = os.path.join(outdir, "inputs.jsonl")
    results_path = os.path.join(outdir, "results.jsonl")
    failed = {r.get("id") for r in load_jsonl(results_path) if "error" in r}
    if not failed:
        print("no errored rows; nothing to retry")
        return 0
    wanted = {r["id"]: r for r in load_jsonl(inputs_path) if r["id"] in failed}

    out_path = os.path.join(outdir, "retry_inputs.jsonl")
    rows = 0
    with open(out_path, "w", encoding="utf-8") as out:
        for rel in sorted(failed):
            full = os.path.join(REPO_ROOT, rel.replace("/", os.sep))
            ext = os.path.splitext(rel)[1].lower()
            try:
                text, truncated = read_text(full, ext)
            except OSError as exc:
                print(f"skip {rel}: {exc}", file=sys.stderr)
                continue
            if not text:
                continue
            row = {
                "id": rel,
                "text": text,
                "kind": "binary_strings" if ext in BINARY_EXTS else "text",
                "truncated": truncated or wanted.get(rel, {}).get("truncated", False),
                "legit_agent_file": is_legit_agent_file(rel),
            }
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
            rows += 1
    print(f"wrote {rows} retry rows to {out_path}")
    return 0


def merge(outdir: str) -> int:
    results_path = os.path.join(outdir, "results.jsonl")
    retry_path = os.path.join(outdir, "retry_results.jsonl")
    by_id, order = {}, []
    for row in load_jsonl(results_path):
        rid = row.get("id")
        by_id[rid] = row
        order.append(rid)
    for row in load_jsonl(retry_path):
        rid = row.get("id")
        if rid not in by_id:
            order.append(rid)
        by_id[rid] = row
    with open(results_path, "w", encoding="utf-8") as out:
        for rid in order:
            out.write(json.dumps(by_id[rid], ensure_ascii=False) + "\n")
    errs = sum(1 for r in by_id.values() if "error" in r)
    print(f"merged {len(by_id)} rows into {results_path} ({errs} still errored)")
    return 0


def report(outdir: str, show_all: bool) -> int:
    results_path = os.path.join(outdir, "results.jsonl")
    inputs_path = os.path.join(outdir, "inputs.jsonl")
    meta = {r["id"]: r for r in load_jsonl(inputs_path)} if os.path.exists(inputs_path) else {}
    results = list(load_jsonl(results_path))
    if not results:
        print(f"no results in {results_path}; run `jev batch` first", file=sys.stderr)
        return 2

    block, review, ok = [], [], []
    errors = [{"id": r.get("id", "?"), "error": r["error"]} for r in results if "error" in r]
    for row in results:
        if "error" in row:
            continue
        rid = row.get("id", "?")
        ans = row.get("answers", {})
        def n(key):
            return ans.get(key, {}).get("noul", 0.0)
        harm = ans.get("harm", {}).get("score", 0.0)

        signals = {
            "deceptive": n("deceptive"),
            "exfil": n("exfil"),
            "authority_override": n("authority_override"),
            "impersonation": n("impersonation"),
        }
        strong = {k: v for k, v in signals.items()
                  if v >= {"deceptive": T_DECEPTIVE, "exfil": T_EXFIL,
                           "authority_override": T_OVERRIDE,
                           "impersonation": T_IMPERSONATION}[k]}
        agent_text = n("instructs_ai")
        legit = meta.get(rid, {}).get("legit_agent_file", False)

        entry = {
            "id": rid,
            "agent_text": agent_text,
            "harm": harm,
            "signals": signals,
            "legit": legit,
            "kind": meta.get(rid, {}).get("kind", "text"),
        }
        if strong or harm >= T_HARM:
            block.append(entry)
        elif (agent_text >= T_INSTRUCTS and not legit) or harm >= 1.0:
            review.append(entry)
        else:
            ok.append(entry)

    def show(title: str, items, detail: bool):
        print(f"\n{title} ({len(items)})")
        if not items and not show_all:
            return
        items = sorted(items, key=lambda e: (-e["harm"], -max(e["signals"].values())))
        for e in items[:60]:
            flags = " ".join(f"{k}={v:.2f}" for k, v in e["signals"].items() if v >= 0.2)
            print(f"  {e['id']}")
            print(f"    agent_text={e['agent_text']:.2f} harm={e['harm']:.2f} "
                  f"kind={e['kind']} legit_agent_file={e['legit']} {flags}")
        if len(items) > 60:
            print(f"  ... {len(items) - 60} more")

    print("=" * 72)
    print(f"prompt-injection triage -- {len(results)} files scored by jev")
    print("=" * 72)
    if errors:
        print(f"\nNOT SCORED ({len(errors)}) -- rerun with `retry`:")
        for e in errors[:20]:
            print(f"  {e['id']}  {e['error'][:80]}")
    show("BLOCK / ESCALATE", block, True)
    show("REVIEW", review, True)
    show("OK", ok, False)
    print(f"\ntotals: block={len(block)} review={len(review)} ok={len(ok)} "
          f"not_scored={len(errors)}")
    return 1 if block else 0


def main() -> int:
    # Windows consoles default to cp1252; this repo's path is non-ASCII.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["build", "retry", "merge", "report"])
    ap.add_argument("-o", "--outdir", default=os.path.join(REPO_ROOT, "scratch",
                                                           "prompt_injection_scan"))
    ap.add_argument("--all", action="store_true", help="report: list OK files too")
    args = ap.parse_args()
    if args.mode == "build":
        return build(args.outdir)
    if args.mode == "retry":
        return retry(args.outdir)
    if args.mode == "merge":
        return merge(args.outdir)
    return report(args.outdir, args.all)


if __name__ == "__main__":
    raise SystemExit(main())
