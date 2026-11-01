const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const workerSource = fs.readFileSync(path.join(root, "SafariExtension/service-worker.js"), "utf8");
const chromeSource = fs.readFileSync(path.join(root, "BrowserExtension/service-worker.js"), "utf8");
const activeDomains = ["t.co", "twitch.tv", "twitter.com", "vk.com", "vk.ru", "vkvideo.ru", "x.com", "youtu.be", "youtube-nocookie.com", "youtube.com"];
const plain = value => JSON.parse(JSON.stringify(value));
const response = payload => ({ ok: true, status: 200, json: async () => payload });
const domainOrigins = domain => [`http://*.${domain}/*`, `https://*.${domain}/*`];
const settle = () => new Promise(resolve => setImmediate(resolve));

function event() {
  const listeners = [];
  return { addListener: callback => listeners.push(callback), listeners, emit: (...args) => Promise.all(listeners.map(fn => fn(...args))) };
}

function harness(options = {}) {
  const shared = options.shared || { rules: [], storage: {} };
  const state = { shared, fetches: [], updates: [], alarms: new Map(), alarmCreates: 0,
    responder: options.responder || (() => response({ blockedDomains: activeDomains })), rejectUpdate: false,
    grantedOrigins: new Set(options.grantedOrigins || []), rejectPermissionCheck: false };
  const api = {
    declarativeNetRequest: {
      getDynamicRules: async () => plain(shared.rules),
      updateDynamicRules: async update => {
        state.updates.push(plain(update));
        if (state.rejectUpdate) throw new Error("DNR rejected transaction");
        for (const rule of update.addRules) {
          if (!options.source && rule.action?.redirect?.url && !/^https?:\/\//.test(rule.action.redirect.url)) {
            throw new Error("redirect specified a non-HTTP url");
          }
        }
        shared.rules = plain([...shared.rules.filter(rule => !update.removeRuleIds.includes(rule.id)), ...update.addRules]);
      }
    },
    storage: { local: { set: async values => Object.assign(shared.storage, plain(values)), get: async () => plain(shared.storage) } },
    alarms: {
      get: async name => state.alarms.get(name),
      create: async (name, value) => { state.alarmCreates++; state.alarms.set(name, plain(value)); },
      onAlarm: event()
    },
    runtime: { onInstalled: event(), onStartup: event(), onMessage: event(), getURL: value => `${options.source ? "chrome" : "safari"}-extension://test${value}` },
    permissions: {
      onAdded: event(), onRemoved: event(),
      contains: async ({ origins }) => {
        if (state.rejectPermissionCheck) throw new Error("Permission state unavailable");
        return origins.every(origin => state.grantedOrigins.has(origin));
      }
    }
  };
  const context = vm.createContext({ browser: api, URL, AbortController, Date, console,
    setTimeout: options.setTimeout || setTimeout,
    clearTimeout: options.clearTimeout || clearTimeout,
    fetch: async (url, init) => {
      state.fetches.push({ url, init });
      return state.responder(url, init);
    }
  });
  vm.runInContext(options.source || workerSource, context);
  const sync = () => vm.runInContext("synchronizeRules()", context);
  return { state, api, shared, context, sync,
    ready: () => vm.runInContext(options.source ? "synchronizeRules()" : "initialSynchronization", context),
    message: message => new Promise(resolve => {
      if (!api.runtime.onMessage.listeners[0](message, {}, resolve)) resolve(undefined);
    })
  };
}

test("Safari matches the current ten Chrome domain conditions and blocks only top-level navigation", async () => {
  const safari = harness();
  const chrome = harness({ source: chromeSource });
  await Promise.all([safari.ready(), chrome.ready()]);
  assert.deepEqual(safari.shared.rules.map(rule => rule.condition), chrome.shared.rules.map(rule => rule.condition));
  assert.equal(safari.shared.rules.length, 10);
  assert.ok(safari.shared.rules.every(rule => rule.action.type === "block" && rule.condition.resourceTypes.join() === "main_frame"));
  assert.ok(safari.state.fetches.every(call => call.url === "http://127.0.0.1:17321/rules?client=safari"));
});

