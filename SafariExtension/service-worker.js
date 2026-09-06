const extensionAPI = globalThis.browser ?? globalThis.chrome;
const RULES_ENDPOINT = "http://127.0.0.1:17321/rules?client=safari";

function safeDomain(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .split("/")[0];
}

async function synchronizeRules() {
  try {
    const response = await fetch(RULES_ENDPOINT, { cache: "no-store" });
    if (!response.ok) return;
    const payload = await response.json();
    const domains = [...new Set((payload.blockedDomains || []).map(safeDomain).filter(Boolean))];
    const existing = await extensionAPI.declarativeNetRequest.getDynamicRules();
    const addRules = domains.map((domain, index) => ({
      id: index + 1,
      priority: 1,
      action: {
        type: "block"
      },
      condition: {
        urlFilter: `||${domain}^`,
        resourceTypes: ["main_frame"]
      }
    }));
    await extensionAPI.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: existing.map(rule => rule.id),
      addRules
    });
    await extensionAPI.storage.local.set({
      lastSyncAt: Date.now(),
      blockedDomains: domains,
      lastSyncError: null
    });
  } catch (error) {
    // Existing rules stay active if the local app is temporarily unavailable.
    await extensionAPI.storage.local.set({
      lastSyncError: String(error?.message || error),
      lastSyncErrorAt: Date.now()
    });
  }
}

extensionAPI.runtime.onInstalled.addListener(() => {
  extensionAPI.alarms.create("hidigFocus-sync", { periodInMinutes: 0.5 });
  synchronizeRules();
});
extensionAPI.runtime.onStartup.addListener(synchronizeRules);
extensionAPI.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === "hidigFocus-sync") synchronizeRules();
});
extensionAPI.runtime.onMessage.addListener((message, _, sendResponse) => {
  if (message?.type !== "sync") return false;
  synchronizeRules().then(() => sendResponse({ ok: true }));
  return true;
});
