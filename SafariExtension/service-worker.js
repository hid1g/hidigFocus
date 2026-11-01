const extensionAPI = globalThis.browser ?? globalThis.chrome;
const RULES_ENDPOINT = "http://127.0.0.1:17321/rules?client=safari";
const SYNC_ALARM = "hidigFocus-sync";
const FETCH_TIMEOUT_MS = 5000;
let pendingSync;
let queuedForcedSync;
let pendingRuleUpdate = Promise.resolve();

function safeDomain(value) {
  if (typeof value !== "string") throw new Error("Некорректный домен в ответе hidigFocus");
  const domain = value
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .split("/")[0];
  if (!domain || /[\s|^*?#:@\\]/u.test(domain)) {
    throw new Error("Некорректный домен в ответе hidigFocus");
  }
  // URL converts international domain names to the ASCII format required by DNR.
  return new URL(`https://${domain}`).hostname;
}

function domainsFromPayload(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("Некорректный ответ hidigFocus");
  }
  let domains;
  if (Object.hasOwn(payload, "blockedDomains")) {
    domains = payload.blockedDomains;
  } else if (Array.isArray(payload.rules)) {
    domains = payload.rules.map(rule => rule?.domain);
  }
  // Only an explicit empty array releases all sites. A malformed response must
  // never silently erase the last working rules.
  if (!Array.isArray(domains)) throw new Error("В ответе hidigFocus нет списка правил");
  return [...new Set(domains.map(safeDomain))].sort();
}

function originsForDomain(domain) {
  return [`http://*.${domain}/*`, `https://*.${domain}/*`];
}

async function canRedirectDomain(domain) {
  try {
    return await extensionAPI.permissions.contains({ origins: originsForDomain(domain) });
  } catch (_) {
    // Missing or unverifiable permission must preserve the basic block.
    return false;
  }
}

async function makeRules(domains) {
  return Promise.all(domains.map(async (domain, index) => ({
    id: index + 1,
    priority: 1,
    action: await canRedirectDomain(domain) ? {
      type: "redirect",
      // Safari rejects non-HTTP redirect.url, and extensionPath is a path
      // (query delimiters are escaped by WebKit's URL::setPath).
      redirect: { extensionPath: "/blocked.html" }
    } : { type: "block" },
    condition: {
      urlFilter: `||${domain}^`,
      resourceTypes: ["main_frame"]
    }
  })));
}

function sameRules(existing, desired) {
  return existing.length === desired.length && desired.every(rule => {
    const current = existing.find(item => item.id === rule.id);
    return current?.priority === rule.priority && current.action?.type === rule.action.type &&
      (rule.action.type !== "redirect" || current.action.redirect?.extensionPath === rule.action.redirect.extensionPath) &&
      current.condition?.urlFilter === rule.condition.urlFilter &&
      current.condition?.resourceTypes?.length === 1 &&
      current.condition.resourceTypes[0] === "main_frame" &&
      Object.keys(current.condition).length === 2;
  });
}

function updateRulesSerially(operation) {
  const update = pendingRuleUpdate.then(operation, operation);
  pendingRuleUpdate = update.catch(() => {});
  return update;
}

function restoreBlocksWithoutPermission() {
  return updateRulesSerially(async () => {
    const existing = await extensionAPI.declarativeNetRequest.getDynamicRules();
    const replacements = [];
    for (const rule of existing) {
      if (rule.action?.type !== "redirect") continue;
      const domain = /^\|\|([^|^]+)\^$/.exec(rule.condition?.urlFilter || "")?.[1];
      if (!domain || !await canRedirectDomain(domain)) {
        replacements.push({ ...rule, action: { type: "block" } });
      }
    }
    if (replacements.length) {
      await extensionAPI.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: replacements.map(rule => rule.id),
        addRules: replacements
      });
    }
  });
}

