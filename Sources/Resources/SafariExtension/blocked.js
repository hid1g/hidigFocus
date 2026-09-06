document.getElementById("domain").textContent = "Этот сайт";
document.getElementById("check").addEventListener("click", async () => {
  const extensionAPI = globalThis.browser ?? globalThis.chrome;
  await extensionAPI.runtime.sendMessage({ type: "sync" });
  history.back();
});
