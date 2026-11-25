const $ = (selector) => document.querySelector(selector);
const state = { csrf: "", role: "", username: "", inmatePage: 1, visitsPage: 1 };

const roleLabels = {
  admin: "Administrator",
  warden: "Facility warden",
  auditor: "Auditor",
  frontdesk: "Front desk",
};

function showMessage(element, message, success = false) {
  element.textContent = message;
  element.classList.toggle("success-message", success);
}

async function api(url, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (options.body) headers["Content-Type"] = "application/json";
  if (state.csrf) headers["X-CSRF-Token"] = state.csrf;
  const response = await fetch(url, { ...options, headers, credentials: "same-origin" });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
  return payload;
}

function showAlert(message) {
  const alert = $("#global-alert");
  alert.textContent = message;
  alert.classList.remove("hidden");
}

function hideAlert() {
  $("#global-alert").classList.add("hidden");
}

function setTableRows(target, rows, columns, emptyMessage = "No records found.") {
  const body = $(target);
  body.replaceChildren();
  if (!rows.length) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = columns.length;
    cell.className = "empty-state";
    cell.textContent = emptyMessage;
    row.append(cell);
    body.append(row);
    return;
  }
  for (const record of rows) {
    const row = document.createElement("tr");
    for (const column of columns) {
      const cell = document.createElement("td");
      const value = record[column.key];
      if (column.kind === "badge") {
        const badge = document.createElement("span");
        const normalized = String(value || "").toLowerCase();
        badge.className = `badge badge-${normalized}`;
        badge.textContent = value || "—";
        cell.append(badge);
      } else {
        cell.textContent = value == null ? "—" : String(value);
        if (column.kind === "name") cell.className = "name-cell";
      }
      row.append(cell);
    }
    body.append(row);
  }
}

async function loadHealth() {
  const note = $("#cloud-note");
  try {
    const result = await api("/api/health");
    note.textContent = result.configured
      ? "Wallet found. Sign in with an assigned database role."
      : "Cloud wallet/config not found. Configure .env and the wallet folder first.";
    note.classList.toggle("ready", result.configured);
  } catch {
    note.textContent = "Could not check cloud configuration.";
  }
}

function setRoleAccess(role) {
  const showRoster = role !== "frontdesk";
  const showVisitors = ["frontdesk", "admin", "auditor"].includes(role);
  const showBooking = ["frontdesk", "admin"].includes(role);
  $("#nav-inmates").classList.toggle("hidden", !showRoster);
  $("#nav-visitors").classList.toggle("hidden", !showVisitors);
  $("#nav-booking").classList.toggle("hidden", !showBooking);
  $("#stat-inmates-card").classList.toggle("hidden", !showRoster);
  $("#stat-blocks-card").classList.toggle("hidden", !showRoster);
}

function openView(name) {
  hideAlert();
  document.querySelectorAll(".view-panel").forEach((panel) => panel.classList.add("hidden"));
  $(`#view-${name}`).classList.remove("hidden");
  document.querySelectorAll(".nav-item").forEach((item) => item.classList.toggle("active", item.dataset.view === name));
  const title = name.replace("-", " ");
  $("#breadcrumb-current").textContent = title.toUpperCase();
  $("#page-title").firstChild.textContent = name === "overview" ? "Good day. " : `${title.charAt(0).toUpperCase()}${title.slice(1)} `;
  if (name === "overview") $("#page-title").firstChild.textContent = "Good day. ";
  const loader = {
    inmates: () => loadInmates(state.inmatePage),
    visits: () => loadVisits(state.visitsPage),
    visitors: loadVisitors,
  }[name];
  if (loader) loader().catch((error) => showAlert(error.message));
}

async function loadDashboard() {
  const result = await api("/api/dashboard");
  $("#stat-today").textContent = result.visits_today;
  $("#stat-scheduled").textContent = result.scheduled_visits;
  if (result.active_inmates !== undefined) $("#stat-inmates").textContent = result.active_inmates;
  if (result.block_count !== undefined) $("#stat-blocks").textContent = result.block_count;
  setTableRows("#today-table", result.today_visits, [
    { key: "slot" },
    { key: "inmate_name", kind: "name" },
    { key: "visitor_name" },
    { key: "block_name" },
    { key: "status", kind: "badge" },
  ]);
}