test("same domains from task, schedule and permanent rules produce the same blocking conditions", async () => {
  const h = harness({ responder: () => response({ rules: [
    { domain: "youtube.com", reason: "tasks", remainingTasks: ["Task"] },
    { domain: "vk.com", reason: "schedule", blockedUntil: "2026-10-15T20:00:00Z" },
    { domain: "twitch.tv", reason: "permanent" }
  ] }) });
  await h.ready();
  assert.deepEqual(h.shared.storage.blockedDomains, ["twitch.tv", "vk.com", "youtube.com"]);
});

test("normalization deduplicates URLs and supports international domains", async () => {
  const h = harness({ responder: () => response({ blockedDomains: [" HTTPS://WWW.YouTube.com/watch ", "youtube.com", "пример.рф"] }) });
  await h.ready();
  assert.deepEqual(h.shared.storage.blockedDomains, ["xn--e1afmkfd.xn--p1ai", "youtube.com"]);
});

test("explicit empty current list removes expired/completed blocking rules in one transaction", async () => {
  const h = harness();
  await h.ready();
  h.state.responder = () => response({ blockedDomains: [], rules: [{ domain: "obsolete.example" }] });
  assert.equal((await h.sync()).ok, true);
  assert.deepEqual(h.shared.rules, []);
  assert.equal(h.state.updates.at(-1).removeRuleIds.length, 10);
  assert.deepEqual(h.state.updates.at(-1).addRules, []);
});

test("malformed responses never silently erase or partially replace the last working rules", async () => {
  const h = harness();
  await h.ready();
  const original = plain(h.shared.rules);
  for (const payload of [{}, null, [], { blockedDomains: null }, { blockedDomains: "youtube.com" },
    { blockedDomains: ["vk.com", ""] }, { blockedDomains: ["youtube.com^bad"] }, { rules: [{}] }]) {
    h.state.responder = () => response(payload);
    assert.equal((await h.sync()).ok, false);
    assert.deepEqual(h.shared.rules, original);
  }
});

test("network, HTTP and JSON errors retain persisted rules and report failure to the popup", async () => {
  const h = harness();
  await h.ready();
  const original = plain(h.shared.rules);
  for (const responder of [
    () => { throw new Error("Local app unavailable"); },
    () => ({ ok: false, status: 503 }),
    () => ({ ok: true, json: async () => { throw new Error("Invalid JSON"); } })
  ]) {
    h.state.responder = responder;
    assert.equal((await h.message({ type: "sync" })).ok, false);
    assert.ok(h.shared.storage.lastSyncError);
    assert.deepEqual(h.shared.rules, original);
  }
});

test("rejected DNR transaction retains existing rules and successful sync clears the error", async () => {
  const h = harness();
  await h.ready();
  const original = plain(h.shared.rules);
  h.state.responder = () => response({ blockedDomains: ["example.com"] });
  h.state.rejectUpdate = true;
  assert.equal((await h.sync()).ok, false);
  assert.deepEqual(h.shared.rules, original);
  h.state.rejectUpdate = false;
  assert.deepEqual(plain(await h.sync()), { ok: true, ruleCount: 1 });
  assert.equal(h.shared.storage.lastSyncError, null);
  assert.equal(h.shared.storage.lastSyncErrorAt, null);
});

test("unchanged rule sets do not repeatedly rewrite DNR", async () => {
  const h = harness();
  await h.ready();
  const count = h.state.updates.length;
  await h.sync();
  await h.sync();
  assert.equal(h.state.updates.length, count);
});

test("manual refresh and startup reapply unchanged rules while the periodic alarm does not", async () => {
  const h = harness();
  await h.ready();
  let count = h.state.updates.length;
  await h.api.alarms.onAlarm.emit({ name: "hidigFocus-sync" });
  assert.equal(h.state.updates.length, count);
  assert.equal((await h.message({ type: "sync" })).ok, true);
  assert.equal(h.state.updates.length, ++count);
  await h.api.runtime.onStartup.emit();
  assert.equal(h.state.updates.length, ++count);
});

