# Development and proof

<!-- sourcebound:purpose -->
Use this guide when changing the lab or reproducing its release decision. It groups the supported lint, unit, manifest, smoke, browser, and adversarial lanes so a contributor can choose the proof proportional to the change.
<!-- sourcebound:end purpose -->

## Commands

Runtime comparison code is Python-standard-library, Bash, and Git. Node packages
are test-only and the explorer itself is framework-free.

```bash
# Reviewed lint toolchain and full-repository gate. The entrypoint refuses any
# missing or different Ruff version.
python3 -m pip install --disable-pip-version-check ruff==0.15.18
python3 scripts/check_ruff.py

# Fast contract + static accessibility tests
python3 -m unittest discover -s tests -v

# Immutable source/schema manifest check
python3 scripts/render_trusted_release.py --check

# Deterministic executable smoke; fails at 90 seconds
./bin/agl compare --check

# Desktop/mobile interaction, receipt verification, and WCAG A/AA scan
npm ci
npx playwright install chromium
npm run test:e2e

# Full 50-case proof (extended/nightly CI, not the pull-request inner loop)
RAILS_NO_STAMP=1 bash rails/adversarial/run_eval.sh
```

`.github/workflows/prove.yml` installs Ruff 0.15.18, runs the same full-repository
lint entrypoint, then runs the trusted-manifest gate, smoke, exact-artifact
check, gitleaks, diff whitespace inspection, unit/static tests, and browser
checks on pushes and pull requests. `.github/workflows/extended.yml` rechecks
the trusted comparison release before the complete 50-case nightly or manual
proof. `.github/workflows/pages.yml` refuses source or artifact drift before
assembling and deploying the static artifact.

Apache-2.0 licensed. See [`LICENSE`](../LICENSE).
