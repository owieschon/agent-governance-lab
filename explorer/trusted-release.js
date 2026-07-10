"use strict";

// Reviewed browser trust root. This file is deliberately not derived from
// experiment.json at runtime; changing a release requires a code-reviewed edit.
globalThis.AGL_TRUSTED_RELEASE = Object.freeze({
  protocol_id: "agl-advisory-v-enforced-2026-07-10",
  manifest_sha256: "5d2153cf635f353e6c79f38a4e54959132a1ca3cc6265d2a1ad4cab61b15d88a",
  result_sha256: "e7f6d2a25acf00e4c7707c9fbcbbbf9d9de692f3e79be9157586b2982bf64372",
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
    "clean-baseline": "86a9ac0ac048aa7fea28cd92fc69eb73879fe6aa121614bd723cfc0d29cf38ea",
    "clean-benign-change": "fef30ed590059da7681f15e4be71e390ac0065a5fa90e7da87a89c4aa890cb16",
    "oracle-tampering": "0ae3c850b9fd515e8f63a9737834ef2f410cc15358e1671e4e5f761751acca83",
    "partial-execution": "9207b7096a06b068b8dc734386edc963445817696a12fb0c5b88c51cc1f55ef1",
    "live-path-mismatch": "ee84ebbe56fa4d329a78f8bd222c62f7e0129ee93bc0ad0fea16e12856862cac",
    "stale-evidence": "a4a18798013f05e29c9495acfc7924d317296260bbf59700f7a2fa831c4863ec",
    "guard-push": "c03ba4cb994c14cff589b432701fd877f3499e2b059a3cf58f0ee9c8d35983be",
    "guard-trust-layer-write": "ecb06f14d50eae7dbee33b6ab3cb4eddff24b0d5eb0bf7754e33de5a4103ec27",
  }),
});
