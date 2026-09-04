"""Reviewed roots of trust for the checked-in comparison release.

These constants are intentionally outside the manifest they authenticate. A
release update must change them as a code-reviewed trust decision; generated
artifacts and mutable binding files cannot rewrite them themselves.
"""

TRUSTED_RELEASE_MANIFEST_SHA256 = "756c693f9b518f944338006a4b67d6364f454a59d310d47cab88e240a331b605"
TRUSTED_RESULT_SHA256 = "0bca929d3d2560ca9bdeb9e60840b08248d33434514d441899c4cc1032130cd8"
