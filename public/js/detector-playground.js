const DEFAULT_ALGORITHM_SOURCE = `function detector(samples, helpers) {
  const config = {
    minSampleCount: 20,
    minWindowSize: 5,
    smoothingWindowSize: 55,
    thresholdStdDevMultiplier: 3,
    minHighAmplitude: 0.08,
    peakDeduplicationWindowMs: 600,
    pairGapMs: 7000
  };

  function average(values) {
    if (!values.length) {
      return 0;
    }

    let total = 0;
    for (const value of values) {
      total += value;
    }
    return total / values.length;
  }

  function standardDeviation(values) {
    if (!values.length) {
      return 0;
    }

    const mean = average(values);
    let squaredDeltaTotal = 0;
    for (const value of values) {
      const delta = value - mean;
      squaredDeltaTotal += delta * delta;
    }
    return Math.sqrt(squaredDeltaTotal / values.length);
  }

  function smoothSamples(points, windowSize) {
    const halfWindow = Math.floor(windowSize / 2);
    const smoothedPoints = [];

    for (let index = 0; index < points.length; index += 1) {
      const start = Math.max(0, index - halfWindow);
      const end = Math.min(points.length, index + halfWindow + 1);
      let total = 0;
      for (let cursor = start; cursor < end; cursor += 1) {
        total += points[cursor].amplitude;
      }

      smoothedPoints.push({
        timeMs: points[index].timeMs,
        amplitude: total / (end - start)
      });
    }

    return smoothedPoints;
  }

  if (samples.length < config.minSampleCount) {
    return {
      config,
      threshold: config.minHighAmplitude,
      smoothed: [],
      acceptedHighs: [],
      pairEvents: [],
      pendingHigh: null
    };
  }

  const resolvedWindowSize = Math.min(
    config.smoothingWindowSize,
    samples.length % 2 === 0 ? samples.length - 1 : samples.length
  );
  if (resolvedWindowSize < config.minWindowSize) {
    return {
      config,
      threshold: config.minHighAmplitude,
      smoothed: [],
      acceptedHighs: [],
      pairEvents: [],
      pendingHigh: null
    };
  }

  const smoothed = smoothSamples(samples, resolvedWindowSize);

  const smoothedValues = smoothed.map((point) => point.amplitude);
  const threshold = Math.max(
    average(smoothedValues) +
      (standardDeviation(smoothedValues) * config.thresholdStdDevMultiplier),
    config.minHighAmplitude
  );

  const candidatePeaks = [];
  for (let index = 1; index < smoothed.length - 1; index += 1) {
    const currentValue = smoothed[index].amplitude;
    if (currentValue < threshold) {
      continue;
    }

    if (currentValue >= smoothed[index - 1].amplitude &&
      currentValue >= smoothed[index + 1].amplitude) {
      candidatePeaks.push({
        sampleIndex: index,
        timeMs: samples[index].timeMs,
        amplitude: samples[index].amplitude,
        smoothedAmplitude: currentValue
      });
    }
  }

  const acceptedHighs = [];
  for (const peak of candidatePeaks) {
    const previousPeak = acceptedHighs[acceptedHighs.length - 1];
    if (previousPeak && (peak.timeMs - previousPeak.timeMs) < config.peakDeduplicationWindowMs) {
      if (peak.smoothedAmplitude > previousPeak.smoothedAmplitude) {
        acceptedHighs[acceptedHighs.length - 1] = peak;
      }
    } else {
      acceptedHighs.push(peak);
    }
  }

  const pairEvents = [];
  let pendingHigh = null;
  for (const highPoint of acceptedHighs) {
    if (!pendingHigh) {
      pendingHigh = highPoint;
      continue;
    }

    const gapMs = highPoint.timeMs - pendingHigh.timeMs;
    if (gapMs <= config.pairGapMs) {
      pairEvents.push({
        pairNumber: pairEvents.length + 1,
        first: pendingHigh,
        second: highPoint,
        gapMs,
        completedAtMs: highPoint.timeMs
      });
      pendingHigh = null;
    } else {
      pendingHigh = highPoint;
    }
  }

  return {
    config,
    threshold,
    smoothed,
    acceptedHighs,
    pairEvents,
    pendingHigh
  };
}`;