test("manual repair queued during a periodic request runs an atomic forced transaction afterward", async () => {
  const h = harness();
  await h.ready();
  let release;
  h.state.responder = () => new Promise(resolve => { release = resolve; });
  const periodic = h.sync();
  const manual = h.message({ type: "sync" });
  const before = h.state.updates.length;
  await settle();
  h.state.responder = () => response({ blockedDomains: activeDomains });
  release(response({ blockedDomains: activeDomains }));
  await periodic;
  await manual;
  assert.equal(h.state.updates.length, before + 1);
  assert.equal(h.state.updates.at(-1).removeRuleIds.length, 10);
  assert.equal(h.state.updates.at(-1).addRules.length, 10);
});

test("concurrent triggers share one request so stale responses cannot win", async () => {
  const h = harness();
  await h.ready();
  let release;
  h.state.responder = () => new Promise(resolve => { release = resolve; });
  const before = h.state.fetches.length;
  const first = h.sync();
  const second = h.sync();
  assert.equal(first, second);
  await settle();
  assert.equal(h.state.fetches.length, before + 1);
  release(response({ blockedDomains: ["example.com"] }));
  assert.equal((await first).ok, true);
});

test("a hung fetch times out, retains rules, and allows a later sync", async () => {
  const shared = { rules: [{ id: 50, action: { type: "block" }, condition: { urlFilter: "||youtube.com^" } }], storage: {} };
  let timeout;
  const h = harness({ shared, setTimeout: (callback, ms) => { assert.equal(ms, 5000); timeout = callback; return 1; }, clearTimeout() {},
    responder: (_, init) => new Promise((resolve, reject) => init.signal.addEventListener("abort", () => reject(new Error("Request timed out")))) });
  const waiting = h.ready();
  await new Promise(resolve => setImmediate(resolve));
  timeout();
  assert.equal((await waiting).ok, false);
  assert.equal(shared.rules[0].id, 50);
  h.state.responder = () => response({ blockedDomains: ["vk.com"] });
  assert.equal((await h.sync()).ok, true);
});

test("fresh workers and browser startup recreate lost alarms without clearing persisted rules", async () => {
  const first = harness();
  await first.ready();
  const restart = harness({ shared: first.shared, responder: () => { throw new Error("offline"); } });
  await restart.ready();
  assert.equal(restart.shared.rules.length, 10);
  assert.equal(restart.state.alarms.get("hidigFocus-sync").periodInMinutes, 0.5);
  restart.state.alarms.clear();
  await restart.api.runtime.onStartup.emit();
  assert.ok(restart.state.alarms.has("hidigFocus-sync"));
  const creations = restart.state.alarmCreates;
  await restart.api.runtime.onStartup.emit();
  assert.equal(restart.state.alarmCreates, creations);
});

test("granting local-server permission and the periodic alarm retry synchronization", async () => {
  const h = harness({ responder: () => { throw new Error("permission denied"); } });
  await h.ready();
  h.state.responder = () => response({ blockedDomains: ["youtube.com"] });
  await h.api.permissions.onAdded.emit({ origins: ["http://127.0.0.1/*"] });
  assert.equal(h.shared.rules.length, 1);
  h.state.responder = () => response({ blockedDomains: [] });
  await h.api.alarms.onAlarm.emit({ name: "hidigFocus-sync" });
  assert.equal(h.shared.rules.length, 0);
});

