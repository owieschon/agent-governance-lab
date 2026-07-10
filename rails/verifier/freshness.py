#!/usr/bin/env python3
"""
freshness.py -- the cold-start freshness model (Job 9b Part 5).

An artifact is matched to what its data can support right now. A demonstrated
catch needs no history and shows day one; an
accumulation artifact (a rate, a trend, a mean) below its meaning threshold
must show a forward-pointing "not enough history yet" state, never an empty or
misleading zero, and never a sad/empty state.

This is the ONE place that decision is made, so every accumulation surface
(scoreboard, and Job 8's status signals already do their own variant) renders
the same way. Reuses Job 8's min-sample discipline; the default floor is the
same small N a window needs to mean anything.

A line is meaningful() iff it has at least `min_n` observations. When it is
not, state() returns a forward-pointing sentence naming how many more are
needed; the caller prints that instead of the metric. Callers that have a real
value print it via value(); the helper never invents a number.

CLI (so shell surfaces can use it without reimplementing the rule):
  freshness.py meaningful <count> [min_n]      # exit 0 if meaningful, else 1
  freshness.py state <count> <label> [min_n]   # prints the forward-pointing
                                               # line (empty if meaningful)
Lives in the trust layer; not agent-editable.
"""
import sys

DEFAULT_MIN_N = 3   # same small-sample floor Job 8's windows use


def meaningful(count, min_n=DEFAULT_MIN_N):
    try:
        return int(count) >= int(min_n)
    except Exception:
        return False


def state(count, label, min_n=DEFAULT_MIN_N):
    """Forward-pointing cold-start line, or '' when the metric is meaningful."""
    if meaningful(count, min_n):
        return ""
    try:
        have = max(0, int(count))
    except Exception:
        have = 0
    need = int(min_n) - have
    return (f"not enough history yet for {label}: {have} of {min_n} "
            f"({need} more to go) -- shown once there is enough to mean something")


def _main(argv):
    if len(argv) >= 3 and argv[1] == "meaningful":
        mn = int(argv[3]) if len(argv) > 3 else DEFAULT_MIN_N
        return 0 if meaningful(argv[2], mn) else 1
    if len(argv) >= 4 and argv[1] == "state":
        mn = int(argv[4]) if len(argv) > 4 else DEFAULT_MIN_N
        line = state(argv[2], argv[3], mn)
        if line:
            print(line)
        return 0
    print("usage: freshness.py meaningful <count> [min_n] | "
          "state <count> <label> [min_n]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