const state = {
  fileName: "",
  recording: null,
  amplitudes: [],
  detection: createEmptyDetectionResult(),
  currentTimeMs: 0,
  playbackSpeed: 16,
  isPlaying: false,
  animationFrameId: null,
  lastFrameTime: null,
  detectorSource: DEFAULT_ALGORITHM_SOURCE,
  lastGoodDetection: createEmptyDetectionResult()
};

const refs = {
  pickFileButton: document.getElementById("pick-file-button"),
  fileInput: document.getElementById("file-input"),
  dropZone: document.getElementById("drop-zone"),
  waveformCanvas: document.getElementById("waveform-canvas"),
  playToggle: document.getElementById("play-toggle"),
  timeSlider: document.getElementById("time-slider"),
  timeCurrent: document.getElementById("time-current"),
  timeTotal: document.getElementById("time-total"),
  speedSelect: document.getElementById("speed-select"),
  recordingMeta: document.getElementById("recording-meta"),
  statHighPoints: document.getElementById("stat-high-points"),
  statPairs: document.getElementById("stat-pairs"),
  statPending: document.getElementById("stat-pending"),
  statThreshold: document.getElementById("stat-threshold"),
  eventList: document.getElementById("event-list"),
  algorithmEditor: document.getElementById("algorithm-editor"),
  runDetectorButton: document.getElementById("run-detector-button"),
  resetDetectorButton: document.getElementById("reset-detector-button"),
  autorunCheckbox: document.getElementById("autorun-checkbox"),
  algorithmStatus: document.getElementById("algorithm-status"),
  debugOutput: document.getElementById("debug-output")
};

let editorRunTimer = null;

const helpers = {
  average(values) {
    if (!values.length) {
      return 0;
    }
    return values.reduce((total, value) => total + value, 0) / values.length;
  },

  standardDeviation(values) {
    if (!values.length) {
      return 0;
    }

    const mean = helpers.average(values);
    const variance = values.reduce((total, value) => {
      const delta = value - mean;
      return total + (delta * delta);
    }, 0) / values.length;
    return Math.sqrt(variance);
  },

  percentile(values, percentile) {
    if (!values.length) {
      return 0;
    }

    const sortedValues = [...values].sort((left, right) => left - right);
    const position = (sortedValues.length - 1) * percentile;
    const lowerIndex = Math.floor(position);
    const upperIndex = Math.min(sortedValues.length - 1, lowerIndex + 1);
    if (lowerIndex === upperIndex) {
      return sortedValues[lowerIndex];
    }

    const fraction = position - lowerIndex;
    return (sortedValues[lowerIndex] * (1 - fraction)) +
      (sortedValues[upperIndex] * fraction);
  },

  smoothSeries(samples, windowSize) {
    if (!samples.length) {
      return [];
    }

    const resolvedWindowSize = Math.min(
      windowSize,
      samples.length % 2 === 0 ? samples.length - 1 : samples.length
    );
    if (resolvedWindowSize < 3) {
      return samples.map((sample) => ({ timeMs: sample.timeMs, value: sample.amplitude }));
    }

    const halfWindow = Math.floor(resolvedWindowSize / 2);
    return samples.map((sample, index) => {
      const start = Math.max(0, index - halfWindow);
      const end = Math.min(samples.length, index + halfWindow + 1);
      const windowSamples = samples.slice(start, end);
      return {
        timeMs: sample.timeMs,
        value: helpers.average(windowSamples.map((entry) => entry.amplitude))
      };
    });
  },

  dedupePeaks(peaks, dedupeWindowMs) {
    const deduplicatedPeaks = [];
    peaks.forEach((peak) => {
      const previousPeak = deduplicatedPeaks[deduplicatedPeaks.length - 1];
      if (previousPeak && (peak.timeMs - previousPeak.timeMs) < dedupeWindowMs) {
        if (peak.smoothedAmplitude > previousPeak.smoothedAmplitude) {
          deduplicatedPeaks[deduplicatedPeaks.length - 1] = peak;
        }
      } else {
        deduplicatedPeaks.push(peak);
      }
    });
    return deduplicatedPeaks;
  },

  formatTime(ms) {
    return formatTime(ms);
  }
};