async function loadInmates(page) {
  const result = await api(`/api/inmates?page=${page}`);
  state.inmatePage = page;
  $("#inmate-count").textContent = `${result.total} active`;
  $("#inmates-page").textContent = `Page ${result.page} of ${Math.max(1, Math.ceil(result.total / result.page_size))}`;
  $("#inmates-prev").disabled = page <= 1;
  $("#inmates-next").disabled = page * result.page_size >= result.total;
  setTableRows("#inmates-table", result.rows, [
    { key: "inmate_no", kind: "name" },
    { key: "full_name" },
    { key: "block_name" },
    { key: "risk_level", kind: "badge" },
    { key: "sentence_end" },
  ]);
}

async function loadVisits(page) {
  const result = await api(`/api/visits?page=${page}`);
  state.visitsPage = page;
  $("#visits-count").textContent = `${result.total} bookings`;
  $("#visits-page").textContent = `Page ${result.page} of ${Math.max(1, Math.ceil(result.total / result.page_size))}`;
  $("#visits-prev").disabled = page <= 1;
  $("#visits-next").disabled = page * result.page_size >= result.total;
  setTableRows("#visits-table", result.rows, [
    { key: "visit_date" },
    { key: "slot" },
    { key: "inmate_name", kind: "name" },
    { key: "block_name" },
    { key: "status", kind: "badge" },
  ]);
}

async function loadVisitors() {
  const result = await api("/api/visitors");
  setTableRows("#visitors-table", result.rows, [
    { key: "full_name", kind: "name" },
    { key: "id_proof_type" },
    { key: "id_proof_masked" },
    { key: "approval_status", kind: "badge" },
  ]);
}

async function enterApp(identity) {
  state.csrf = identity.csrf;
  state.role = identity.role;
  state.username = identity.username;
  $("#login-shell").classList.add("hidden");
  $("#app-shell").classList.remove("hidden");
  $("#user-name").textContent = roleLabels[state.role] || state.role;
  $("#user-role").textContent = state.username;
  $("#connection-user").textContent = state.username;
  $("#user-avatar").textContent = (roleLabels[state.role] || "U").split(" ").map((word) => word[0]).join("").slice(0, 2).toUpperCase();
  $("#heading-name").textContent = roleLabels[state.role] || "Team";
  $("#today-label").textContent = new Intl.DateTimeFormat(undefined, { weekday: "short", month: "short", day: "numeric", year: "numeric" }).format(new Date());
  $("#booking-form").elements.visit_date.min = new Date().toISOString().slice(0, 10);
  setRoleAccess(state.role);
  try {
    await loadDashboard();
  } catch (error) {
    showAlert(error.message);
  }
}

$("#login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = $("#login-message");
  showMessage(message, "Connecting to Oracle…");
  const submit = event.currentTarget.querySelector("button[type=submit]");
  submit.disabled = true;
  try {
    const identity = await api("/api/login", {
      method: "POST",
      body: JSON.stringify({ username: $("#username").value, password: $("#password").value }),
    });
    $("#password").value = "";
    await enterApp(identity);
  } catch (error) {
    showMessage(message, error.message);
  } finally {
    submit.disabled = false;
  }
});

document.querySelectorAll(".nav-item").forEach((item) => item.addEventListener("click", () => openView(item.dataset.view)));
document.querySelectorAll("[data-open-view]").forEach((item) => item.addEventListener("click", () => openView(item.dataset.openView)));
$("#refresh-button").addEventListener("click", async () => {
  try {
    if (!$(`#view-overview`).classList.contains("hidden")) await loadDashboard();
    else openView(document.querySelector(".nav-item.active")?.dataset.view || "overview");
  } catch (error) {
    showAlert(error.message);
  }
});
$("#inmates-prev").addEventListener("click", () => loadInmates(Math.max(1, state.inmatePage - 1)).catch((error) => showAlert(error.message)));
$("#inmates-next").addEventListener("click", () => loadInmates(state.inmatePage + 1).catch((error) => showAlert(error.message)));
$("#visits-prev").addEventListener("click", () => loadVisits(Math.max(1, state.visitsPage - 1)).catch((error) => showAlert(error.message)));
$("#visits-next").addEventListener("click", () => loadVisits(state.visitsPage + 1).catch((error) => showAlert(error.message)));

$("#booking-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const values = Object.fromEntries(new FormData(form).entries());
  const message = $("#booking-message");
  showMessage(message, "Checking booking rules…");
  try {
    const result = await api("/api/bookings", { method: "POST", body: JSON.stringify(values) });
    const success = result.status === "BOOKED";
    showMessage(message, `${result.status}: ${result.message}`, success);
    if (success) await loadDashboard();
  } catch (error) {
    showMessage(message, error.message);
  }
});

$("#logout-button").addEventListener("click", async () => {
  try {
    await api("/api/logout", { method: "POST", body: "{}" });
  } finally {
    window.location.reload();
  }
});

loadHealth();
