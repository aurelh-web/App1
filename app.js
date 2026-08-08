const STORAGE_KEY = "reelmeter-state-v1";

// Ungefähre physische Bildschirmhöhe (Hochformat, cm) – nur zur Demo, keine
// Herstellerangabe im strengen Sinn. Bestimmt, wie viel "Strecke" ein Swipe zählt.
const DEVICES = [
  { id: "iphone-se", label: "iPhone SE", heightCm: 12.2 },
  { id: "iphone-14", label: "iPhone 14 / 15", heightCm: 14.7 },
  { id: "iphone-15-pro-max", label: "iPhone 15/16 Pro Max", heightCm: 16.0 },
  { id: "pixel-8", label: "Google Pixel 8", heightCm: 14.7 },
  { id: "galaxy-s24-ultra", label: "Samsung Galaxy S24 Ultra", heightCm: 16.2 },
];

const REEL_CONTENT = [
  ["🍜", "Rezept: 5-Minuten-Ramen"],
  ["🐶", "Hund reagiert auf Türklingel"],
  ["✈️", "3 Tage Lissabon für unter 300€"],
  ["🏋️", "Push-Day in 60 Sekunden"],
  ["🎸", "Cover: bekannter Song, unerkannt"],
  ["🧠", "Fun Fact über das Gehirn"],
  ["🌆", "Timelapse: Sonnenuntergang Stadt"],
  ["🐱", "Katze erschrickt sich vor Gurke"],
  ["📈", "3 Investment-Fehler, die jeder macht"],
  ["🍕", "Pizza-Hack, den keiner kennt"],
  ["💃", "Trend-Tanz Nummer 4.827"],
  ["🚗", "Auto-Restauration, Vorher/Nachher"],
  ["🧳", "Packliste für den nächsten Trip"],
  ["🎮", "Clutch-Moment im Ranked-Match"],
  ["🧑‍🍳", "Streetfood aus Bangkok"],
];

function todayKey(d = new Date()) {
  return d.toISOString().slice(0, 10);
}

function defaultState() {
  return {
    deviceId: DEVICES[1].id,
    today: { date: todayKey(), reels: 0, distanceCm: 0 },
    allTime: { reels: 0, distanceCm: 0 },
    history: {}, // dateKey -> reels count (für die letzten Tage, exkl. heute)
  };
}

function loadState() {
  const raw = localStorage.getItem(STORAGE_KEY);
  let state;
  try {
    state = raw ? JSON.parse(raw) : defaultState();
  } catch {
    state = defaultState();
  }
  state = rolloverIfNewDay(state);
  return state;
}

function rolloverIfNewDay(state) {
  const key = todayKey();
  if (state.today.date !== key) {
    state.history[state.today.date] = state.today.reels;
    state.today = { date: key, reels: 0, distanceCm: 0 };
  }
  return state;
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

let state = loadState();

function currentDevice() {
  return DEVICES.find((d) => d.id === state.deviceId) ?? DEVICES[0];
}

function registerSwipe() {
  const heightCm = currentDevice().heightCm;
  state.today.reels += 1;
  state.today.distanceCm += heightCm;
  state.allTime.reels += 1;
  state.allTime.distanceCm += heightCm;
  saveState();
  renderWidget();
}

function formatMeters(cm) {
  const m = cm / 100;
  if (m < 1000) return `${m.toFixed(m < 10 ? 1 : 0)} m`;
  return `${(m / 1000).toFixed(2)} km`;
}

function formatKm(cm) {
  return `${(cm / 100000).toFixed(3)} km`;
}

function comparisonText(totalCm) {
  const km = totalCm / 100000;
  if (km <= 0) return "Noch keine Strecke – leg los!";
  if (km < 0.05) return `Erst ${Math.round(totalCm)} cm – weiterswipen für einen Vergleich.`;

  const facts = [
    { km: 0.33, label: "Eiffelturm-Höhen" },
    { km: 0.828, label: "Burj-Khalifa-Höhen" },
    { km: 5, label: "Runden um den Alexanderplatz" },
    { km: 42.195, label: "Marathon-Strecken" },
    { km: 289, label: "Strecken Berlin–Hamburg" },
  ];
  let best = facts[0];
  for (const f of facts) {
    if (km >= f.km * 0.2) best = f;
  }
  const times = km / best.km;
  const timesText = times < 1 ? times.toFixed(2) : times < 10 ? times.toFixed(1) : Math.round(times).toString();
  return `Das sind ${timesText}× ${best.label} (${km.toFixed(2)} km).`;
}

function buildFeed() {
  const feed = document.getElementById("feed");
  const cards = [];
  // 60 Karten reichen für eine Demo-Session; jede Karte wiederholt den Inhalt-Pool.
  for (let i = 0; i < 60; i++) {
    const [emoji, caption] = REEL_CONTENT[i % REEL_CONTENT.length];
    const hue = (i * 47) % 360;
    const el = document.createElement("div");
    el.className = "reel";
    el.style.background = `linear-gradient(160deg, hsl(${hue} 60% 22%), hsl(${(hue + 40) % 360} 55% 12%))`;
    el.innerHTML = `
      <span class="index">#${i + 1}</span>
      <span class="emoji">${emoji}</span>
      <span class="caption">${caption}</span>
    `;
    feed.appendChild(el);
    cards.push(el);
  }
  return cards;
}

function observeFeed(cards) {
  let activeIndex = -1;
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting && entry.intersectionRatio > 0.6) {
          const idx = cards.indexOf(entry.target);
          if (idx !== -1 && idx !== activeIndex) {
            if (activeIndex !== -1) registerSwipe();
            activeIndex = idx;
          }
        }
      }
    },
    { root: document.getElementById("feed"), threshold: [0.6] }
  );
  cards.forEach((c) => observer.observe(c));
}