boot();

function boot() {
  refs.algorithmEditor.value = DEFAULT_ALGORITHM_SOURCE;
  refs.speedSelect.value = String(state.playbackSpeed);

  refs.pickFileButton.addEventListener("click", pickFile);
  refs.fileInput.addEventListener("change", onFileInputChange);
  refs.dropZone.addEventListener("dragenter", onDragEnter);
  refs.dropZone.addEventListener("dragover", onDragOver);
  refs.dropZone.addEventListener("dragleave", onDragLeave);
  refs.dropZone.addEventListener("drop", onDrop);

  refs.playToggle.addEventListener("click", togglePlayback);
  refs.timeSlider.addEventListener("input", onTimelineInput);
  refs.speedSelect.addEventListener("change", onSpeedChange);

  refs.algorithmEditor.addEventListener("input", onAlgorithmInput);
  refs.runDetectorButton.addEventListener("click", runDetector);
  refs.resetDetectorButton.addEventListener("click", resetDetectorSource);

  window.addEventListener("resize", renderCanvas);

  renderAll();
}

async function pickFile() {
  if (window.showOpenFilePicker) {
    try {
      const [handle] = await window.showOpenFilePicker({
        multiple: false,
        types: [
          {
            description: "JSON files",
            accept: {
              "application/json": [".json"]
            }
          }
        ]
      });

      const file = await handle.getFile();
      await loadRecordingFileSafely(file);
      return;
    } catch (error) {
      if (error && error.name === "AbortError") {
        return;
      }
    }
  }

  refs.fileInput.click();
}

async function onFileInputChange(event) {
  const [file] = event.target.files || [];
  if (!file) {
    return;
  }

  await loadRecordingFileSafely(file);
  refs.fileInput.value = "";
}

function onDragEnter(event) {
  event.preventDefault();
  refs.dropZone.classList.add("active");
}

function onDragOver(event) {
  event.preventDefault();
  refs.dropZone.classList.add("active");
}

function onDragLeave(event) {
  event.preventDefault();
  refs.dropZone.classList.remove("active");
}

async function onDrop(event) {
  event.preventDefault();
  refs.dropZone.classList.remove("active");
  const [file] = event.dataTransfer.files || [];
  if (!file) {
    return;
  }

  await loadRecordingFileSafely(file);
}

async function loadRecordingFileSafely(file) {
  try {
    await loadRecordingFile(file);
    setAlgorithmStatus("Recording loaded", "success");
  } catch (error) {
    stopPlayback();
    setAlgorithmStatus("Could not load that JSON file", "error");
    refs.debugOutput.textContent = String(error.stack || error.message || error);
  }
}

async function loadRecordingFile(file) {
  const rawText = await file.text();
  const parsedRecording = JSON.parse(rawText);
  const amplitudesPayload = typeof parsedRecording.amplitudes_json === "string"
    ? JSON.parse(parsedRecording.amplitudes_json)
    : parsedRecording.amplitudes_json;

  if (!Array.isArray(amplitudesPayload)) {
    throw new Error("The selected JSON file does not contain an amplitudes_json array.");
  }

  state.fileName = file.name;
  state.recording = parsedRecording;
  state.amplitudes = amplitudesPayload
    .map((entry) => ({
      timeMs: Number(entry.x || 0),
      amplitude: Number(entry.y || 0)
    }))
    .filter((entry) => Number.isFinite(entry.timeMs) && Number.isFinite(entry.amplitude))
    .sort((left, right) => left.timeMs - right.timeMs);

  state.currentTimeMs = 0;
  stopPlayback();

  refs.runDetectorButton.disabled = state.amplitudes.length === 0;
  refs.playToggle.disabled = state.amplitudes.length === 0;
  refs.timeSlider.disabled = state.amplitudes.length === 0;

  runDetector();
}

