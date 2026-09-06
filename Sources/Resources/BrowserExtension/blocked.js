const extensionAPI = globalThis.browser ?? globalThis.chrome;
const domain = new URLSearchParams(location.search).get("domain") || "";
const message = document.getElementById("message");
const tasksSection = document.getElementById("tasks");
const taskList = document.getElementById("task-list");

function formatBlockedUntil(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const targetDay = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const dayDifference = Math.round((targetDay - today) / 86400000);
  const time = new Intl.DateTimeFormat("ru-RU", { hour: "2-digit", minute: "2-digit" }).format(date);
  if (dayDifference === 0) return `сегодня до ${time}`;
  if (dayDifference === 1) return `завтра до ${time}`;
  const day = new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "long" }).format(date);
  return `до ${day}, ${time}`;
}

async function renderReason() {
  const stored = await extensionAPI.storage.local.get(["blockRules"]);
  const rule = (stored.blockRules || []).find(item => item.domain === domain);
  if (!rule) {
    message.textContent = "Этот сайт входит в закрытую группу. Доступ появится по правилам расписания или после выполнения назначенных задач.";
    return;
  }
  const group = rule.groupName ? `Группа «${rule.groupName}». ` : "";
  if (rule.reason === "tasks" && rule.remainingTasks.length > 0) {
    message.textContent = `${group}Доступ откроется после выполнения оставшихся задач.`;
    tasksSection.hidden = false;
    taskList.replaceChildren(...rule.remainingTasks.map(title => {
      const item = document.createElement("li");
      item.textContent = title;
      return item;
    }));
    return;
  }
  if (rule.reason === "schedule" && rule.blockedUntil) {
    const until = formatBlockedUntil(rule.blockedUntil);
    if (until) {
      message.textContent = `${group}Заблокировано ${until}.`;
      return;
    }
  }
  message.textContent = "Этот сайт входит в закрытую группу. Доступ появится по правилам расписания или после выполнения назначенных задач.";
}

renderReason();
document.getElementById("check").addEventListener("click", async () => {
  await extensionAPI.runtime.sendMessage({ type: "sync" });
  history.back();
});
