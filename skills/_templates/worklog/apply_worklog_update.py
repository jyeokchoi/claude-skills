#!/usr/bin/env python3
import argparse
import sys

DASH_START = "<!-- WORKLOG:DASHBOARD:START -->"
DASH_END = "<!-- WORKLOG:DASHBOARD:END -->"
TL_INSERT = "<!-- WORKLOG:TIMELINE:INSERT:HERE -->"

def read_file(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def write_file(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

def replace_between(text: str, start: str, end: str, replacement_block: str) -> str:
    s = text.find(start)
    e = text.find(end)
    if s == -1 or e == -1 or e < s:
        raise RuntimeError(f"Dashboard markers not found or invalid: {start} .. {end}")
    e_end = e + len(end)
    return text[:s] + replacement_block + text[e_end:]

def insert_after(text: str, marker: str, insertion: str) -> str:
    i = text.find(marker)
    if i == -1:
        raise RuntimeError(f"Timeline insert marker not found: {marker}")
    j = i + len(marker)
    # Insert on next line (preserve marker line)
    return text[:j] + "\n" + insertion.rstrip() + "\n" + text[j:].lstrip("\n")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--worklog", required=True, help="Path to worklog.md")
    ap.add_argument("--dashboard-file", required=True, help="Path to file containing the full dashboard block INCLUDING markers")
    ap.add_argument("--timeline-file", required=True, help="Path to file containing one timeline entry (no markers needed)")
    args = ap.parse_args()

    worklog = read_file(args.worklog)
    dashboard_block = read_file(args.dashboard_file).rstrip() + "\n"
    timeline_entry = read_file(args.timeline_file).rstrip() + "\n"

    updated = replace_between(worklog, DASH_START, DASH_END, dashboard_block)
    updated = insert_after(updated, TL_INSERT, timeline_entry)

    write_file(args.worklog, updated)
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"[apply_worklog_update] ERROR: {e}", file=sys.stderr)
        raise SystemExit(2)
