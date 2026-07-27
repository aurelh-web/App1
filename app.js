const STORAGE_KEY = "zeitbudget-state-v1";

const DEFAULT_APPS = [
  { id: "instagram", icon: "📷", name: "Instagram", dailyFreeMinutes: 30, pricePerMinute: 0.10 },
  { id: "tiktok", icon: "🎵", name: "TikTok", dailyFreeMinutes: 20, pricePerMinute: 0.15 },
  { id: "youtube", icon: "▶️", name: "YouTube", dailyFreeMinutes: 40, pricePerMinute: 0.08 },
  { id: "x", icon: "🐦", name: "X / Twitter", dailyFreeMinutes: 20, pricePerMinute: 0.10 },
];

const BUY_PACKAGES = [
  { minutes: 5, factor: 5 },
  { minutes: 15, factor: 15 },
  { minutes: 30, factor: 30 },
];

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function loadState() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw) {
    try {
      return migrateState(JSON.parse(raw));
    } catch {
      /* fall through to default */
    }
  }
  return {
    apps: DEFAULT_APPS,
    charity: "Ärzte ohne Grenzen",
    usage: {},
    extraMinutes: {},
    transactions: [],
    donationTotal: 0,
  };
}

function migrateState(state) {
  state.apps ??= DEFAULT_APPS;
  state.charity ??= "Ärzte ohne Grenzen";
  state.usage ??= {};
  state.extraMinutes ??= {};
  state.transactions ??= [];
  state.donationTotal ??= 0;
  return state;
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

let state = loadState();

let activeSession = null; // { appId, intervalId, secondsUsedThisSession }

function usedSecondsToday(appId) {
  const day = state.usage[todayKey()] || {};
  return day[appId] || 0;
}

function setUsedSecondsToday(appId, seconds) {
  const key = todayKey();
  state.usage[key] ??= {};
  state.usage[key][appId] = seconds;
  saveState();
}

function extraMinutesToday(appId) {
  const key = todayKey();
  state.extraMinutes[key] ??= {};
  return state.extraMinutes[key][appId] || 0;
}

function addExtraMinutesToday(appId, minutes) {
  const key = todayKey();
  state.extraMinutes[key] ??= {};
  state.extraMinutes[key][appId] = (state.extraMinutes[key][appId] || 0) + minutes;
  saveState();
}

function budgetSecondsToday(app) {
  return (app.dailyFreeMinutes + extraMinutesToday(app.id)) * 60;
}

function formatTime(totalSeconds) {
  const s = Math.max(0, Math.round(totalSeconds));
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

function formatEuro(amount) {
  return amount.toLocaleString("de-DE", { style: "currency", currency: "EUR" });
}

function renderCharityLabel() {
  document.getElementById("charityLabel").textContent = state.charity || "eine gute Sache";
}

function renderAppGrid() {
  const grid = document.getElementById("appGrid");
  grid.innerHTML = "";
  state.apps.forEach((app) => {
    const used = usedSecondsToday(app.id);
    const budget = budgetSecondsToday(app);
    const pct = Math.min(100, (used / budget) * 100 || 0);
    const remaining = Math.max(0, budget - used);

    const card = document.createElement("div");
    card.className = "app-card";
    card.innerHTML = `
      <div class="app-card-head">
        <span class="app-card-icon">${app.icon}</span>
        <span class="app-card-name">${app.name}</span>
      </div>
      <div class="progress-bar">
        <div class="progress-fill ${used >= budget ? "over" : ""}" style="width:${pct}%"></div>
      </div>
      <div class="app-card-meta">
        <span>${formatTime(remaining)} übrig</span>
        <span>${app.dailyFreeMinutes} min frei/Tag</span>
      </div>
      <button class="btn btn-primary btn-full open-session" data-app="${app.id}">
        ${used >= budget ? "Zeit kaufen & starten" : "Sitzung starten"}
      </button>
    `;
    grid.appendChild(card);
  });

  grid.querySelectorAll(".open-session").forEach((btn) => {
    btn.addEventListener("click", () => startOrResumeApp(btn.dataset.app));
  });
}

function startOrResumeApp(appId) {
  const app = state.apps.find((a) => a.id === appId);
  if (!app) return;
  const used = usedSecondsToday(app.id);
  const budget = budgetSecondsToday(app);
  if (used >= budget) {
    openBuyModal(app);
  } else {
    openSessionModal(app);
  }
}

function openSessionModal(app) {
  document.getElementById("sessionAppIcon").textContent = app.icon;
  document.getElementById("sessionAppName").textContent = app.name;
  document.getElementById("sessionStatus").textContent = "Sitzung läuft …";
  showModal("sessionModal");
  runSessionTick(app);
  activeSession = {
    appId: app.id,
    intervalId: setInterval(() => runSessionTick(app), 1000),
  };
}

function runSessionTick(app) {
  let used = usedSecondsToday(app.id);
  const budget = budgetSecondsToday(app);

  if (used >= budget) {
    stopActiveSession();
    closeModal("sessionModal");
    openBuyModal(app);
    return;
  }

  used += 1;
  setUsedSecondsToday(app.id, used);

  const remaining = Math.max(0, budget - used);
  document.getElementById("timerDisplay").textContent = formatTime(remaining);
  const pct = Math.min(100, (used / budget) * 100);
  document.getElementById("sessionProgressFill").style.width = `${pct}%`;
  document.getElementById("sessionProgressFill").classList.toggle("over", used >= budget);

  if (used >= budget) {
    document.getElementById("sessionStatus").textContent = "Frei-Kontingent aufgebraucht.";
  }

  renderAppGrid();
}

function stopActiveSession() {
  if (activeSession) {
    clearInterval(activeSession.intervalId);
    activeSession = null;
  }
}

let pendingBuyApp = null;
let selectedPackageIndex = 1;

function openBuyModal(app) {
  pendingBuyApp = app;
  selectedPackageIndex = 1;
  document.getElementById("buyExplainer").textContent =
    `Dein Frei-Kontingent für ${app.name} ist heute aufgebraucht. Schalte weitere Minuten frei ` +
    `– der Betrag wird als Spende an ${state.charity || "eine gute Sache"} verbucht.`;
  renderBuyOptions(app);
  updateCardFormValidity();
  showModal("buyModal");
}

function renderBuyOptions(app) {
  const container = document.getElementById("buyOptions");
  container.innerHTML = "";
  BUY_PACKAGES.forEach((pkg, idx) => {
    const amount = pkg.minutes * app.pricePerMinute;
    const row = document.createElement("div");
    row.className = "buy-option" + (idx === selectedPackageIndex ? " selected" : "");
    row.innerHTML = `<span>${pkg.minutes} Minuten</span><span class="amount">${formatEuro(amount)}</span>`;
    row.addEventListener("click", () => {
      selectedPackageIndex = idx;
      renderBuyOptions(app);
    });
    container.appendChild(row);
  });
}

function updateCardFormValidity() {
  const num = document.getElementById("cardNumber").value.replace(/\s/g, "");
  const expiry = document.getElementById("cardExpiry").value;
  const cvc = document.getElementById("cardCvc").value;
  const valid = num.length >= 12 && /^\d{2}\/\d{2}$/.test(expiry) && cvc.length >= 3;
  document.getElementById("confirmBuyBtn").disabled = !valid;
}

function confirmBuy() {
  if (!pendingBuyApp) return;
  const pkg = BUY_PACKAGES[selectedPackageIndex];
  const amount = pkg.minutes * pendingBuyApp.pricePerMinute;

  addExtraMinutesToday(pendingBuyApp.id, pkg.minutes);
  state.donationTotal += amount;
  state.transactions.push({
    date: new Date().toISOString(),
    appId: pendingBuyApp.id,
    appName: pendingBuyApp.name,
    minutes: pkg.minutes,
    amount,
  });
  saveState();

  document.getElementById("cardNumber").value = "";
  document.getElementById("cardExpiry").value = "";
  document.getElementById("cardCvc").value = "";

  closeModal("buyModal");
  renderAppGrid();
  openSessionModal(pendingBuyApp);
  pendingBuyApp = null;
}

function renderSettings() {
  document.getElementById("charityInput").value = state.charity;
  const list = document.getElementById("settingsAppList");
  list.innerHTML = "";
  state.apps.forEach((app) => {
    const row = document.createElement("div");
    row.className = "settings-app-row";
    row.innerHTML = `
      <span class="app-icon-small">${app.icon}</span>
      <span>${app.name}</span>
      <input type="number" min="1" value="${app.dailyFreeMinutes}" title="Frei-Minuten/Tag" data-field="dailyFreeMinutes" data-app="${app.id}" />
      <input type="number" min="0.01" step="0.01" value="${app.pricePerMinute}" title="Preis/Minute (€)" data-field="pricePerMinute" data-app="${app.id}" />
    `;
    list.appendChild(row);
  });

  list.querySelectorAll("input").forEach((input) => {
    input.addEventListener("change", () => {
      const app = state.apps.find((a) => a.id === input.dataset.app);
      if (!app) return;
      const value = parseFloat(input.value);
      if (!isNaN(value) && value > 0) {
        app[input.dataset.field] = value;
        saveState();
        renderAppGrid();
      }
    });
  });
}

function renderStats() {
  document.getElementById("statDonated").textContent = formatEuro(state.donationTotal);
  const usedToday = Object.values(state.usage[todayKey()] || {}).reduce((a, b) => a + b, 0);
  document.getElementById("statMinutesToday").textContent = `${Math.round(usedToday / 60)} min`;

  const overBudgetDays = Object.keys(state.usage).filter((day) => {
    const dayUsage = state.usage[day];
    return state.apps.some((app) => {
      const used = dayUsage[app.id] || 0;
      const extra = (state.extraMinutes[day] && state.extraMinutes[day][app.id]) || 0;
      return used >= (app.dailyFreeMinutes + extra) * 60 && extra > 0;
    });
  }).length;
  document.getElementById("statOverBudgetDays").textContent = overBudgetDays;

  const historyList = document.getElementById("historyList");
  historyList.innerHTML = "";
  if (state.transactions.length === 0) {
    historyList.innerHTML = `<p class="fine-print">Noch keine gekaufte Zeit.</p>`;
  }
  [...state.transactions].reverse().forEach((tx) => {
    const item = document.createElement("div");
    item.className = "history-item";
    const date = new Date(tx.date);
    item.innerHTML = `
      <span>${tx.appName} · ${tx.minutes} min</span>
      <span class="amount">${formatEuro(tx.amount)}</span>
      <span class="h-date">${date.toLocaleDateString("de-DE")} ${date.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })}</span>
    `;
    historyList.appendChild(item);
  });
}

function showModal(id) {
  document.getElementById(id).classList.remove("hidden");
}
function closeModal(id) {
  document.getElementById(id).classList.add("hidden");
  if (id === "sessionModal") {
    stopActiveSession();
  }
}

function addNewApp() {
  const icon = document.getElementById("newAppIcon").value.trim() || "📱";
  const name = document.getElementById("newAppName").value.trim();
  const minutes = parseFloat(document.getElementById("newAppMinutes").value);
  const price = parseFloat(document.getElementById("newAppPrice").value);
  if (!name || !minutes || !price) return;

  const id = name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now();
  state.apps.push({ id, icon, name, dailyFreeMinutes: minutes, pricePerMinute: price });
  saveState();
  renderAppGrid();
  renderSettings();

  document.getElementById("newAppIcon").value = "";
  document.getElementById("newAppName").value = "";
  document.getElementById("newAppMinutes").value = "30";
  document.getElementById("newAppPrice").value = "0.10";
  closeModal("addAppModal");
}

function init() {
  renderCharityLabel();
  renderAppGrid();

  document.querySelectorAll("[data-close]").forEach((btn) => {
    btn.addEventListener("click", () => closeModal(btn.dataset.close));
  });
  document.querySelectorAll(".modal-overlay").forEach((overlay) => {
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) closeModal(overlay.id);
    });
  });

  document.getElementById("stopSessionBtn").addEventListener("click", () => {
    closeModal("sessionModal");
  });

  document.getElementById("settingsBtn").addEventListener("click", () => {
    renderSettings();
    showModal("settingsModal");
  });
  document.getElementById("statsBtn").addEventListener("click", () => {
    renderStats();
    showModal("statsModal");
  });
  document.getElementById("addAppBtn").addEventListener("click", () => showModal("addAppModal"));
  document.getElementById("createAppBtn").addEventListener("click", addNewApp);

  document.getElementById("charityInput").addEventListener("change", (e) => {
    state.charity = e.target.value.trim() || "eine gute Sache";
    saveState();
    renderCharityLabel();
  });

  ["cardNumber", "cardExpiry", "cardCvc"].forEach((id) => {
    document.getElementById(id).addEventListener("input", updateCardFormValidity);
  });
  document.getElementById("confirmBuyBtn").addEventListener("click", confirmBuy);

  document.getElementById("resetDayBtn").addEventListener("click", () => {
    delete state.usage[todayKey()];
    delete state.extraMinutes[todayKey()];
    saveState();
    renderAppGrid();
  });

  document.getElementById("resetAllBtn").addEventListener("click", () => {
    if (!confirm("Wirklich alle Daten löschen?")) return;
    localStorage.removeItem(STORAGE_KEY);
    state = loadState();
    renderCharityLabel();
    renderAppGrid();
    renderSettings();
  });
}

init();
