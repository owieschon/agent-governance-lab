"use strict";

const state = {
  result: null,
  receipts: {},
  trigger: null,
};

const $ = (id) => document.getElementById(id);

function shortDigest(value, length = 16) {
  return `${value.slice(0, length)}…${value.slice(-6)}`;
}

function metricText(metric) {
  return `${metric.numerator}/${metric.denominator}`;
}

function setSeal(kind, title, detail) {
  const seal = $("dataset-seal");
  seal.classList.remove("verified", "failed");
  seal.classList.add(kind);
  $("seal-title").textContent = title;
  $("seal-detail").textContent = detail;
}

function showRefusal(reasons) {
  $("headline-metrics").hidden = true;
  $("result-refusal").hidden = false;
  $("refusal-reason").textContent = reasons.join(" ");
  document.documentElement.dataset.state = "invalid";
}

function renderMetrics(result) {
  const metrics = result.metrics.by_policy;
  $("l1-contained").textContent = metricText(metrics.L1.containment);
  $("l1-clean").textContent = metricText(metrics.L1.false_blocks);
  $("l3-contained").textContent = metricText(metrics.L3.containment);
  $("l3-clean").textContent = metricText(metrics.L3.false_blocks);
  $("shared-digest").textContent = `${result.cases.length} candidate envelopes · digest bound per row`;
  $("headline-metrics").hidden = false;
  $("result-refusal").hidden = true;
}

function decisionClass(decision) {
  return decision === "BLOCKED" ? "blocked" : "released";
}

function renderCases(cases) {
  const ledger = $("case-ledger");
  ledger.replaceChildren();
  cases.forEach((item) => {
    const li = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "case-row";
    button.dataset.caseId = item.id;
    button.setAttribute("aria-haspopup", "dialog");
    button.setAttribute("aria-label", `${item.title}: inspect bound receipt`);
    button.innerHTML = `
      <span class="case-title"><strong></strong><small></small></span>
      <span class="decision ${decisionClass(item.treatments.L1.decision)}"></span>
      <code class="case-digest"></code>
      <span class="decision ${decisionClass(item.treatments.L3.decision)}"></span>
      <span class="row-arrow" aria-hidden="true">↗</span>`;
    button.querySelector(".case-title strong").textContent = item.title;
    button.querySelector(".case-title small").textContent = `${item.family.replaceAll("_", " ")} · ${item.expected_label}`;
    const decisions = button.querySelectorAll(".decision");
    decisions[0].textContent = `L1 ${item.treatments.L1.decision}`;
    decisions[1].textContent = `L3 ${item.treatments.L3.decision}`;
    button.querySelector(".case-digest").textContent = shortDigest(item.candidate_sha256);
    button.addEventListener("click", () => openCase(item, button));
    li.append(button);
    ledger.append(li);
  });
}

function renderContext(context) {
  const historical = context.historical_study.record;
  $("history-status").textContent = historical.decision.status;
  const reasons = $("history-reasons");
  reasons.replaceChildren();
  historical.invalidity_reasons.forEach((reason) => {
    const li = document.createElement("li");
    li.textContent = reason;
    reasons.append(li);
  });

  const engineering = context.engineering_decision.record;
  const transport = engineering.transport;
  const kappa = engineering.fidelity_gate.clean_safety_boundary;
  const falseOpens = engineering.fidelity_gate.adversarial_false_opens;
  $("transport-count").textContent = `${transport.completed}/${transport.total}`;
  $("kappa-readout").textContent = `${kappa.candidate_kappa} ∉ [${kappa.committed_band.join(", ")}]`;
  $("false-open-readout").textContent = `${falseOpens.candidate} vs ${falseOpens.reference}`;
  $("engineering-pin").textContent = shortDigest(engineering.source.commit, 10);
  $("engineering-digest").textContent = shortDigest(engineering.source.sha256, 10);
}