function onTimelineInput(event) {
  state.currentTimeMs = Number(event.target.value);
  stopPlayback(false);
  renderAll();
}

function onSpeedChange(event) {
  state.playbackSpeed = Number(event.target.value);
}

function onAlgorithmInput() {
  state.detectorSource = refs.algorithmEditor.value;
  if (!refs.autorunCheckbox.checked) {
    setAlgorithmStatus("Ready", "neutral");
    return;
  }

  window.clearTimeout(editorRunTimer);
  editorRunTimer = window.setTimeout(() => {
    runDetector();
  }, 180);
}

function resetDetectorSource() {
  refs.algorithmEditor.value = DEFAULT_ALGORITHM_SOURCE;
  state.detectorSource = DEFAULT_ALGORITHM_SOURCE;
  runDetector();
}

function runDetector() {
  if (!state.amplitudes.length) {
    renderAll();
    return;
  }

  try {
    const compiledDetector = new Function(
      "samples",
      "helpers",
      `${refs.algorithmEditor.value}\nif (typeof detector !== "function") { throw new Error("Please define detector(samples, helpers)."); }\nreturn detector(samples, helpers);`
    );
    const rawResult = compiledDetector(state.amplitudes, helpers);
    state.detection = normalizeDetectionResult(rawResult, state.amplitudes);
    state.lastGoodDetection = state.detection;
    state.currentTimeMs = Math.min(state.currentTimeMs, getDurationMs());
    setAlgorithmStatus("Detector running", "success");
  } catch (error) {
    state.detection = state.lastGoodDetection;
    setAlgorithmStatus(error.message || "Detector error", "error");
    refs.debugOutput.textContent = String(error.stack || error.message || error);
    renderAll();
    return;
  }

  renderAll();
}

function normalizeDetectionResult(result, samples) {
  const normalizedSmoothed = Array.isArray(result.smoothed)
    ? result.smoothed.map((point, index) => ({
      timeMs: Number(point.timeMs ?? samples[index]?.timeMs ?? 0),
      amplitude: Number(point.amplitude ?? point.value ?? 0)
    }))
    : [];

  const acceptedHighs = Array.isArray(result.acceptedHighs)
    ? result.acceptedHighs.map((highPoint, index) => ({
      sampleIndex: Number(highPoint.sampleIndex ?? index),
      timeMs: Number(highPoint.timeMs ?? 0),
      amplitude: Number(highPoint.amplitude ?? 0),
      smoothedAmplitude: Number(highPoint.smoothedAmplitude ?? highPoint.amplitude ?? 0)
    })).sort((left, right) => left.timeMs - right.timeMs)
    : [];

  const pairEvents = Array.isArray(result.pairEvents)
    ? result.pairEvents.map((pairEvent, index) => {
      const first = normalizePeak(pairEvent.first);
      const second = normalizePeak(pairEvent.second);
      return {
        pairNumber: Number(pairEvent.pairNumber ?? index + 1),
        first,
        second,
        gapMs: Number(pairEvent.gapMs ?? (second.timeMs - first.timeMs)),
        completedAtMs: Number(pairEvent.completedAtMs ?? second.timeMs)
      };
    }).sort((left, right) => left.completedAtMs - right.completedAtMs)
    : [];

  return {
    config: result.config || {},
    threshold: Number(result.threshold ?? 0),
    smoothed: normalizedSmoothed,
    acceptedHighs,
    pairEvents,
    pendingHigh: result.pendingHigh ? normalizePeak(result.pendingHigh) : null
  };
}

