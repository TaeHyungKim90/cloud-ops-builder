#!/usr/bin/env python3
"""trivy image → out/trivy-image-summary.md 요약.

Usage:
  python3 scripts/trivy_image_summary.py
  python3 scripts/trivy_image_summary.py nexus.sk-inc.com:8081/cr/cloud-ops-builder:v1.2.0
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMAGE = "nexus.sk-inc.com:8081/cr/cloud-ops-builder:v1.2.0"
DEFAULT_SEVERITY = "HIGH,CRITICAL"
OUT_DIR = ROOT / "out"
JSON_OUT = OUT_DIR / "trivy-image.json"
MD_OUT = OUT_DIR / "trivy-image-summary.md"


def _run_trivy(image: str, severity: str, json_path: Path) -> int:
    if not shutil.which("trivy"):
        print("[trivy-image] trivy not found in PATH", file=sys.stderr)
        return 127
    json_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "trivy",
        "image",
        "--severity",
        severity,
        "--format",
        "json",
        "--output",
        str(json_path),
        image,
    ]
    print(f"[trivy-image] {' '.join(cmd)}", flush=True)
    proc = subprocess.run(cmd, cwd=str(ROOT))
    return proc.returncode


def _fixed_version(vuln: dict) -> str:
    fixed = vuln.get("FixedVersion") or ""
    if fixed:
        return str(fixed)
    return "-"


def _collect_vulns(report: dict) -> list[dict]:
    rows: list[dict] = []
    for result in report.get("Results") or []:
        target = result.get("Target") or ""
        class_ = result.get("Class") or result.get("Type") or ""
        for v in result.get("Vulnerabilities") or []:
            rows.append(
                {
                    "target": target,
                    "class": class_,
                    "pkg": v.get("PkgName") or "-",
                    "vuln_id": v.get("VulnerabilityID") or "-",
                    "severity": (v.get("Severity") or "UNKNOWN").upper(),
                    "installed": v.get("InstalledVersion") or "-",
                    "fixed": _fixed_version(v),
                    "title": (v.get("Title") or v.get("Description") or "")[:120],
                    "status": v.get("Status") or "",
                    "primary_url": (v.get("PrimaryURL") or ""),
                }
            )
    order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 9}
    rows.sort(key=lambda r: (order.get(r["severity"], 9), r["pkg"], r["vuln_id"]))
    return rows


def _write_md(image: str, severity: str, rows: list[dict], path: Path) -> None:
    counts = Counter(r["severity"] for r in rows)
    now = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    lines = [
        "# Trivy image summary",
        "",
        f"- **Image**: `{image}`",
        f"- **Severity filter**: `{severity}`",
        f"- **Scanned at**: {now}",
        f"- **Total**: {len(rows)} "
        f"(CRITICAL: {counts.get('CRITICAL', 0)}, HIGH: {counts.get('HIGH', 0)}, "
        f"MEDIUM: {counts.get('MEDIUM', 0)}, LOW: {counts.get('LOW', 0)})",
        "",
    ]
    if not rows:
        lines.extend(["## Findings", "", "취약점 없음.", "", ""])
        path.write_text("\n".join(lines), encoding="utf-8")
        return

    lines.extend(
        [
            "## Findings",
            "",
            "| Severity | Package | Vulnerability | Installed | Fixed | Title |",
            "|----------|---------|---------------|-----------|-------|-------|",
        ]
    )
    for r in rows:
        title = r["title"].replace("|", "\\|")
        vid = r["vuln_id"]
        if r["primary_url"]:
            vid = f"[{vid}]({r['primary_url']})"
        lines.append(
            f"| {r['severity']} | `{r['pkg']}` | {vid} | `{r['installed']}` | "
            f"`{r['fixed']}` | {title} |"
        )
    lines.extend(["", "## By package", ""])
    by_pkg: dict[str, list[dict]] = {}
    for r in rows:
        by_pkg.setdefault(r["pkg"], []).append(r)
    for pkg, items in sorted(by_pkg.items()):
        ids = ", ".join(i["vuln_id"] for i in items)
        lines.append(
            f"- **`{pkg}`** `{items[0]['installed']}` → fix `{items[0]['fixed']}`: {ids}"
        )
    lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "image",
        nargs="?",
        default=os.environ.get("TRIVY_IMAGE", DEFAULT_IMAGE),
    )
    parser.add_argument(
        "--severity",
        default=os.environ.get("TRIVY_SEVERITY", DEFAULT_SEVERITY),
    )
    parser.add_argument("--json-out", type=Path, default=JSON_OUT)
    parser.add_argument("--md-out", type=Path, default=MD_OUT)
    parser.add_argument(
        "--skip-scan",
        action="store_true",
        help="기존 JSON만으로 md 재생성",
    )
    args = parser.parse_args()

    if not args.skip_scan:
        rc = _run_trivy(args.image, args.severity, args.json_out)
        if rc not in (0, 1):  # 1: vulns found with --exit-code (we don't set it)
            # trivy returns 0 even with findings unless --exit-code 1
            if rc != 0:
                print(f"[trivy-image] trivy exit {rc}", file=sys.stderr)
                return rc

    if not args.json_out.is_file():
        print(f"[trivy-image] missing {args.json_out}", file=sys.stderr)
        return 1

    report = json.loads(args.json_out.read_text(encoding="utf-8"))
    # ArtifactName may be present
    image = report.get("ArtifactName") or args.image
    rows = _collect_vulns(report)
    args.md_out.parent.mkdir(parents=True, exist_ok=True)
    _write_md(image, args.severity, rows, args.md_out)
    print(
        f"[trivy-image] findings={len(rows)} → {args.md_out.relative_to(ROOT)} "
        f"(json: {args.json_out.relative_to(ROOT)})",
        flush=True,
    )
    # console short table
    print("", flush=True)
    print(f"{'Severity':<10} {'Package':<22} {'CVE':<18} {'Installed':<12} Fixed", flush=True)
    print("-" * 88, flush=True)
    for r in rows:
        print(
            f"{r['severity']:<10} {r['pkg']:<22} {r['vuln_id']:<18} "
            f"{r['installed']:<12} {r['fixed']}",
            flush=True,
        )
    if not rows:
        print("(no HIGH/CRITICAL findings)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
