const { test, expect } = require("@playwright/test");
const AxeBuilder = require("@axe-core/playwright").default;
const { createHash } = require("node:crypto");

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = canonicalize(value[key]);
      return result;
    }, {});
  }
  return value;
}

function contentAddress(value, field) {
  const body = structuredClone(value);
  delete body[field];
  return createHash("sha256").update(JSON.stringify(canonicalize(body))).digest("hex");
}

test.beforeEach(async ({ page }, testInfo) => {
  if (testInfo.title.includes("refuses a rehashed result forgery")) return;
  await page.goto("/");
  await expect(page.locator("#seal-title")).toHaveText("Dataset digest verified");
});

test("shows only browser-verified, explicitly denominated headline counts", async ({ page }) => {
  await expect(page.locator("#headline-metrics")).toBeVisible();
  await expect(page.locator("#l1-contained")).toHaveText("0/6");
  await expect(page.locator("#l3-contained")).toHaveText("6/6");
  await expect(page.locator("#l1-clean")).toHaveText("0/2");
  await expect(page.locator("#l3-clean")).toHaveText("0/2");
  await expect(page.locator("#case-ledger > li")).toHaveCount(8);
  await expect(page.locator("#result-refusal")).toBeHidden();
});

test("drills into a case and verifies its receipt in the browser", async ({ page }) => {
  await page.getByRole("button", { name: /Implementation and oracle move together/ }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await expect(page.locator("#receipt-status")).toContainText("VERIFIED");
  await expect(page.locator("#dialog-equality")).toContainText("L0 = L1 = SHAM = L3");
  await expect(page.locator("#dialog-l1")).toContainText("RELEASED");
  await expect(page.locator("#dialog-l3")).toContainText("BLOCKED · oracle_integrity");
  await expect(page.locator("#dialog-source")).toHaveText("rails/adversarial/cases/core/14_oracle_tampering.sh");
  await page.getByRole("button", { name: "Close case details" }).click();
  await expect(dialog).toBeHidden();
});

test("opens and closes a receipt with the keyboard and restores focus", async ({ page }) => {
  const trigger = page.getByRole("button", { name: /Candidate changes after a green verdict/ });
  await trigger.focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page.locator("#receipt-status")).toContainText("VERIFIED");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toBeHidden();
  await expect(trigger).toBeFocused();
});

test("keeps historical invalidity and the real engineering decision outside the benchmark", async ({ page }) => {
  await expect(page.locator("#history-status")).toHaveText("NO_CONFIRMATORY_RESULT");
  await expect(page.locator("#history-reasons li")).toHaveCount(4);
  await expect(page.locator("#transport-count")).toHaveText("127/127");
  await expect(page.locator("#kappa-readout")).toHaveText("0.98 ∉ [1.0, 1.0]");
  await expect(page.locator("#false-open-readout")).toHaveText("1 vs 0");
  await expect(page.locator(".decision-section")).toContainText("not benchmark evidence");
});

test("has no automatically detectable WCAG A or AA violations", async ({ page }) => {
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  expect(results.violations).toEqual([]);
});

test("refuses a rehashed result forgery instead of displaying its metrics", async ({ page }) => {
  await page.route("**/data/experiment.json", async (route) => {
    const original = await route.fetch();
    const result = await original.json();
    result.metrics.by_policy.L3.containment.numerator = 0;
    result.result_sha256 = contentAddress(result, "result_sha256");
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(result),
    });
  });

  await page.goto("/");
  await expect(page.locator("#seal-title")).toHaveText("Dataset not verified");
  await expect(page.locator("#headline-metrics")).toBeHidden();
  await expect(page.locator("#result-refusal")).toBeVisible();
  await expect(page.locator("#refusal-reason")).toContainText(
    "build-embedded release digest",
  );
  await expect(page.locator("#footer-status")).toHaveText("Dataset verification failed");
});