test("Safari manifest requests only the valid local host pattern and real popup diagnostics", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "SafariExtension/manifest.json")));
  assert.deepEqual(manifest.host_permissions, ["http://127.0.0.1/*"]);
  assert.equal(manifest.action.default_popup, "popup.html");
  assert.ok(manifest.permissions.includes("declarativeNetRequest"));
  assert.ok(manifest.permissions.includes("declarativeNetRequestWithHostAccess"));
  assert.deepEqual(manifest.optional_host_permissions, ["http://*/*", "https://*/*"]);
  assert.deepEqual(manifest.web_accessible_resources[0].resources, ["blocked.html", "blocked.css", "blocked.js", "icons/icon128.png"]);
  assert.equal(manifest.content_scripts, undefined);
  assert.ok(!manifest.permissions.includes("tabs"));
  const popup = fs.readFileSync(path.join(root, "SafariExtension/popup.js"), "utf8");
  assert.match(popup, /declarativeNetRequest\.getDynamicRules\(\)/);
  assert.match(popup, /origins: \["http:\/\/127\.0\.0\.1\/\*"\]/);
});

test("only domains with granted HTTP and HTTPS access redirect to the custom extension page", async () => {
  const h = harness({ grantedOrigins: domainOrigins("x.com") });
  await h.ready();
  const redirects = h.shared.rules.filter(rule => rule.action.type === "redirect");
  assert.equal(redirects.length, 1);
  assert.equal(redirects[0].condition.urlFilter, "||x.com^");
  assert.deepEqual(redirects[0].action.redirect, { extensionPath: "/blocked.html" });
  assert.equal(h.shared.rules.filter(rule => rule.action.type === "block").length, 9);
  h.state.grantedOrigins.add("https://*.twitch.tv/*");
  await h.sync();
  assert.equal(h.shared.rules.find(rule => rule.condition.urlFilter === "||twitch.tv^").action.type, "block");
});

test("Safari rejects non-HTTP redirect URLs atomically and the extension uses a plain resource path", async () => {
  const h = harness({ grantedOrigins: domainOrigins("x.com") });
  await h.ready();
  const original = plain(h.shared.rules);
  await assert.rejects(h.api.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: original.map(rule => rule.id),
    addRules: [{ ...original[0], action: { type: "redirect", redirect: { url: "safari-extension://test/blocked.html" } } }]
  }), /non-HTTP/);
  assert.deepEqual(h.shared.rules, original);
  for (const rule of original.filter(rule => rule.action.type === "redirect")) {
    assert.equal(rule.action.redirect.extensionPath, "/blocked.html");
    assert.equal(rule.action.redirect.url, undefined);
    assert.doesNotMatch(rule.action.redirect.extensionPath, /[?#]/);
  }
});

test("granting domain permission upgrades that domain without changing the domain set", async () => {
  const h = harness();
  await h.ready();
  for (const origin of domainOrigins("youtube.com")) h.state.grantedOrigins.add(origin);
  await h.api.permissions.onAdded.emit({ origins: domainOrigins("youtube.com") });
  assert.equal(h.shared.rules.find(rule => rule.condition.urlFilter === "||youtube.com^").action.type, "redirect");
  assert.deepEqual(h.shared.storage.blockedDomains, activeDomains);
});

test("revoking domain permissions restores a block even when the local app is offline", async () => {
  const h = harness({ grantedOrigins: activeDomains.flatMap(domainOrigins) });
  await h.ready();
  assert.equal(h.shared.rules.filter(rule => rule.action.type === "redirect").length, 10);
  for (const origin of domainOrigins("x.com")) h.state.grantedOrigins.delete(origin);
  h.state.responder = () => { throw new Error("Local app unavailable"); };
  await h.api.permissions.onRemoved.emit({ origins: domainOrigins("x.com") });
  assert.equal(h.shared.rules.find(rule => rule.condition.urlFilter === "||x.com^").action.type, "block");
  assert.equal(h.shared.rules.filter(rule => rule.action.type === "redirect").length, 9);
  assert.deepEqual(h.shared.storage.blockedDomains, activeDomains);
  assert.match(h.shared.storage.lastSyncError, /unavailable/);
});