async function recordFailure(error) {
  const message = String(error?.message || error);
  try {
    await extensionAPI.storage.local.set({
      lastSyncError: message,
      lastSyncErrorAt: Date.now()
    });
  } catch (_) {
    // A storage failure must not remove the browser's persisted dynamic rules.
  }
  return { ok: false, error: message };
}

async function performSynchronization(force) {
  const controller = new AbortController();
  let timeout;
  try {
    // Revoked redirect permissions must fall back to block even when the local
    // app is offline. Do this before waiting for any network response.
    await restoreBlocksWithoutPermission();
    timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    const response = await fetch(RULES_ENDPOINT, { cache: "no-store", signal: controller.signal });
    if (!response.ok) throw new Error(`hidigFocus: HTTP ${response.status}`);
    const payload = await response.json();
    const domains = domainsFromPayload(payload);
    const addRules = await updateRulesSerially(async () => {
      const existing = await extensionAPI.declarativeNetRequest.getDynamicRules();
      const desired = await makeRules(domains);
      if (force || !sameRules(existing, desired)) {
        // Removal and addition belong in one atomic call, including intentional
        // empty lists when the current schedule/tasks release every site.
        await extensionAPI.declarativeNetRequest.updateDynamicRules({
          removeRuleIds: existing.map(rule => rule.id),
          addRules: desired
        });
      }
      return desired;
    });
    await extensionAPI.storage.local.set({
      lastSyncAt: Date.now(),
      blockedDomains: domains,
      lastSyncError: null,
      lastSyncErrorAt: null
    });
    return { ok: true, ruleCount: addRules.length };
  } catch (error) {
    // Existing rules stay active if the local app is temporarily unavailable.
    return recordFailure(error);
  } finally {
    clearTimeout(timeout);
  }
}

function synchronizeRules({ force = false } = {}) {
  // Startup, popup and alarm can arrive together. An older response must not
  // overwrite a newer one, and one stalled request must have a bounded lifetime.
  if (pendingSync && force) {
    // A manual repair arriving during a periodic no-op still has to reach DNR.
    // Coalesce repairs behind the current request without racing transactions.
    if (!queuedForcedSync) {
      queuedForcedSync = pendingSync.then(() => {
        queuedForcedSync = undefined;
        return synchronizeRules({ force: true });
      });
    }
    return queuedForcedSync;
  }
  if (!pendingSync) {
    pendingSync = performSynchronization(force).finally(() => { pendingSync = undefined; });
  }
  return pendingSync;
}

async function initialize() {
  try {
    if (!await extensionAPI.alarms.get(SYNC_ALARM)) {
      await extensionAPI.alarms.create(SYNC_ALARM, { periodInMinutes: 0.5 });
    }
  } catch (error) {
    await recordFailure(error);
  }
  // Reapply on a fresh worker/startup even when Safari's persisted rule records
  // are unchanged. Records alone do not prove that its compiled rules are active.
  return synchronizeRules({ force: true });
}

extensionAPI.runtime.onInstalled.addListener(initialize);
extensionAPI.runtime.onStartup.addListener(initialize);
extensionAPI.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === SYNC_ALARM) return synchronizeRules();
});
extensionAPI.runtime.onMessage.addListener((message, _, sendResponse) => {
  if (message?.type !== "sync") return false;
  synchronizeRules({ force: true }).then(sendResponse);
  return true;
});
extensionAPI.permissions?.onAdded.addListener(initialize);
extensionAPI.permissions?.onRemoved.addListener(async () => {
  try {
    // Do not queue this behind a potentially stalled fetch. The DNR transaction
    // lock still prevents it from racing an in-progress rule replacement.
    await restoreBlocksWithoutPermission();
  } catch (error) {
    return recordFailure(error);
  }
  return synchronizeRules({ force: true });
});

// Safari can load a background worker without another onInstalled event.
// Recreate a missing alarm and fetch the current rules on every fresh worker.
const initialSynchronization = initialize();
