#!/usr/bin/env python3
"""
Render a reviewer findings artifact into a capped summary for the handoff doc.

Usage: python3 render_review_summary.py <findings-path>

Output: severity-ordered summary, capped at 3 findings + "N more in artifacts".
If the file is missing or unparseable, prints nothing and exits 0 (graceful).

Lives in the trust layer (rails/verifier/). Not agent-editable.
"""
import os
import re
import sys

CAP = 3  # max findings rendered in the handoff summary

def parse_findings(path):
    """Parse a YAML-headered markdown findings file into structured findings."""
    if not os.path.isfile(path):
        return None, []
    try:
        text = open(path, errors="replace").read()
    except Exception:
        return None, []

    # Split YAML header from body
    header = {}
    body = text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            body = parts[2]
            # Parse simple YAML key: value pairs from header
            for line in parts[1].strip().splitlines():
                m = re.match(r"^(\w[\w_]*)\s*:\s*(.+)$", line.strip())
                if m:
                    header[m.group(1)] = m.group(2).strip()

    SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}

    # v2.2 two-register format (reviewer.md's emission spec): "## CONTRACT" /
    # "## JUDGMENT" sections holding "### FAIL: title" / "### PASS: title" /
    # "### observation" items. Register order is STRUCTURAL (D45 v2.2):
    # contract failures render first, then judgment items, never interleaved;
    # PASS items are register entries, not findings. Severity (display-only)
    # comes from an optional "severity: <level>" body line.
    if re.search(r"^##\s+(CONTRACT|JUDGMENT)\s*$", body, re.M):
        findings = []
        register = None
        current = None

        def close(cur):
            if cur is None or not cur["renderable"]:
                return
            for bl in cur["body_lines"]:
                sm = re.match(r"^severity\s*:\s*(critical|high|medium|low|info)\s*$",
                              bl.strip(), re.I)
                if sm:
                    cur["severity"] = sm.group(1).lower()
            cur["severity_rank"] = SEVERITY_ORDER.get(cur["severity"], 5)
            findings.append(cur)

        for line in body.splitlines():
            rm_ = re.match(r"^##\s+(CONTRACT|JUDGMENT)\s*$", line)
            im = re.match(r"^###\s+(.+)$", line)
            if rm_:
                close(current); current = None
                register = rm_.group(1).lower()
            elif im and register:
                close(current)
                item = im.group(1).strip()
                if register == "contract":
                    fm = re.match(r"^(FAIL|PASS)\s*:\s*(.+)$", item)
                    verdict = fm.group(1) if fm else "FAIL"
                    title = fm.group(2).strip() if fm else item
                    current = {
                        "register": "contract", "verdict": verdict,
                        "renderable": verdict == "FAIL",
                        "severity": "high", "title": title, "body_lines": [],
                    }
                else:
                    current = {
                        "register": "judgment", "verdict": "",
                        "renderable": True,
                        "severity": "info", "title": item, "body_lines": [],
                    }
            elif current is not None:
                current["body_lines"].append(line)
        close(current)

        # contract failures first (severity-sorted, stable), then judgment
        # items in emission order -- the register boundary is never crossed
        contract = sorted([f for f in findings if f["register"] == "contract"],
                          key=lambda f: f["severity_rank"])
        judgment = [f for f in findings if f["register"] == "judgment"]
        return header, contract + judgment

    # legacy flat format: lines starting with "## severity: title"
    findings = []
    current = None
    for line in body.splitlines():
        m = re.match(r"^##\s+(critical|high|medium|low|info)\s*:\s*(.+)$", line, re.I)
        if m:
            if current:
                findings.append(current)
            sev = m.group(1).lower()
            current = {
                "register": "", "verdict": "", "renderable": True,
                "severity": sev,
                "severity_rank": SEVERITY_ORDER.get(sev, 5),
                "title": m.group(2).strip(),
                "body_lines": [],
            }
        elif current is not None:
            current["body_lines"].append(line)
    if current:
        findings.append(current)

    # Sort by severity (critical first)
    findings.sort(key=lambda f: f["severity_rank"])
    return header, findings


def render(path):
    """Render the capped summary."""
    header, findings = parse_findings(path)
    if header is None:
        return ""  # missing or unparseable -> graceful empty

    if not findings:
        return "**Review:** no findings."

    total = len(findings)
    shown = findings[:CAP]
    remaining = total - len(shown)

    lines = []
    lines.append("**Review findings** (contract failures first):")
    lines.append("")
    for f in shown:
        if f.get("register") == "contract":
            lines.append(f"- **FAIL {f['severity']}:** {f['title']}")
        elif f.get("register") == "judgment":
            lines.append(f"- **judgment:** {f['title']}")
        else:
            lines.append(f"- **{f['severity']}:** {f['title']}")
    if remaining > 0:
        lines.append(f"- *…{remaining} more in artifacts*")
    lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: render_review_summary.py <findings-path>", file=sys.stderr)
        sys.exit(2)
    out = render(sys.argv[1])
    if out:
        print(out)