test("permission removal repairs existing rules before a stalled fetch and stale data cannot restore redirect", async () => {
  const h = harness({ grantedOrigins: domainOrigins("x.com") });
  await h.ready();
  let release;
  h.state.responder = () => new Promise(resolve => { release = resolve; });
  const fetching = h.sync();
  await settle();
  h.state.grantedOrigins.clear();
  const revoked = h.api.permissions.onRemoved.emit({ origins: domainOrigins("x.com") });
  await settle();
  assert.equal(h.shared.rules.find(rule => rule.condition.urlFilter === "||x.com^").action.type, "block");
  h.state.responder = () => response({ blockedDomains: activeDomains });
  release(response({ blockedDomains: activeDomains }));
  await Promise.all([fetching, revoked]);
  assert.ok(h.shared.rules.every(rule => rule.action.type === "block"));
});

test("a fresh offline worker downgrades persisted redirects when permission is absent or unverifiable", async () => {
  const first = harness({ grantedOrigins: activeDomains.flatMap(domainOrigins) });
  await first.ready();
  const restart = harness({ shared: first.shared, responder: () => { throw new Error("offline"); } });
  restart.state.rejectPermissionCheck = true;
  await restart.ready();
  assert.equal(restart.shared.rules.length, 10);
  assert.ok(restart.shared.rules.every(rule => rule.action.type === "block"));
});

test("popup requests only the displayed missing domains directly from the click and reports actual action counts", async () => {
  const h = harness({ grantedOrigins: domainOrigins("x.com") });
  await h.ready();
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { hidden: false, disabled: false, textContent: "", listeners: {}, addEventListener(type, fn) { this.listeners[type] = fn; } });
    return elements.get(id);
  };
  const requests = [];
  h.api.permissions.request = args => { requests.push(plain(args)); return Promise.resolve(false); };
  h.api.runtime.sendMessage = h.message;
  const context = vm.createContext({ browser: h.api, document: { getElementById: element }, Date, URL });
  vm.runInContext(fs.readFileSync(path.join(root, "SafariExtension/popup.js"), "utf8"), context);
  await settle();
  assert.match(element("mode").textContent, /hidigFocus: 1/);
  assert.match(element("mode").textContent, /Safari: 9/);
  assert.ok(!element("missing-domains").textContent.split(", ").includes("x.com"));
  const clicked = element("redirect").listeners.click();
  assert.equal(requests.length, 1, "permissions.request must run synchronously during the user gesture");
  assert.deepEqual(requests[0].origins, activeDomains.filter(domain => domain !== "x.com").flatMap(domainOrigins));
  assert.ok(requests[0].origins.every(origin => !["<all_urls>", "http://*/*", "https://*/*"].includes(origin)));
  await clicked;
});

test("the custom blocked page displays the domain as text and has no bypass or navigation control", () => {
  const html = fs.readFileSync(path.join(root, "SafariExtension/blocked.html"), "utf8");
  const script = fs.readFileSync(path.join(root, "SafariExtension/blocked.js"), "utf8");
  assert.match(html, /<h1>Сайт заблокирован<\/h1>/);
  assert.doesNotMatch(html, /<(button|a|form)\b/i);
  assert.doesNotMatch(script, /history\.|location\s*=|location\.(href|assign|replace)\s*[=(]/);
  const dangerous = '<img src=x onerror="location.reload()">';
  const domainElement = { textContent: "" };
  vm.runInNewContext(script, { URL, location: { href: `safari-extension://test/blocked.html?domain=${encodeURIComponent(dangerous)}` }, document: { getElementById: () => domainElement } });
  assert.equal(domainElement.textContent, dangerous);
});

test("bundled Safari resources match the standalone source exactly", () => {
  for (const name of fs.readdirSync(path.join(root, "SafariExtension"))) {
    const source = path.join(root, "SafariExtension", name);
    if (fs.statSync(source).isFile()) {
      assert.deepEqual(fs.readFileSync(path.join(root, "Sources/Resources/SafariExtension", name)), fs.readFileSync(source), name);
    }
  }
});