async function openCase(summary, trigger) {
  state.trigger = trigger;
  const dialog = $("case-dialog");
  $("dialog-title").textContent = summary.title;
  $("dialog-family").textContent = `${summary.family.replaceAll("_", " ")} · ${summary.expected_label}`;
  $("receipt-status").classList.remove("failed");
  $("receipt-status").textContent = "Loading and verifying receipt…";
  $("dialog-json").textContent = "";
  if (typeof dialog.showModal === "function") dialog.showModal();
  else dialog.setAttribute("open", "");

  try {
    const receipt = state.receipts[summary.id];
    if (!receipt) throw new Error("receipt was not part of the verified release");
    const digest = await globalThis.AGLVerification.verifyContentAddress(
      receipt,
      "receipt_sha256",
    );
    if (digest !== globalThis.AGL_TRUSTED_RELEASE.receipts[summary.id]) {
      throw new Error("receipt differs from the build-embedded release");
    }
    $("receipt-status").textContent = `VERIFIED · SHA-256 ${shortDigest(digest, 20)}`;
    $("dialog-candidate").textContent = receipt.candidate.sha256;
    $("dialog-equality").textContent = "L0 = L1 = SHAM = L3. SHAM and L3 also bind the same gate evidence; only authority differs.";
    $("dialog-l1").textContent = `${receipt.treatments.L1.decision} · ${receipt.treatments.L1.reason}`;
    $("dialog-l1-evidence").textContent = `evidence ${shortDigest(receipt.treatments.L1.evidence_sha256)}`;
    $("dialog-l3").textContent = `${receipt.treatments.L3.decision} · ${receipt.treatments.L3.reason}`;
    $("dialog-l3-evidence").textContent = `evidence ${shortDigest(receipt.treatments.L3.evidence_sha256)}`;
    $("dialog-source").textContent = receipt.public_mechanism_source;
    $("dialog-label-basis").textContent = receipt.label_basis;
    $("dialog-json").textContent = JSON.stringify(receipt, null, 2);
  } catch (error) {
    $("receipt-status").classList.add("failed");
    $("receipt-status").textContent = `NOT VERIFIED · ${error.message}`;
  }
}

function closeDialog() {
  const dialog = $("case-dialog");
  if (typeof dialog.close === "function") dialog.close();
  else dialog.removeAttribute("open");
  state.trigger?.focus();
}

async function loadExperiment() {
  try {
    if (!globalThis.AGL_TRUSTED_RELEASE || !globalThis.AGLVerification) {
      throw new Error("build trust or verifier code is unavailable");
    }
    const trust = globalThis.AGL_TRUSTED_RELEASE;
    const verification = globalThis.AGLVerification;
    const response = await fetch("data/experiment.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`dataset request returned ${response.status}`);
    const result = await response.json();
    const receiptEntries = await Promise.all(
      trust.case_ids.map(async (caseId) => {
        const receiptResponse = await fetch(`data/receipts/${caseId}.json`, { cache: "no-store" });
        if (!receiptResponse.ok) throw new Error(`receipt request returned ${receiptResponse.status}`);
        return [caseId, await receiptResponse.json()];
      }),
    );
    const receipts = Object.fromEntries(receiptEntries);
    const verified = await verification.verifyRelease(
      result,
      receipts,
      trust,
    );
    state.result = result;
    state.receipts = receipts;
    renderCases(verified.cases);
    renderContext(result.context);
    $("footer-digest").textContent = shortDigest(verified.resultDigest, 20);
    $("footer-status").textContent = "Browser-verified trusted release";

    renderMetrics({ ...result, metrics: verified.metrics, cases: verified.cases });
    setSeal(
      "verified",
      "Dataset digest verified",
      `Trusted release ${shortDigest(trust.manifest_sha256, 12)} · ${verified.cases.length} semantic receipts recomputed.`,
    );
    document.documentElement.dataset.state = "verified";
  } catch (error) {
    setSeal("failed", "Dataset not verified", "Headline counts remain hidden because browser verification did not complete.");
    showRefusal([error.message]);
    $("case-ledger").innerHTML = '<li class="loading-row">Receipts are unavailable until the dataset verifies.</li>';
    $("footer-status").textContent = "Dataset verification failed";
  }
}

$("dialog-close").addEventListener("click", closeDialog);
$("case-dialog").addEventListener("click", (event) => {
  if (event.target === $("case-dialog")) closeDialog();
});

loadExperiment();
