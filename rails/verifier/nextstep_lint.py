#!/usr/bin/env python3
"""
nextstep_lint.py -- the L6 mechanized check (Job 8 Part D2).

Every block/flag/error message states a condition AND at least one concrete
next action that addresses it. A message with no next step is a dead end; this
lint fails it.

Scope (v1, documented residual): the literal string arguments of the kit's
blocking/flagging call sites -- deny()/block()/bad()/refuse() -- in
  - .claude/hooks/*.py            (parsed with ast)
  - rails/verifier/*.py           (parsed with ast)
  - rails/verifier/*.sh           (their embedded <<'PY' python blocks,
                                   extracted then parsed with ast)
Free-form echo/printf flag text in shell is outside v1 (no reliable
extraction); the eval's case asserts the lint both passes the shipped kit
and fires on a planted dead-end message. The action-clause test is a
HEURISTIC (verb/path/command markers); Part B's false-block adjudication is
the tuning loop if it ever blocks a legitimate message.

CLI: nextstep_lint.py <proj>   -> exit 0 clean; exit 1 lists each dead end.
Lives in the trust layer; not agent-editable.
"""
import ast
import glob
import os
import re
import sys

CALL_NAMES = {"deny", "block", "bad", "refuse"}

# A concrete action clause: an imperative verb, a kit path, a script, or an
# explicit human-routing phrase.
ACTION = re.compile(
    r"(?i)\b(run|re-?run|set|use|write|declare|describe|state|ask|links?|edit"
    r"|propose|release|revert|move|add|remove|see|follow|fix|check|provide"
    r"|read|draft|wait|stop|hand|report|record|adjudicate|produce|build"
    r"|review)\b"
    r"|rails/|\.sh\b|\.py\b|the human"
)

HEREDOC = re.compile(r"<<'PY'\n(.*?)\nPY\b", re.S)


def literal_text(node):
    """Best-effort literal content of a message expression: plain strings,
    f-string literal parts, and +-concatenations. Non-literal parts (vars,
    format calls) contribute nothing -- the lint judges only what is fixed."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        return "".join(literal_text(v) for v in node.values
                       if isinstance(v, ast.Constant))
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
        return literal_text(node.left) + literal_text(
            node.right if isinstance(node.op, ast.Add) else ast.Constant(""))
    return ""


def lint_source(src, label, failures):
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        name = fn.id if isinstance(fn, ast.Name) else (
            fn.attr if isinstance(fn, ast.Attribute) else "")
        if name not in CALL_NAMES or not node.args:
            continue
        text = literal_text(node.args[0]).strip()
        if not text:
            continue  # fully dynamic message: nothing fixed to judge
        if not ACTION.search(text):
            failures.append((label, node.lineno, text[:100]))


def main(proj):
    failures = []
    py_files = sorted(
        glob.glob(os.path.join(proj, ".claude", "hooks", "*.py"))
        + glob.glob(os.path.join(proj, "rails", "verifier", "*.py")))
    for p in py_files:
        if os.path.basename(p) == os.path.basename(__file__):
            continue
        try:
            src = open(p, errors="replace").read()
        except Exception:
            continue
        lint_source(src, os.path.relpath(p, proj), failures)
    for p in sorted(glob.glob(os.path.join(proj, "rails", "verifier", "*.sh"))):
        try:
            src = open(p, errors="replace").read()
        except Exception:
            continue
        for i, m in enumerate(HEREDOC.finditer(src)):
            lint_source(m.group(1), f"{os.path.relpath(p, proj)} (py block {i+1})",
                        failures)
    if failures:
        print("L6 NEXT-STEP LINT: message(s) state a condition with no next "
              "step. Add a concrete action clause (what the reader does now) "
              "to each:", file=sys.stderr)
        for label, line, text in failures:
            print(f"  {label}:{line}: \"{text}\"", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else os.getcwd()))