function renderDeviceSelect() {
  const select = document.getElementById("device-select");
  select.innerHTML = DEVICES.map(
    (d) => `<option value="${d.id}" ${d.id === state.deviceId ? "selected" : ""}>${d.label}</option>`
  ).join("");
  select.addEventListener("change", () => {
    state.deviceId = select.value;
    saveState();
    renderWidget();
  });
}

function renderWeekChart() {
  const container = document.getElementById("week-chart");
  container.innerHTML = "";
  const days = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const key = todayKey(d);
    const reels = key === state.today.date ? state.today.reels : state.history[key] ?? 0;
    days.push({ key, reels, label: d.toLocaleDateString("de-DE", { weekday: "narrow" }) });
  }
  const max = Math.max(1, ...days.map((d) => d.reels));
  for (const day of days) {
    const wrap = document.createElement("div");
    wrap.className = "week-chart-wrap";
    wrap.style.flex = "1";
    const bar = document.createElement("div");
    bar.className = "bar";
    bar.style.height = `${Math.max(3, (day.reels / max) * 50)}px`;
    bar.title = `${day.reels} Reels`;
    const label = document.createElement("div");
    label.className = "bar-label";
    label.textContent = day.label;
    wrap.appendChild(bar);
    wrap.appendChild(label);
    container.appendChild(wrap);
  }
}

function renderWidget() {
  document.getElementById("w-reels-today").textContent = state.today.reels;
  document.getElementById("w-dist-today").textContent = formatMeters(state.today.distanceCm);
  document.getElementById("w-reels-all").textContent = state.allTime.reels;
  document.getElementById("w-dist-all").textContent = formatKm(state.allTime.distanceCm);
  document.getElementById("comparison").textContent = comparisonText(state.allTime.distanceCm);
  document.getElementById("screen-height-info").textContent = `${currentDevice().heightCm} cm pro Swipe`;
  renderWeekChart();
}

function initSizeToggle() {
  const buttons = document.querySelectorAll(".size-btn");
  const widget = document.getElementById("widget");
  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      buttons.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      widget.dataset.size = btn.dataset.size;
    });
  });
}

function initReset() {
  document.getElementById("reset-btn").addEventListener("click", () => {
    if (!confirm("Alle ReelMeter-Statistiken wirklich zurücksetzen?")) return;
    state = defaultState();
    saveState();
    renderWidget();
  });
}

function init() {
  renderDeviceSelect();
  initSizeToggle();
  initReset();
  const cards = buildFeed();
  observeFeed(cards);
  renderWidget();
}

document.addEventListener("DOMContentLoaded", init);