function normalizePeak(peak) {
  return {
    sampleIndex: Number(peak?.sampleIndex ?? 0),
    timeMs: Number(peak?.timeMs ?? 0),
    amplitude: Number(peak?.amplitude ?? 0),
    smoothedAmplitude: Number(peak?.smoothedAmplitude ?? peak?.amplitude ?? 0)
  };
}

function togglePlayback() {
  if (!state.amplitudes.length) {
    return;
  }

  if (state.isPlaying) {
    stopPlayback();
  } else {
    startPlayback();
  }
}

function startPlayback() {
  if (state.currentTimeMs >= getDurationMs()) {
    state.currentTimeMs = 0;
  }

  state.isPlaying = true;
  state.lastFrameTime = null;
  refs.playToggle.textContent = "Pause";
  state.animationFrameId = window.requestAnimationFrame(stepPlayback);
}

function stopPlayback(resetButton = true) {
  state.isPlaying = false;
  state.lastFrameTime = null;
  if (state.animationFrameId) {
    window.cancelAnimationFrame(state.animationFrameId);
  }
  state.animationFrameId = null;

  if (resetButton) {
    refs.playToggle.textContent = "Play";
  }
}

function stepPlayback(frameTime) {
  if (!state.isPlaying) {
    return;
  }

  if (state.lastFrameTime == null) {
    state.lastFrameTime = frameTime;
  }

  const deltaMs = frameTime - state.lastFrameTime;
  state.lastFrameTime = frameTime;
  state.currentTimeMs = Math.min(
    state.currentTimeMs + (deltaMs * state.playbackSpeed),
    getDurationMs()
  );

  if (state.currentTimeMs >= getDurationMs()) {
    stopPlayback();
  }

  renderAll();

  if (state.isPlaying) {
    state.animationFrameId = window.requestAnimationFrame(stepPlayback);
  }
}

function renderAll() {
  syncTimelineControls();
  renderMeta();
  renderCanvas();
  renderStats();
  renderEvents();
  renderDebug();
}

function syncTimelineControls() {
  const durationMs = getDurationMs();
  refs.timeSlider.max = String(durationMs);
  refs.timeSlider.value = String(Math.min(state.currentTimeMs, durationMs));
  refs.timeCurrent.textContent = formatTime(state.currentTimeMs);
  refs.timeTotal.textContent = formatTime(durationMs);
}

function renderMeta() {
  if (!state.recording || !state.amplitudes.length) {
    refs.recordingMeta.textContent = "No file loaded yet";
    return;
  }

  const durationSeconds = (getDurationMs() / 1000).toFixed(1);
  refs.recordingMeta.textContent =
    `${state.fileName} | ${state.amplitudes.length} points | slot ${state.recording.slot_id ?? "?"} | ${durationSeconds}s`;
}

