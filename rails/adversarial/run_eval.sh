#!/usr/bin/env bash
#
# run_eval.sh: the demonstrate-the-catch layer for the governor.
#
# Runs every known-bad case (core, then project) in a fresh sandbox each,
# proving each check fires on its violation and stays quiet on clean work.
# On a FULL pass it stamps rails/adversarial/registry.json with the current
# governor fingerprint; verify.sh refuses to certify any dispatch until
# that stamp matches (a changed governor does not take force unproven).
#
# Find, don't fix (spec section 7): this script surfaces and proves. It
# never modifies the trust layer. Gaps it finds become human work.
#
# Isolation (spec section 6): core and project scopes run and report
# separately; a project's gap never greens the core, and vice versa.
set -u
HOST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$HOST/rails/adversarial"
RUNID="$(date -u +%Y%m%dT%H%M%SZ)"
EVID="$HOST/rails/evidence/ADVERSARIAL/$RUNID"
mkdir -p "$EVID"

# bash 3.2 portability: no associative arrays. Case names are dynamic (and
# contain '/'), so status is held in parallel indexed arrays looked up by a
# linear scan -- the case count is tiny.
NAMES=(); STATES=()
_set_status() { NAMES+=("$1"); STATES+=("$2"); }
_status_of() {  # _status_of <name> -> echoes state or MISSING
  local q="$1" i
  for i in "${!NAMES[@]}"; do
    [ "${NAMES[$i]}" = "$q" ] && { printf '%s' "${STATES[$i]}"; return; }
  done
  printf 'MISSING'
}
TOTAL=0; FAILED=0

