const extensionAPI = globalThis.browser ?? globalThis.chrome;
const RULES_ENDPOINT = "http://127.0.0.1:17321/rules?client=chromium";

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
    const rules = (payload.rules || []).map(rule => ({
      domain: safeDomain(rule.domain),
      groupName: String(rule.groupName || ""),
      reason: String(rule.reason || "permanent"),
      remainingTasks: Array.isArray(rule.remainingTasks) ? rule.remainingTasks.map(String) : [],
      blockedUntil: rule.blockedUntil || null
    })).filter(rule => rule.domain);
    const domains = [...new Set((payload.blockedDomains || rules.map(rule => rule.domain)).map(safeDomain).filter(Boolean))];
    const detailsByDomain = new Map(rules.map(rule => [rule.domain, rule]));
    const existing = await extensionAPI.declarativeNetRequest.getDynamicRules();
    const addRules = domains.map((domain, index) => ({
      id: index + 1,
      priority: 1,
      action: {
        type: "redirect",
        redirect: {
          url: extensionAPI.runtime.getURL(`/blocked.html?domain=${encodeURIComponent(domain)}`)
        }
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
      blockRules: domains.map(domain => detailsByDomain.get(domain) || {
        domain,
        groupName: "",
        reason: "permanent",
        remainingTasks: [],
        blockedUntil: null
      })
    });
  } catch (_) {
    // Dynamic rules intentionally remain unchanged when the local app is unavailable.
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
