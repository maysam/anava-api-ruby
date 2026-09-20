/*
 * The per-user panel's one piece of client-side behaviour: drawing the
 * last-30-days activity chart. Everything else on the page is server-rendered
 * (app/views/panel/show.html.erb). Chart.js is the same vendored copy the
 * admin dashboard uses (public/admin/vendor/chart.umd.min.js).
 */
(function () {
  "use strict";

  function readEmbeddedJson(elementId) {
    var element = document.getElementById(elementId);
    if (!element) return null;
    try {
      return JSON.parse(element.textContent);
    } catch (error) {
      return null;
    }
  }

  function shortDateLabel(isoDate) {
    var parsed = new Date(isoDate + "T00:00:00");
    if (isNaN(parsed.getTime())) return isoDate;
    return parsed.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  }

  function drawDailyActivityChart(dailyActivity) {
    var canvas = document.getElementById("daily-activity-canvas");
    if (!canvas || typeof Chart === "undefined" || !dailyActivity) return;

    var styles = getComputedStyle(document.documentElement);
    var primary = styles.getPropertyValue("--primary").trim() || "#0f6b52";
    var mutedForeground = styles.getPropertyValue("--muted-foreground").trim() || "#6b7670";
    var border = styles.getPropertyValue("--border").trim() || "#e4e0d6";

    new Chart(canvas.getContext("2d"), {
      type: "bar",
      data: {
        labels: dailyActivity.map(function (day) { return shortDateLabel(day.date); }),
        datasets: [{
          label: "Sessions",
          data: dailyActivity.map(function (day) { return day.count; }),
          backgroundColor: primary,
          borderRadius: 4,
          maxBarThickness: 18
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              afterLabel: function (context) {
                var day = dailyActivity[context.dataIndex];
                if (!day || !day.count) return "";
                return "Average score " + day.averagePercentage + "%";
              }
            }
          }
        },
        scales: {
          x: {
            ticks: { color: mutedForeground, maxRotation: 0, autoSkip: true, maxTicksLimit: 8 },
            grid: { display: false }
          },
          y: {
            beginAtZero: true,
            ticks: { color: mutedForeground, precision: 0 },
            grid: { color: border }
          }
        }
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    var panelData = readEmbeddedJson("panel-json");
    if (panelData) drawDailyActivityChart(panelData.dailyActivity);
  });
})();
