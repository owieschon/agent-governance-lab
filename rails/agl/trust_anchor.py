"""Reviewed roots of trust for the checked-in comparison release.

These constants are intentionally outside the manifest they authenticate. A
release update must change them as a code-reviewed trust decision; generated
artifacts and mutable binding files cannot rewrite them themselves.
"""

TRUSTED_RELEASE_MANIFEST_SHA256 = "5d2153cf635f353e6c79f38a4e54959132a1ca3cc6265d2a1ad4cab61b15d88a"
TRUSTED_RESULT_SHA256 = "e7f6d2a25acf00e4c7707c9fbcbbbf9d9de692f3e79be9157586b2982bf64372"
