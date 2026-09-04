"""Reviewed roots of trust for the checked-in comparison release.

These constants are intentionally outside the manifest they authenticate. A
release update must change them as a code-reviewed trust decision; generated
artifacts and mutable binding files cannot rewrite them themselves.
"""

TRUSTED_RELEASE_MANIFEST_SHA256 = "c9d671ca047140ddd3ea10e341648f97eeae376b2c9b7735e1a102028222ff85"
TRUSTED_RESULT_SHA256 = "510312ecc75f41d88416640def5c2b9641772a880e739d57c562854b33432ea4"