function renderCanvas() {
  const canvas = refs.waveformCanvas;
  const context = canvas.getContext("2d");
  const devicePixelRatio = window.devicePixelRatio || 1;
  const cssWidth = canvas.clientWidth;
  const cssHeight = Math.max(220, Math.min(320, Math.round(cssWidth * 0.24)));

  if (canvas.width !== Math.round(cssWidth * devicePixelRatio) ||
    canvas.height !== Math.round(cssHeight * devicePixelRatio)) {
    canvas.width = Math.round(cssWidth * devicePixelRatio);
    canvas.height = Math.round(cssHeight * devicePixelRatio);
  }

  context.setTransform(1, 0, 0, 1, 0, 0);
  context.scale(devicePixelRatio, devicePixelRatio);
  context.clearRect(0, 0, cssWidth, cssHeight);

  if (!state.amplitudes.length) {
    context.fillStyle = "rgba(17, 32, 59, 0.65)";
    context.font = "16px Space Grotesk";
    context.fillText("Pick a recording JSON to render the waveform.", 20, cssHeight / 2);
    return;
  }

  const padding = { top: 18, right: 18, bottom: 36, left: 46 };
  const chartWidth = cssWidth - padding.left - padding.right;
  const chartHeight = cssHeight - padding.top - padding.bottom;
  const durationMs = getDurationMs();
  const threshold = Number.isFinite(state.detection.threshold) ? state.detection.threshold : 0;
  const smoothed = state.detection.smoothed.length ? state.detection.smoothed : [];
  const maxAmplitude = Math.max(
    ...state.amplitudes.map((point) => point.amplitude),
    ...smoothed.map((point) => point.amplitude),
    threshold,
    0.001
  );

  const xForTime = (timeMs) => padding.left + ((timeMs / durationMs) * chartWidth);
  const yForAmplitude = (amplitude) => padding.top + chartHeight - ((amplitude / maxAmplitude) * chartHeight);

  context.fillStyle = "rgba(31, 111, 235, 0.08)";
  context.fillRect(padding.left, padding.top, chartWidth * (state.currentTimeMs / durationMs), chartHeight);

  drawAxes(context, padding, chartWidth, chartHeight, cssWidth, cssHeight, durationMs, maxAmplitude);

  if (threshold > 0) {
    const thresholdY = yForAmplitude(threshold);
    context.save();
    context.strokeStyle = "#f97316";
    context.setLineDash([8, 8]);
    context.lineWidth = 2;
    context.beginPath();
    context.moveTo(padding.left, thresholdY);
    context.lineTo(cssWidth - padding.right, thresholdY);
    context.stroke();
    context.restore();
  }

  state.detection.pairEvents.forEach((pairEvent) => {
    const startX = xForTime(pairEvent.first.timeMs);
    const endX = xForTime(pairEvent.second.timeMs);
    context.save();
    context.fillStyle = "rgba(124, 58, 237, 0.08)";
    context.fillRect(startX, padding.top, endX - startX, chartHeight);
    context.strokeStyle = "rgba(124, 58, 237, 0.4)";
    context.lineWidth = 1.5;
    context.beginPath();
    context.moveTo(startX, yForAmplitude(pairEvent.first.amplitude));
    context.lineTo(endX, yForAmplitude(pairEvent.second.amplitude));
    context.stroke();
    context.restore();
  });

  drawSeries(context, state.amplitudes, xForTime, yForAmplitude, {
    strokeStyle: "rgba(79, 124, 255, 0.95)",
    fillStyle: "rgba(79, 124, 255, 0.12)",
    lineWidth: 1.8,
    fill: true
  }, chartHeight + padding.top);

  if (smoothed.length) {
    drawSeries(context, smoothed, xForTime, yForAmplitude, {
      strokeStyle: "#00a38c",
      fillStyle: null,
      lineWidth: 2.2,
      fill: false
    });
  }

  state.detection.acceptedHighs.forEach((highPoint, index) => {
    const x = xForTime(highPoint.timeMs);
    const y = yForAmplitude(highPoint.amplitude);
    const active = highPoint.timeMs <= state.currentTimeMs;
    context.beginPath();
    context.fillStyle = active ? "#d9485f" : "rgba(217, 72, 95, 0.35)";
    context.arc(x, y, active ? 5 : 4, 0, Math.PI * 2);
    context.fill();

    context.fillStyle = "rgba(17, 32, 59, 0.82)";
    context.font = "11px IBM Plex Mono";
    context.fillText(String(index + 1), x + 7, y - 8);
  });

  state.detection.pairEvents.forEach((pairEvent) => {
    const x = xForTime(pairEvent.second.timeMs);
    const y = yForAmplitude(pairEvent.second.amplitude);
    const active = pairEvent.completedAtMs <= state.currentTimeMs;
    context.beginPath();
    context.fillStyle = active ? "#7c3aed" : "rgba(124, 58, 237, 0.35)";
    context.arc(x, y, active ? 6 : 5, 0, Math.PI * 2);
    context.fill();
  });

  const playheadX = xForTime(state.currentTimeMs);
  context.save();
  context.strokeStyle = "#111111";
  context.lineWidth = 2;
  context.beginPath();
  context.moveTo(playheadX, padding.top);
  context.lineTo(playheadX, padding.top + chartHeight);
  context.stroke();
  context.restore();
}

