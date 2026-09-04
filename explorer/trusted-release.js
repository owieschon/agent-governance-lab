"use strict";

// Reviewed browser trust root. This file is deliberately not derived from
// experiment.json at runtime; changing a release requires a code-reviewed edit.
globalThis.AGL_TRUSTED_RELEASE = Object.freeze({
  protocol_id: "agl-advisory-v-enforced-2026-07-10",
  manifest_sha256: "c9d671ca047140ddd3ea10e341648f97eeae376b2c9b7735e1a102028222ff85",
  result_sha256: "510312ecc75f41d88416640def5c2b9641772a880e739d57c562854b33432ea4",
  case_ids: Object.freeze([
    "clean-baseline",
    "clean-benign-change",
    "oracle-tampering",
    "partial-execution",
    "live-path-mismatch",
    "stale-evidence",
    "guard-push",
    "guard-trust-layer-write",
  ]),
  receipts: Object.freeze({
    "clean-baseline": "5d1b2e1ae2c6e3080a99a63197d2d691f28ab70e5e9583f120f2012c37cbaee1",
    "clean-benign-change": "8d79e22d3e1a373c04dd63d1f213f4b98888861fe0efb917165bc0d158052604",
    "oracle-tampering": "c9192f0c7afc5f109ebf1c89ead51ac52d7377d49b9018cbc38704b62b50b45d",
    "partial-execution": "777f52118a41ca706ad7b9af7bf31e0a869d45acbeafb9d1d621ea6cec9c7048",
    "live-path-mismatch": "121c6b9691e784d35240a0c2bfdaa8f59e52a2248d2d0f487e7ca5a8c2ffcf43",
    "stale-evidence": "5507049ed38647949f8d7d11ba10ee42ae153c61c6983d1b54e53e4230fab5f9",
    "guard-push": "f92ee07dde37aa3da6a9df44303ab18f11c7ed48a648e6beb5da51019da8fb42",
    "guard-trust-layer-write": "71b1fca0a134289b6c99c5eb126fda761c5f5b143440fd7f6b1ab24e5fdf3661",
  }),
});
