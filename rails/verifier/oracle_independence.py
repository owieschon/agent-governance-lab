#!/usr/bin/env python3
"""
oracle_independence.py <root> <manifest>

Answer-leakage / solution-in-the-test defense (Job 7 Part 1, class B). A test
proves nothing if its expected value is produced by the very implementation it
is supposed to grade -- the oracle and the subject are the same, so the
assertion is true by construction. Scoped to LOAD-BEARING test files only, to
bound false positives (Job 8's precision adjudication tunes it).

Mechanical slice implemented here (the precise, low-false-positive one): an
assert / assertEqual whose BOTH compared sides call a local-implementation
symbol -- i.e. the test compares the implementation to itself. Imports that
resolve to a file under the repo are treated as "implementation under test";
stdlib / unittest / pytest imports are not.

Prints OK, or "FAIL: ..." with the offending file:line evidence. Heuristic, not
a proof -- see DECISIONS.md for the precision residual and the (b) extension
(same-dispatch verbatim expected-value leakage) left for Job 8. Lives in the
trust layer; not agent-editable.
"""
import ast
import os
import sys

STDLIB_HINTS = {
    "unittest", "pytest", "os", "sys", "re", "json", "math", "typing",
    "collections", "itertools", "functools", "datetime", "pathlib", "hashlib",
    "subprocess", "tempfile", "io", "abc", "dataclasses", "enum", "random",
}


def load_bearing_files(root, manifest):
    files = []
    lb = os.path.join(root, "rails", "verifier", "load_bearing.txt")
    try:
        for ln in open(lb):
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                files.append(ln)
    except Exception:
        pass
    # manifest entries that are file paths (contain a separator) also count
    try:
        import json
        m = json.load(open(manifest))
        for n in m.get("load_bearing_tests", []):
            if "/" in n and n.endswith(".py"):
                files.append(n)
    except Exception:
        pass
    out = []
    for f in files:
        p = os.path.join(root, f)
        if os.path.isfile(p) and f.endswith(".py") and f not in out:
            out.append(f)
    return out


def impl_symbols(root, tree):
    """Names imported from modules that resolve to a local file under root."""
    syms = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            top = node.module.split(".")[0]
            if top in STDLIB_HINTS:
                continue
            mod_path = node.module.replace(".", os.sep)
            local = (os.path.exists(os.path.join(root, mod_path + ".py"))
                     or os.path.isdir(os.path.join(root, mod_path))
                     or os.path.exists(os.path.join(root, node.module.split(".")[0])))
            if local:
                for a in node.names:
                    syms.add(a.asname or a.name)
        elif isinstance(node, ast.Import):
            for a in node.names:
                top = a.name.split(".")[0]
                if top not in STDLIB_HINTS and os.path.exists(os.path.join(root, top)):
                    syms.add(a.asname or top)
    return syms


def calls_impl(node, syms):
    for n in ast.walk(node):
        if isinstance(n, ast.Call):
            f = n.func
            name = getattr(f, "id", None) or getattr(f, "attr", None)
            base = getattr(getattr(f, "value", None), "id", None)
            if name in syms or base in syms:
                return True
    return False


def scan(root, relpath, syms):
    hits = []
    try:
        tree = ast.parse(open(os.path.join(root, relpath)).read())
    except Exception:
        return hits
    for node in ast.walk(tree):
        sides = []
        if isinstance(node, ast.Assert) and isinstance(node.test, ast.Compare):
            sides = [node.test.left] + list(node.test.comparators)
        elif isinstance(node, ast.Call):
            f = node.func
            if getattr(f, "attr", None) in ("assertEqual", "assertEquals",
                                            "assertNotEqual") and len(node.args) >= 2:
                sides = node.args[:2]
        if len(sides) >= 2:
            impl_sides = sum(1 for s in sides if calls_impl(s, syms))
            if impl_sides >= 2:
                hits.append((relpath, getattr(node, "lineno", 0)))
    return hits


def main(argv):
    root, manifest = argv[1], argv[2]
    allhits = []
    for rel in load_bearing_files(root, manifest):
        try:
            tree = ast.parse(open(os.path.join(root, rel)).read())
        except Exception:
            continue
        syms = impl_symbols(root, tree)
        if syms:
            allhits += scan(root, rel, syms)
    if not allhits:
        print("OK no self-referential oracle in load-bearing tests")
        return 0
    ev = "; ".join(f"{f}:{ln}" for f, ln in allhits)
    print("FAIL: self-referential oracle (expected value computed by the impl "
          "under test) at " + ev)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
