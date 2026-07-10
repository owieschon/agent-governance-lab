#!/usr/bin/env python3
"""
exercised_assertions.py <root> <manifest> <suite_log>

Precondition-masked-pass defense (Job 7 Part 1, class C). Generalizes the
count-reconciliation idea to PER-TEST accounting: a load-bearing test that is
collected but SKIPPED, xfailed, or never actually executed reports nothing and
the suite stays green -- a silent no-op. This check parses the suite log for
each named load-bearing test and FAILs if any is skipped/xfailed or absent from
the run while it should have executed.

Runner support: per-test output is required -- pytest `-rA` or `unittest -v`.
Without it the check reports NA (it cannot account for what it cannot see); that
runner-specificity is the stated residual (see DECISIONS; jest: use
`--verbose` and the per-test PASS/SKIP lines). Heuristic on log format. Lives
in the trust layer; not agent-editable.
"""
import json, os, re, sys

SKIP = re.compile(r"\b(skipped|xfail|xfailed|expected failure)\b", re.I)
OKP = re.compile(r"(\bok\b|\bPASSED\b|\bPASS\b)")


def lb_names(root, manifest):
    names = []
    try:
        m = json.load(open(manifest))
        for n in m.get("load_bearing_tests", []):
            if "/" not in n:          # a test name/id, not a file path
                names.append(n)
    except Exception:
        pass
    try:
        for ln in open(os.path.join(root, "rails", "verifier", "load_bearing.txt")):
            ln = ln.strip()
            if ln and not ln.startswith("#") and "/" not in ln and not ln.endswith(".py"):
                names.append(ln)
    except Exception:
        pass
    return list(dict.fromkeys(names))


def main(argv):
    root, manifest, logp = argv[1], argv[2], argv[3]
    names = lb_names(root, manifest)
    if not names:
        print("OK no named load-bearing tests to account for")
        return 0
    try:
        lines = open(logp, errors="replace").read().splitlines()
    except Exception:
        print("NA no suite log")
        return 0
    if not any(OKP.search(l) or "::" in l for l in lines):
        print("NA suite log has no per-test accounting (need pytest -rA / unittest -v)")
        return 0
    problems = []
    for n in names:
        hit = [l for l in lines if n in l]
        if any(SKIP.search(l) for l in hit):
            problems.append(f"{n} (skipped/xfailed)")
        elif not any(OKP.search(l) for l in hit):
            problems.append(f"{n} (collected but not executed/passed)")
    if problems:
        print("FAIL: load-bearing test not exercised: " + ", ".join(problems))
    else:
        print("OK all load-bearing tests executed and passed by name")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
