const extensionAPI = globalThis.browser ?? globalThis.chrome;
const syncButton = document.getElementById("sync");
const connectButton = document.getElementById("connect");
const redirectButton = document.getElementById("redirect");
const localOrigins = { origins: ["http://127.0.0.1/*"] };
let missingDomainOrigins = [];

async function showStatus() {
  const [state, rules, canConnect] = await Promise.all([
    extensionAPI.storage.local.get(["lastSyncAt", "lastSyncError"]),
    extensionAPI.declarativeNetRequest.getDynamicRules(),
    extensionAPI.permissions.contains(localOrigins)
  ]);
  connectButton.hidden = canConnect;
  document.getElementById("status").textContent = `Правил блокировки в Safari: ${rules.length}`;
  const redirectCount = rules.filter(rule => rule.action?.type === "redirect").length;
  const fallbackCount = rules.filter(rule => rule.action?.type === "block").length;
  document.getElementById("mode").textContent = `Страница hidigFocus: ${redirectCount}. Стандартный блок Safari: ${fallbackCount}.`;
  const domains = [...new Set(rules.map(rule => /^\|\|([^|^]+)\^$/.exec(rule.condition?.urlFilter || "")?.[1]).filter(Boolean))].sort();
  const missingDomains = [];
  const origins = [];
  for (const domain of domains) {
    const domainOrigins = [`http://*.${domain}/*`, `https://*.${domain}/*`];
    if (!await extensionAPI.permissions.contains({ origins: domainOrigins })) {
      missingDomains.push(domain);
      origins.push(...domainOrigins);
    }
  }
  // Prepare the exact visible request while reading status. The click handler
  // must call permissions.request immediately to preserve the user gesture.
  missingDomainOrigins = origins;
  redirectButton.hidden = !origins.length;
  document.getElementById("missing-domains").textContent = missingDomains.length
    ? `Разрешение требуется для: ${missingDomains.join(", ")} и их поддоменов.`
    : "";
  document.getElementById("updated").textContent = state.lastSyncAt
    ? `Последнее обновление: ${new Date(state.lastSyncAt).toLocaleString("ru-RU")}`
    : "Успешного обновления ещё не было.";
  const error = document.getElementById("error");
  error.hidden = !state.lastSyncError;
  error.textContent = state.lastSyncError
    ? `Не удалось обновить правила. ${rules.length ? "Сохранены последние правила." : "Правил блокировки пока нет."} ${state.lastSyncError}`
    : "";
}

async function refresh() {
  syncButton.disabled = true;
  redirectButton.disabled = true;
  try {
    await extensionAPI.runtime.sendMessage({ type: "sync" });
    await showStatus();
  } catch (error) {
    const message = document.getElementById("error");
    message.hidden = false;
    message.textContent = `Не удалось проверить расширение: ${error.message || error}`;
  } finally {
    syncButton.disabled = false;
    redirectButton.disabled = false;
  }
}

syncButton.addEventListener("click", refresh);
connectButton.addEventListener("click", async () => {
  try {
    // Request only the local rules server, directly from the user's click.
    await extensionAPI.permissions.request(localOrigins);
    await refresh();
  } catch (error) {
    const message = document.getElementById("error");
    message.hidden = false;
    message.textContent = `Не удалось разрешить связь: ${error.message || error}`;
  }
});
redirectButton.addEventListener("click", async () => {
  if (!missingDomainOrigins.length) return;
  try {
    const permissionRequest = extensionAPI.permissions.request({ origins: [...missingDomainOrigins] });
    redirectButton.disabled = true;
    await permissionRequest;
    await refresh();
  } catch (error) {
    const message = document.getElementById("error");
    message.hidden = false;
    message.textContent = `Не удалось разрешить показ страницы hidigFocus: ${error.message || error}`;
  } finally {
    redirectButton.disabled = false;
  }
});
refresh();