function drawAxes(context, padding, chartWidth, chartHeight, cssWidth, cssHeight, durationMs, maxAmplitude) {
  context.save();
  context.strokeStyle = "rgba(17, 32, 59, 0.12)";
  context.lineWidth = 1;
  context.beginPath();
  context.moveTo(padding.left, padding.top);
  context.lineTo(padding.left, padding.top + chartHeight);
  context.lineTo(padding.left + chartWidth, padding.top + chartHeight);
  context.stroke();

  context.fillStyle = "rgba(17, 32, 59, 0.6)";
  context.font = "11px IBM Plex Mono";
  const horizontalMarkers = [0, 0.25, 0.5, 0.75, 1];
  horizontalMarkers.forEach((marker) => {
    const amplitude = maxAmplitude * marker;
    const y = padding.top + chartHeight - (chartHeight * marker);
    context.beginPath();
    context.moveTo(padding.left, y);
    context.lineTo(cssWidth - padding.right, y);
    context.strokeStyle = "rgba(17, 32, 59, 0.05)";
    context.stroke();
    context.fillText(amplitude.toFixed(2), 8, y + 4);
  });

  const timeMarkers = [0, 0.25, 0.5, 0.75, 1];
  timeMarkers.forEach((marker) => {
    const timeMs = durationMs * marker;
    const x = padding.left + (chartWidth * marker);
    context.beginPath();
    context.moveTo(x, padding.top);
    context.lineTo(x, padding.top + chartHeight);
    context.strokeStyle = "rgba(17, 32, 59, 0.05)";
    context.stroke();
    context.fillText(formatTime(timeMs), x - 18, cssHeight - 14);
  });
  context.restore();
}

function drawSeries(context, points, xForTime, yForAmplitude, styles, baselineY) {
  if (!points.length) {
    return;
  }

  context.save();
  context.lineWidth = styles.lineWidth;
  context.strokeStyle = styles.strokeStyle;
  context.beginPath();
  points.forEach((point, index) => {
    const x = xForTime(point.timeMs);
    const y = yForAmplitude(point.amplitude);
    if (index === 0) {
      context.moveTo(x, y);
    } else {
      context.lineTo(x, y);
    }
  });
  context.stroke();

  if (styles.fill && styles.fillStyle && Number.isFinite(baselineY)) {
    context.lineTo(xForTime(points[points.length - 1].timeMs), baselineY);
    context.lineTo(xForTime(points[0].timeMs), baselineY);
    context.closePath();
    context.fillStyle = styles.fillStyle;
    context.fill();
  }

  context.restore();
}

function renderStats() {
  const liveSnapshot = computeLiveSnapshot(state.currentTimeMs);
  refs.statHighPoints.textContent = String(liveSnapshot.highPointsDetected);
  refs.statPairs.textContent = String(liveSnapshot.pairsDetected);
  refs.statPending.textContent = liveSnapshot.pendingHigh ? `Yes @ ${formatTime(liveSnapshot.pendingHigh.timeMs)}` : "No";
  refs.statThreshold.textContent = (state.detection.threshold || 0).toFixed(4);
}

function renderEvents() {
  refs.eventList.innerHTML = "";

  if (!state.amplitudes.length) {
    const emptyItem = document.createElement("li");
    emptyItem.textContent = "Load a file to see detection events.";
    refs.eventList.appendChild(emptyItem);
    return;
  }

  const events = buildEventTimeline();
  if (!events.length) {
    const emptyItem = document.createElement("li");
    emptyItem.textContent = "No detection events yet for this algorithm.";
    refs.eventList.appendChild(emptyItem);
    return;
  }

  events.forEach((event) => {
    const item = document.createElement("li");
    if (event.timeMs <= state.currentTimeMs) {
      item.classList.add("active");
    }

    const tag = document.createElement("span");
    tag.className = `event-tag ${event.kind}`;
    tag.textContent = event.kind === "high" ? `High ${event.ordinal}` : `Pair ${event.ordinal}`;

    const title = document.createElement("div");
    title.textContent = event.label;

    const time = document.createElement("div");
    time.className = "event-time";
    time.textContent = `${formatTime(event.timeMs)}${event.detail ? ` | ${event.detail}` : ""}`;

    item.appendChild(tag);
    item.appendChild(title);
    item.appendChild(time);
    refs.eventList.appendChild(item);
  });
}

