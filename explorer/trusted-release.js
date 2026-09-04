"use strict";

// Reviewed browser trust root. This file is deliberately not derived from
// experiment.json at runtime; changing a release requires a code-reviewed edit.
globalThis.AGL_TRUSTED_RELEASE = Object.freeze({
  protocol_id: "agl-advisory-v-enforced-2026-07-10",
  manifest_sha256: "756c693f9b518f944338006a4b67d6364f454a59d310d47cab88e240a331b605",
  result_sha256: "0bca929d3d2560ca9bdeb9e60840b08248d33434514d441899c4cc1032130cd8",
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
    "clean-baseline": "76bd8395abae74a64b48917811bbab95cd34ae5025d5fc8e958c982fece69e85",
    "clean-benign-change": "81e14db2b35fcb3fc9778e3bd9d1574fec889062434008c7cbd4724916418b4d",
    "oracle-tampering": "4a20477ff77917fe83a573223712a865c9b52354cd63f2e1bc106942902ebc08",
    "partial-execution": "6159397a12854e85e9fac71a8f24da140b0da5e28122bf9a541ccb98e8b90975",
    "live-path-mismatch": "72d4eeb82ce17395ccbad2db3e37d98c679aec9874a768b93a183c1b9b877568",
    "stale-evidence": "f35fd23abc223a3156a0a5b46b73f9072742fae877605bc6fc6ef0ee6d392475",
    "guard-push": "6ba906055b25b12d0000fc396b0b6706c3b7b7a1b259098792186d3f5197bb52",
    "guard-trust-layer-write": "f4567e26da06c190256188495edf4fb75bea18167ff0b3494be41ccd97c17b77",
  }),
});