run_scope() {  # run_scope <scope>
  local scope="$1"
  local dir="$HERE/cases/$scope"
  [ -d "$dir" ] || return 0
  shopt -s nullglob
  for case_sh in "$dir"/*.sh; do
    local name; name="$scope/$(basename "$case_sh" .sh)"
    TOTAL=$((TOTAL + 1))
    printf '== %s\n' "$name"
    local sb; sb="$(bash "$HERE/fixture.sh" 2>"$EVID/$(basename "$case_sh").fixture.err")"
    if [ -z "$sb" ] || [ ! -d "$sb" ]; then
      _set_status "$name" "FAIL (fixture)"; FAILED=$((FAILED + 1))
      printf '    FAIL fixture did not build\n'; continue
    fi
    if SANDBOX="$sb" KIT_HOST="$HOST" bash "$case_sh" >"$EVID/$(basename "$case_sh").log" 2>&1; then
      _set_status "$name" "PASS"
    else
      _set_status "$name" "FAIL"; FAILED=$((FAILED + 1))
    fi
    sed 's/^/  /' "$EVID/$(basename "$case_sh").log"
    [ "${KEEP_SANDBOX:-0}" = "1" ] || rm -rf "$sb"
  done
}

skip_scope_kitdev() {  # installer absent (installed target): report, don't run, don't fail
  local dir="$HERE/cases/kitdev" case_sh name
  echo
  echo "=============== KITDEV SCOPE: not applicable in this repo ==========="
  echo "  No install.sh here -> this is an installed target, not the kit-dev"
  echo "  source. The installer/eject cases below cannot run by construction"
  echo "  (install.sh is the installer, never shipped into an installed tree);"
  echo "  they are proven in kit-dev CI (.github/workflows/prove.yml). Reported"
  echo "  here, never skipped silently, and they do not gate this target's proof."
  shopt -s nullglob
  for case_sh in "$dir"/*.sh; do
    name="kitdev/$(basename "$case_sh" .sh)"
    _set_status "$name" "N/A"
    printf '  N/A  %s (requires the installer)\n' "$name"
  done
}

run_scope core
run_scope project
# kitdev scope: cases that exercise the installer/eject tooling, which lives
# ONLY in the kit-dev source -- install.sh is the installer, never part of an
# installed target's tree. Run them where the installer exists; everywhere else
# report them N/A. A target that lacks the installer must not FAIL these (that
# would block every legitimate install's governor proof) nor skip them silently.
if [ -f "$HOST/install.sh" ]; then
  run_scope kitdev
else
  skip_scope_kitdev
fi

# ---- coverage register: spec section 3 classes -> cases ------------------
classmap() {  # classmap <class> -> echoes the case path(s) proving it
  case "$1" in
    weaken-a-check)           echo "core/01_weaken_a_check" ;;
    off-live-path)            echo "core/02_off_live_path" ;;
    vacuous-test)             echo "core/03_vacuous_test" ;;
    partial-run-green)        echo "core/04_partial_run_green" ;;
    claim-not-landed)         echo "core/05_claim_not_landed" ;;
    not-exercised-as-pass)    echo "core/06_not_exercised" ;;
    boundary-breach)          echo "core/07_boundary_breach" ;;
    inflation)                echo "core/08_stale_green_stop_gate + core/09_forge_a_verdict" ;;
    undisclosed-judgment)     echo "core/10_undisclosed_decisions" ;;
    unproven-governor-change) echo "core/11_governor_drift" ;;
    incident-ledger)          echo "core/12_incident_ledger" ;;
    oracle-tampering)         echo "core/14_oracle_tampering" ;;
    answer-leakage)           echo "core/15_answer_leakage" ;;
    masked-precondition)      echo "core/16_masked_precondition" ;;
    environment-dependent-green) echo "core/17_environment_dependent_green" ;;
    posture-invariant)        echo "core/18_posture_invariant" ;;
    floor-invariant)          echo "core/18_posture_invariant + core/19_l5_footprint" ;;
    default-footprint)        echo "core/19_l5_footprint" ;;
    next-step-lint)           echo "core/20_l6_nextstep_lint" ;;
    receipt-provenance)       echo "core/21_receipt_provenance" ;;
    precision-adjudication)   echo "core/22_precision_adjudication" ;;
    demo-real-catch)          echo "core/23_demo_real_catch" ;;
    init-seeds-never-stamps)  echo "core/24_init_seeds_never_stamps" ;;
    eject-clean)              echo "core/25_eject_clean" ;;
    eject-roundtrip)          echo "kitdev/26_eject_roundtrip" ;;
    freshness-states)         echo "core/27_freshness_states" ;;
    quarantine-smuggling)     echo "core/30_quarantine_lane" ;;
    reviewer-posture-breach)  echo "core/31_reviewer_posture" ;;
    gate-ignores-review)      echo "core/32_gate_ignores_review" ;;
    findings-cap)             echo "core/33_findings_cap" ;;
    minimal-grounding)        echo "core/34_minimal_grounding" ;;
    push-indirection)         echo "core/35_push_indirection" ;;
    symlink-attack)           echo "core/36_symlink_attack" ;;
    git-config-alias)         echo "core/37_git_config_alias" ;;
    fail-open-json)           echo "core/38_fail_open_json" ;;
    heredoc-injection)        echo "core/39_heredoc_injection" ;;
    exhaust-context)          echo "core/41_exhaust_context" ;;
    draft-vs-verdict)         echo "core/42_draft_vs_verdict" ;;
    handoff-review-wiring)    echo "kitdev/43_handoff_review_wiring" ;;
    review-hang-timeout)      echo "core/44_review_hang_timeout" ;;
    review-success-render)    echo "core/45_review_success_render" ;;
    reviewer-fp-corpus-fence) echo "core/46_reviewer_fp_fence" ;;
    observer-containment)     echo "core/47_observer_containment" ;;
    inbox-create-only)        echo "core/48_inbox_create_only" ;;
    observer-protected-set)   echo "core/49_observer_protected_set" ;;
    observer-runner)          echo "core/50_observer_runner" ;;
    notify-default-off)       echo "core/50_observer_runner" ;;
  esac
}

echo
echo "=============== COVERAGE REGISTER (known classes) ==============="
for cls in weaken-a-check off-live-path vacuous-test partial-run-green \
           claim-not-landed not-exercised-as-pass boundary-breach inflation \
           undisclosed-judgment unproven-governor-change incident-ledger \
           oracle-tampering answer-leakage \
           masked-precondition environment-dependent-green \
           posture-invariant floor-invariant default-footprint \
           next-step-lint receipt-provenance precision-adjudication \
           demo-real-catch init-seeds-never-stamps \
           eject-clean eject-roundtrip freshness-states \
           quarantine-smuggling \
           reviewer-posture-breach gate-ignores-review \
           findings-cap minimal-grounding \
           push-indirection symlink-attack git-config-alias \
           fail-open-json heredoc-injection \
           exhaust-context draft-vs-verdict \
           handoff-review-wiring review-hang-timeout \
           review-success-render reviewer-fp-corpus-fence \
           observer-containment inbox-create-only observer-protected-set \
           observer-runner notify-default-off; do
  cases="$(classmap "$cls")"
  ok=1; na=0
  for c in ${cases//+/ }; do
    c="$(echo "$c" | xargs)"; [ -z "$c" ] && continue
    st="$(_status_of "$c")"
    if [ "$st" = "N/A" ]; then na=1; continue; fi
    [ "$st" = "PASS" ] || ok=0
  done
  if [ "$na" -eq 1 ]; then v="N/A (kit-dev)"; elif [ "$ok" -eq 1 ]; then v="PROVEN"; else v="NOT PROVEN"; fi
  printf '  %-26s %-11s (%s)\n' "$cls" "$v" "$cases"
done
echo "  (gaps beyond these classes are unenumerated by definition;"
echo "   the boundaries bound their blast radius -- spec section 5)"

echo
echo "=============== CASE RESULTS (core | project isolated) ==========="
for k in $(printf '%s\n' "${NAMES[@]}" | sort); do
  printf '  %-34s %s\n' "$k" "$(_status_of "$k")"
done

# ---- stamp only on a full pass -------------------------------------------
if [ "$FAILED" -eq 0 ] && [ "$TOTAL" -gt 0 ]; then
  # Accretion gate: an unlinked incident is a failure class that bit us and is
  # not yet guaranteed against. The governor does not re-stamp until every
  # incident points at the eval case that now covers it.
  if ! python3 "$HOST/rails/verifier/incident.py" check "$HOST"; then
    echo
    echo "GOVERNOR NOT PROVEN: unlinked incident(s) above. Set linked_case on"
    echo "each to the eval case that now covers it, then re-run. NOT stamped."
    echo "evidence: rails/evidence/ADVERSARIAL/$RUNID/"
    exit 1
  fi
  # CI proves but does not stamp: stamping the registry is a local, human-
  # released act, never something a CI runner writes. CI just asserts green.
  if [ "${RAILS_NO_STAMP:-0}" = "1" ]; then
    echo
    echo "GOVERNOR PROVEN (CI mode, RAILS_NO_STAMP=1): all $TOTAL cases passed."
    echo "Registry NOT stamped -- stamping stays a local human-released act."
    echo "evidence: rails/evidence/ADVERSARIAL/$RUNID/"
    exit 0
  fi
  python3 - "$HOST" "$RUNID" "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" <<'PYEOF'
import json, platform, shutil, subprocess, sys
host, runid, bashv = sys.argv[1], sys.argv[2], sys.argv[3]
fp = subprocess.run(["python3", host + "/rails/verifier/fingerprint.py", host],
                    capture_output=True, text=True).stdout.strip()
cc = "unknown"
if shutil.which("claude"):
    try:
        cc = subprocess.run(["claude", "--version"], capture_output=True,
                            text=True, timeout=10).stdout.strip() or "unknown"
    except Exception:
        pass
json.dump({
    "last_proven_fingerprint": fp,
    "run_id": runid,
    "stamped_by": "run_eval.sh (full pass)",
    "environment": {
        "python": ".".join(platform.python_version_tuple()[:2]),
        "bash": bashv,
        "claude_code": cc,
    },
}, open(host + "/rails/adversarial/registry.json", "w"), indent=2)
print(f"\nGOVERNOR PROVEN: registry stamped (fingerprint {fp[:16]}..., cc={cc})")
# The fingerprint hashes the FILESYSTEM, so untracked files join the stamp
# silently -- content no diff ever showed a reviewer. Surface them at the one
# moment that matters: when the stamp is written.
unt = subprocess.run(["python3", host + "/rails/verifier/fingerprint.py",
                      host, "--untracked"],
                     capture_output=True, text=True).stdout.strip()
if unt:
    print("note: the stamped fingerprint covers file(s) git does not track:")
    for ln in unt.splitlines():
        print(f"  {ln}")
    print("review and commit (or remove) them -- this stamp blesses their "
          "current bytes.")
PYEOF
  echo "evidence: rails/evidence/ADVERSARIAL/$RUNID/"
  exit 0
else
  echo
  echo "GOVERNOR NOT PROVEN: $FAILED of $TOTAL cases failed. Registry NOT stamped."
  echo "verify.sh will refuse to certify dispatches until this passes."
  echo "evidence: rails/evidence/ADVERSARIAL/$RUNID/"
  exit 1
fi