function renderDebug() {
  if (!state.amplitudes.length) {
    refs.debugOutput.textContent = "Load a recording to inspect detector output.";
    return;
  }

  const liveSnapshot = computeLiveSnapshot(state.currentTimeMs);
  refs.debugOutput.textContent = JSON.stringify({
    fileName: state.fileName,
    totalSamples: state.amplitudes.length,
    threshold: Number((state.detection.threshold || 0).toFixed(6)),
    acceptedHighs: state.detection.acceptedHighs.length,
    completedPairs: state.detection.pairEvents.length,
    currentTimeMs: Math.round(state.currentTimeMs),
    highPointsSoFar: liveSnapshot.highPointsDetected,
    pairsSoFar: liveSnapshot.pairsDetected,
    currentConfig: state.detection.config,
    firstHighs: state.detection.acceptedHighs.slice(0, 8),
    firstPairs: state.detection.pairEvents.slice(0, 6)
  }, null, 2);
}

function computeLiveSnapshot(playheadMs) {
  const seenHighs = state.detection.acceptedHighs.filter((highPoint) => highPoint.timeMs <= playheadMs);
  const seenPairs = state.detection.pairEvents.filter((pairEvent) => pairEvent.completedAtMs <= playheadMs);

  let pendingHigh = null;
  seenHighs.forEach((highPoint) => {
    if (!pendingHigh) {
      pendingHigh = highPoint;
      return;
    }

    if ((highPoint.timeMs - pendingHigh.timeMs) <= (state.detection.config.pairGapMs || 7000)) {
      pendingHigh = null;
    } else {
      pendingHigh = highPoint;
    }
  });

  return {
    highPointsDetected: seenHighs.length,
    pairsDetected: seenPairs.length,
    pendingHigh
  };
}

function buildEventTimeline() {
  const events = [];

  state.detection.acceptedHighs.forEach((highPoint, index) => {
    events.push({
      kind: "high",
      ordinal: index + 1,
      timeMs: highPoint.timeMs,
      label: `High point ${index + 1} accepted`,
      detail: `raw ${highPoint.amplitude.toFixed(4)} | smooth ${highPoint.smoothedAmplitude.toFixed(4)}`
    });
  });

  state.detection.pairEvents.forEach((pairEvent) => {
    events.push({
      kind: "pair",
      ordinal: pairEvent.pairNumber,
      timeMs: pairEvent.completedAtMs,
      label: `Pair ${pairEvent.pairNumber} completed`,
      detail: `gap ${formatTime(pairEvent.gapMs)}`
    });
  });

  return events.sort((left, right) => {
    if (left.timeMs === right.timeMs) {
      return left.kind === "high" ? -1 : 1;
    }
    return left.timeMs - right.timeMs;
  });
}

function getDurationMs() {
  if (!state.amplitudes.length) {
    return 0;
  }
  return state.amplitudes[state.amplitudes.length - 1].timeMs;
}

function formatTime(ms) {
  const safeMs = Math.max(0, Number(ms) || 0);
  const totalSeconds = safeMs / 1000;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${seconds.toFixed(1).padStart(4, "0")}`;
}

function setAlgorithmStatus(message, tone) {
  refs.algorithmStatus.textContent = message;
  refs.algorithmStatus.className = `algorithm-status ${tone}`;
}

function createEmptyDetectionResult() {
  return {
    config: {},
    threshold: 0,
    smoothed: [],
    acceptedHighs: [],
    pairEvents: [],
    pendingHigh: null
  };
}
