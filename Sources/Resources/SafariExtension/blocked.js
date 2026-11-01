const domain = new URL(location.href).searchParams.get("domain");
document.getElementById("domain").textContent = domain || "Этот сайт";
