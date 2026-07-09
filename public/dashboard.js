/*
 * Dashboard behaviour — native Rails port of the anava-web React reference.
 * Plain vanilla JS (no build step). The page is server-rendered by
 * DashboardController; this handles the interactive bits the React app had:
 * health indicator, tab switching, filter/model navigation, expand/collapse
 * of day groups, the recording detail modal (amplitude chart + map + JSON
 * download), and the analytics charts. Charts use the vendored Chart.js.
 */
(function () {
  "use strict";

  var SLOTS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"];
  var CHART_COLORS = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#ec4899"];

  function slotName(slotId) {
    return SLOTS[slotId] || "Slot " + slotId;
  }

  function pad2(n) { return String(n).padStart(2, "0"); }

  function formatDurationShort(seconds) {
    if (!seconds) return "0:00";
    var mins = Math.floor(seconds / 60);
    var secs = seconds % 60;
    return mins + ":" + pad2(secs);
  }

  function formatTime(ms) {
    var d = new Date(Number(ms));
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
  }

  function formatDateTime(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    if (isNaN(d.getTime())) return String(iso);
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) +
      " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
  }

  function readJson(id) {
    var el = document.getElementById(id);
    if (!el) return null;
    try { return JSON.parse(el.textContent); } catch (e) { return null; }
  }

  // Recording fields (user_id, model, ...) originate from client API input, so
  // escape before interpolating into innerHTML to avoid stored XSS.
  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  // ---- Health indicator ---------------------------------------------------
  function initHealth() {
    var dot = document.querySelector(".health-dot");
    var label = document.querySelector(".health-label");
    if (!dot) return;
    fetch("/health")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
      .then(function (data) {
        var ok = data && data.success;
        dot.classList.toggle("connected", !!ok);
        if (label) label.textContent = ok ? "connected" : "error";
      })
      .catch(function () {
        dot.classList.add("disconnected");
        if (label) label.textContent = "disconnected";
      });
  }

  // ---- URL / navigation helpers ------------------------------------------
  function currentTab() {
    var url = new URL(window.location.href);
    var tab = url.searchParams.get("tab");
    return tab === "analytics" ? "analytics" : "recordings";
  }

  function navigateWith(changes, resetPage) {
    var url = new URL(window.location.href);
    Object.keys(changes).forEach(function (key) {
      if (changes[key] === null) url.searchParams.delete(key);
      else url.searchParams.set(key, changes[key]);
    });
    if (resetPage) url.searchParams.set("page", "1");
    window.location.href = url.toString();
  }

  function initNavSelects() {
    document.querySelectorAll("select[data-nav]").forEach(function (sel) {
      sel.addEventListener("change", function () {
        var changes = {};
        changes[sel.getAttribute("data-nav")] = sel.value;
        // Model/range/per_page changes should reset pagination.
        navigateWith(changes, true);
      });
    });
  }

  // ---- Tabs ---------------------------------------------------------------
  function showTab(tab) {
    document.querySelectorAll(".tab-trigger").forEach(function (btn) {
      btn.classList.toggle("active", btn.getAttribute("data-tab") === tab);
    });
    document.querySelectorAll(".tab-panel").forEach(function (panel) {
      panel.hidden = panel.getAttribute("data-tab") !== tab;
    });
    var url = new URL(window.location.href);
    url.searchParams.set("tab", tab);
    window.history.replaceState({}, "", url.toString());
    // Charts must be built while their panel is visible: Chart.js can't size a
    // canvas inside a display:none container, so defer until the tab is shown.
    if (tab === "analytics") ensureAnalyticsCharts();
  }

  function initTabs() {
    document.querySelectorAll(".tab-trigger").forEach(function (btn) {
      btn.addEventListener("click", function () {
        showTab(btn.getAttribute("data-tab"));
      });
    });
    showTab(currentTab());
  }

  // ---- Expand / collapse day groups --------------------------------------
  function initDayToggles() {
    document.querySelectorAll(".day-header").forEach(function (header) {
      header.addEventListener("click", function () {
        var body = header.parentElement.querySelector(".day-body");
        if (!body) return;
        var expanded = header.getAttribute("aria-expanded") === "true";
        header.setAttribute("aria-expanded", String(!expanded));
        body.hidden = expanded;
      });
    });
  }

  // ---- Recording detail modal --------------------------------------------
  var amplitudeChart = null;

  function amplitudesFrom(recording) {
    var raw = recording.amplitudes_json;
    if (!raw) return [];
    var parsed;
    try { parsed = JSON.parse(raw); } catch (e) { return []; }
    if (!Array.isArray(parsed)) return [];
    return parsed.map(function (item) {
      if (typeof item === "number") return item;
      if (item !== null && typeof item === "object" && "y" in item) return Number(item.y);
      return 0;
    });
  }

  function buildInfoRows(recording) {
    var rows = [];
    function add(label, value, full) {
      rows.push(
        '<div class="' + (full ? "full" : "") + '">' +
        '<p class="label">' + label + "</p>" +
        '<p class="value">' + escapeHtml(value) + "</p></div>"
      );
    }
    if (recording.id !== undefined && recording.id !== null) add("ID", recording.id);
    add("Slot", slotName(recording.slot_id));
    add("Date", recording.date);
    add("Duration", formatDurationShort(recording.duration));
    if (recording.start_timestamp) add("Start", formatTime(recording.start_timestamp));
    if (recording.end_timestamp) add("End", formatTime(recording.end_timestamp));
    if (recording.percentage !== undefined && recording.percentage !== null) add("Activity %", recording.percentage + "%");
    if (recording.model) add("Model", recording.model);
    add("User ID", recording.user_id, true);
    if (recording.created_at) add("Created At", formatDateTime(recording.created_at));
    if (recording.updated_at) add("Updated At", formatDateTime(recording.updated_at));
    return rows.join("");
  }

  function openModal(recording) {
    var overlay = document.getElementById("recording-modal");
    if (!overlay) return;

    overlay.querySelector(".info-grid").innerHTML = buildInfoRows(recording);

    // Amplitude waveform chart
    var ampSection = overlay.querySelector("[data-amplitude-section]");
    var amplitudes = amplitudesFrom(recording);
    if (amplitudeChart) { amplitudeChart.destroy(); amplitudeChart = null; }
    if (amplitudes.length > 0 && window.Chart) {
      ampSection.hidden = false;
      var ctx = overlay.querySelector("#amplitude-canvas").getContext("2d");
      amplitudeChart = new Chart(ctx, {
        type: "line",
        data: {
          labels: amplitudes.map(function (_, i) { return i; }),
          datasets: [{
            data: amplitudes,
            borderColor: "#2563eb",
            backgroundColor: "rgba(37, 99, 235, 0.2)",
            borderWidth: 1.5,
            fill: true,
            pointRadius: 0,
            tension: 0.3
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                title: function (items) { return "Sample " + items[0].label; },
                label: function (item) { return "Amplitude: " + item.formattedValue; }
              }
            }
          },
          scales: { x: { display: false } }
        }
      });
    } else {
      ampSection.hidden = true;
    }

    // Map (OpenStreetMap embed) — only when a real location is present
    var mapSection = overlay.querySelector("[data-map-section]");
    var lat = Number(recording.latitude);
    var lon = Number(recording.longitude);
    var hasLocation = recording.latitude != null && recording.longitude != null && lat !== 0 && lon !== 0 && !isNaN(lat) && !isNaN(lon);
    if (hasLocation) {
      mapSection.hidden = false;
      mapSection.querySelector(".section-label span").textContent = "Location (" + lat + ", " + lon + ")";
      var bbox = [lon - 0.005, lat - 0.005, lon + 0.005, lat + 0.005].join(",");
      mapSection.querySelector("iframe").src =
        "https://www.openstreetmap.org/export/embed.html?bbox=" + bbox + "&layer=mapnik&marker=" + lat + "," + lon;
    } else {
      mapSection.hidden = true;
      mapSection.querySelector("iframe").src = "about:blank";
    }

    // Download JSON
    var downloadBtn = overlay.querySelector("[data-download]");
    downloadBtn.onclick = function () {
      var blob = new Blob([JSON.stringify(recording, null, 2)], { type: "application/json" });
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url;
      a.download = "recording-" + (recording.id != null ? recording.id : recording.date) + "-" + recording.slot_id + ".json";
      a.click();
      URL.revokeObjectURL(url);
    };

    overlay.hidden = false;
  }

  function closeModal() {
    var overlay = document.getElementById("recording-modal");
    if (!overlay) return;
    overlay.hidden = true;
    if (amplitudeChart) { amplitudeChart.destroy(); amplitudeChart = null; }
  }

  function initModal() {
    var recordings = readJson("recordings-json") || {};
    document.querySelectorAll(".rec-row").forEach(function (row) {
      row.addEventListener("click", function () {
        var rec = recordings[row.getAttribute("data-recording-id")];
        if (rec) openModal(rec);
      });
    });
    var overlay = document.getElementById("recording-modal");
    if (!overlay) return;
    overlay.addEventListener("click", function (e) { if (e.target === overlay) closeModal(); });
    overlay.querySelector(".modal-close").addEventListener("click", closeModal);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeModal(); });
  }

  // ---- Analytics charts ---------------------------------------------------
  var analyticsChartsBuilt = false;

  function ensureAnalyticsCharts() {
    if (analyticsChartsBuilt) return;
    analyticsChartsBuilt = true;
    initAnalyticsCharts();
  }

  function initAnalyticsCharts() {
    if (!window.Chart) return;
    var data = readJson("analytics-json");
    if (!data) return;

    var dailyCanvas = document.getElementById("daily-chart");
    if (dailyCanvas && data.dailySummary) {
      new Chart(dailyCanvas.getContext("2d"), {
        type: "line",
        data: {
          labels: data.dailySummary.map(function (d) { return d.label; }),
          datasets: [
            {
              label: "Recordings", yAxisID: "y",
              data: data.dailySummary.map(function (d) { return d.count; }),
              borderColor: "#3b82f6", backgroundColor: "#3b82f6", tension: 0.3, borderWidth: 2
            },
            {
              label: "Duration (min)", yAxisID: "y1",
              data: data.dailySummary.map(function (d) { return d.durationMinutes; }),
              borderColor: "#10b981", backgroundColor: "#10b981", tension: 0.3, borderWidth: 2
            }
          ]
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          scales: {
            y: { type: "linear", position: "left", beginAtZero: true },
            y1: { type: "linear", position: "right", beginAtZero: true, grid: { drawOnChartArea: false } }
          }
        }
      });
    }

    var slotCanvas = document.getElementById("slot-chart");
    if (slotCanvas && data.slotData && data.slotData.length > 0) {
      new Chart(slotCanvas.getContext("2d"), {
        type: "bar",
        data: {
          labels: data.slotData.map(function (s) { return s.name; }),
          datasets: [{
            label: "Recordings",
            data: data.slotData.map(function (s) { return s.value; }),
            backgroundColor: data.slotData.map(function (_, i) { return CHART_COLORS[i % CHART_COLORS.length]; })
          }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
      });
    }

    var typeCanvas = document.getElementById("type-chart");
    if (typeCanvas && data.activityTypeData && data.activityTypeData.length > 0) {
      new Chart(typeCanvas.getContext("2d"), {
        type: "pie",
        data: {
          labels: data.activityTypeData.map(function (t) { return t.name; }),
          datasets: [{
            data: data.activityTypeData.map(function (t) { return t.value; }),
            backgroundColor: data.activityTypeData.map(function (_, i) { return CHART_COLORS[i % CHART_COLORS.length]; })
          }]
        },
        options: { responsive: true, maintainAspectRatio: false }
      });
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    initHealth();
    initNavSelects();
    initDayToggles();
    initModal();
    // initTabs() calls showTab(), which builds the analytics charts if the
    // analytics tab is the active one on load — so run it last.
    initTabs();
  });
})();
