#!/usr/bin/env python3
"""Generate Smart Generation quality benchmark reports.

Direction 1 deliverable:
- Canonical scenario corpus support
- Metric extraction from generated camera/output artifacts
- Local/CI-ready report command with optional gate enforcement
"""

from __future__ import annotations

import argparse
import bisect
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


# MARK: - Data Models


@dataclass
class CameraSample:
    time: float
    x: float
    y: float
    zoom: float


@dataclass
class DynamicsSample:
    time: float
    pan_speed: float
    zoom_speed: float
    jerk: float


@dataclass
class ScenarioEvaluation:
    scenario_id: str
    status: str
    project_path: str | None
    metrics: dict[str, float | None]
    gate_results: dict[str, str]
    pass_all_gates: bool | None
    notes: list[str]


# MARK: - Helpers


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * (p / 100.0)
    lo = math.floor(rank)
    hi = math.ceil(rank)
    if lo == hi:
        return ordered[lo]
    weight = rank - lo
    return ordered[lo] * (1.0 - weight) + ordered[hi] * weight


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def resolve_path(candidate: str | None, manifest_path: Path, repo_root: Path) -> Path | None:
    if not candidate:
        return None

    path = Path(candidate)
    if path.is_absolute():
        return path

    repo_relative = repo_root / path
    if repo_relative.exists():
        return repo_relative

    manifest_relative = manifest_path.parent / path
    return manifest_relative


# MARK: - Camera Sampling


def clamp_center_for_zoom(x: float, y: float, zoom: float) -> tuple[float, float]:
    if zoom <= 1.0:
        return x, y
    half_ratio = 0.5 / max(zoom, 1.0)
    return (
        clamp(x, half_ratio, 1.0 - half_ratio),
        clamp(y, half_ratio, 1.0 - half_ratio),
    )


def spring_raw_value(zeta: float, omega: float, actual_time: float) -> float:
    if zeta >= 1.0:
        zo = zeta * omega
        decay = math.exp(-zo * actual_time)
        return 1.0 - (1.0 + zo * actual_time) * decay

    wd = omega * math.sqrt(max(1e-8, 1.0 - zeta * zeta))
    zo = zeta * omega
    decay = math.exp(-zo * actual_time)
    return 1.0 - decay * (math.cos(wd * actual_time) + (zo / wd) * math.sin(wd * actual_time))


def bezier_x(t: float, p1x: float, p2x: float) -> float:
    mt = 1.0 - t
    return 3 * mt * mt * t * p1x + 3 * mt * t * t * p2x + t * t * t


def bezier_y(t: float, p1y: float, p2y: float) -> float:
    mt = 1.0 - t
    return 3 * mt * mt * t * p1y + 3 * mt * t * t * p2y + t * t * t


def bezier_x_derivative(t: float, p1x: float, p2x: float) -> float:
    mt = 1.0 - t
    return 3 * mt * mt * p1x + 6 * mt * t * (p2x - p1x) + 3 * t * t * (1.0 - p2x)


def cubic_bezier_value(t: float, p1x: float, p1y: float, p2x: float, p2y: float) -> float:
    epsilon = 1e-4
    x = t
    for _ in range(10):
        x_value = bezier_x(x, p1x, p2x)
        diff = x_value - t
        if abs(diff) < epsilon:
            break
        derivative = bezier_x_derivative(x, p1x, p2x)
        if abs(derivative) < epsilon:
            break
        x -= diff / derivative

    return bezier_y(x, p1y, p2y)


def apply_easing(easing: dict[str, Any], progress: float, duration: float) -> float:
    t = clamp(progress, 0.0, 1.0)
    easing_type = easing.get("type", "linear")

    if easing_type == "linear":
        result = t
    elif easing_type == "easeIn":
        result = t * t
    elif easing_type == "easeOut":
        result = t * (2.0 - t)
    elif easing_type == "easeInOut":
        result = 2.0 * t * t if t < 0.5 else -1.0 + (4.0 - 2.0 * t) * t
    elif easing_type == "cubicBezier":
        result = cubic_bezier_value(
            t,
            float(easing.get("p1x", 0.25)),
            float(easing.get("p1y", 0.1)),
            float(easing.get("p2x", 0.25)),
            float(easing.get("p2y", 1.0)),
        )
    elif easing_type == "spring":
        zeta = float(easing.get("dampingRatio", 1.0))
        response = max(0.01, float(easing.get("response", 0.8)))
        omega = 2.0 * math.pi / response
        actual_time = t * max(duration, 0.001)
        raw = spring_raw_value(zeta, omega, actual_time)
        end_value = spring_raw_value(zeta, omega, max(duration, 0.001))
        result = t if abs(end_value) < 1e-6 else raw / end_value
    else:
        result = t

    return clamp(result, 0.0, 1.0)


def extract_camera_segments(project: dict[str, Any]) -> list[dict[str, Any]]:
    tracks = project.get("timeline", {}).get("tracks", [])
    for track in tracks:
        if track.get("type") == "transform":
            return list(track.get("data", {}).get("segments", []))

        data = track.get("data", {})
        if isinstance(data, dict) and "segments" in data:
            # Fallback for legacy/partial payloads where type may be absent.
            maybe_segments = data.get("segments")
            if isinstance(maybe_segments, list) and maybe_segments:
                first = maybe_segments[0]
                if isinstance(first, dict) and "startTransform" in first and "endTransform" in first:
                    return list(maybe_segments)
    return []


def sample_camera_from_segments(
    segments: list[dict[str, Any]],
    duration: float,
    sample_rate: float,
) -> list[CameraSample]:
    if duration <= 0:
        return []

    segments = sorted(segments, key=lambda seg: float(seg.get("startTime", 0.0)))
    dt = 1.0 / max(1.0, sample_rate)
    steps = max(1, int(math.ceil(duration / dt)))
    samples: list[CameraSample] = []
    segment_index = 0
    previous = CameraSample(time=0.0, x=0.5, y=0.5, zoom=1.0)

    for step in range(steps + 1):
        t = min(duration, step * dt)

        while segment_index + 1 < len(segments) and t >= float(segments[segment_index].get("endTime", 0.0)):
            segment_index += 1

        active_segment: dict[str, Any] | None = None
        if segments:
            candidate = segments[segment_index]
            start = float(candidate.get("startTime", 0.0))
            end = float(candidate.get("endTime", 0.0))
            is_last = segment_index == len(segments) - 1
            if start <= t < end or (is_last and start <= t <= end):
                active_segment = candidate

        if active_segment is None:
            samples.append(CameraSample(time=t, x=previous.x, y=previous.y, zoom=previous.zoom))
            continue

        start_t = float(active_segment.get("startTime", 0.0))
        end_t = float(active_segment.get("endTime", start_t + 0.001))
        segment_duration = max(0.001, end_t - start_t)
        raw_progress = (t - start_t) / segment_duration
        easing = active_segment.get("interpolation", {"type": "linear"})
        eased = apply_easing(easing, raw_progress, segment_duration)

        start_transform = active_segment.get("startTransform", {})
        end_transform = active_segment.get("endTransform", {})
        start_center = start_transform.get("center", {"x": 0.5, "y": 0.5})
        end_center = end_transform.get("center", {"x": 0.5, "y": 0.5})

        sx = float(start_center.get("x", 0.5))
        sy = float(start_center.get("y", 0.5))
        ex = float(end_center.get("x", 0.5))
        ey = float(end_center.get("y", 0.5))

        szoom = float(start_transform.get("zoom", 1.0))
        ezoom = float(end_transform.get("zoom", 1.0))

        zoom = szoom + (ezoom - szoom) * eased
        x = sx + (ex - sx) * eased
        y = sy + (ey - sy) * eased
        x, y = clamp_center_for_zoom(x, y, zoom)

        previous = CameraSample(time=t, x=x, y=y, zoom=zoom)
        samples.append(previous)

    return samples


def interpolate_camera_sample(samples: list[CameraSample], time: float) -> CameraSample:
    if not samples:
        return CameraSample(time=time, x=0.5, y=0.5, zoom=1.0)
    if time <= samples[0].time:
        return samples[0]
    if time >= samples[-1].time:
        return samples[-1]

    times = [sample.time for sample in samples]
    index = bisect.bisect_right(times, time)
    left = samples[index - 1]
    right = samples[index]
    dt = right.time - left.time
    if dt <= 0:
        return left

    alpha = (time - left.time) / dt
    zoom = left.zoom + (right.zoom - left.zoom) * alpha
    x = left.x + (right.x - left.x) * alpha
    y = left.y + (right.y - left.y) * alpha
    x, y = clamp_center_for_zoom(x, y, zoom)
    return CameraSample(time=time, x=x, y=y, zoom=zoom)


def sample_camera_from_continuous_transforms(
    transforms: list[dict[str, Any]],
    duration: float,
    sample_rate: float,
) -> list[CameraSample]:
    source_samples = sorted(
        [
            CameraSample(
                time=float(item.get("time", 0.0)),
                x=float(item.get("transform", {}).get("center", {}).get("x", 0.5)),
                y=float(item.get("transform", {}).get("center", {}).get("y", 0.5)),
                zoom=float(item.get("transform", {}).get("zoom", 1.0)),
            )
            for item in transforms
        ],
        key=lambda sample: sample.time,
    )
    if len(source_samples) < 2:
        return source_samples

    dt = 1.0 / max(1.0, sample_rate)
    steps = max(1, int(math.ceil(duration / dt)))
    output: list[CameraSample] = []
    for step in range(steps + 1):
        t = min(duration, step * dt)
        output.append(interpolate_camera_sample(source_samples, t))

    return output


def build_camera_samples(project: dict[str, Any], sample_rate: float) -> tuple[list[CameraSample], str, list[str]]:
    notes: list[str] = []

    timeline = project.get("timeline", {})
    duration = float(timeline.get("duration", project.get("media", {}).get("duration", 0.0)))
    if duration <= 0:
        return [], "none", ["Timeline duration is missing or zero"]

    continuous = timeline.get("continuousTransforms")
    if isinstance(continuous, list) and len(continuous) >= 2:
        notes.append("Camera sampled from timeline.continuousTransforms")
        return sample_camera_from_continuous_transforms(continuous, duration, sample_rate), "continuous", notes

    segments = extract_camera_segments(project)
    if segments:
        notes.append("Camera sampled from transform segments (interpolation-aware)")
        return sample_camera_from_segments(segments, duration, sample_rate), "segments", notes

    return [], "none", ["No camera track data available"]


# MARK: - Cursor Sampling


def extract_cursor_samples(project_path: Path, project: dict[str, Any]) -> tuple[list[tuple[float, float, float]], list[str]]:
    notes: list[str] = []
    interop = project.get("interop", {})
    streams = interop.get("streams", {})

    metadata_rel = interop.get("recordingMetadataPath", "recording/metadata.json")
    mouse_moves_rel = streams.get("mouseMoves", "recording/mousemoves-0.json")

    metadata_path = project_path / metadata_rel
    mouse_moves_path = project_path / mouse_moves_rel

    if not metadata_path.exists() or not mouse_moves_path.exists():
        notes.append("Cursor streams not found; cursor alignment metric skipped")
        return [], notes

    metadata = load_json(metadata_path)
    mouse_moves = load_json(mouse_moves_path)

    display = metadata.get("display", {})
    width = float(display.get("widthPx", 0.0))
    height = float(display.get("heightPx", 0.0))
    start_ms = int(metadata.get("processTimeStartMs", 0))

    if width <= 0 or height <= 0:
        notes.append("Invalid metadata display size; cursor alignment metric skipped")
        return [], notes

    samples: list[tuple[float, float, float]] = []
    for item in mouse_moves:
        process_ms = int(item.get("processTimeMs", 0))
        x = float(item.get("x", 0.0)) / width
        y = 1.0 - (float(item.get("y", 0.0)) / height)
        t = (process_ms - start_ms) / 1000.0
        samples.append((t, clamp(x, 0.0, 1.0), clamp(y, 0.0, 1.0)))

    samples.sort(key=lambda entry: entry[0])
    notes.append(f"Loaded {len(samples)} cursor samples from event stream")
    return samples, notes


def interpolate_cursor(samples: list[tuple[float, float, float]], time: float) -> tuple[float, float] | None:
    if not samples:
        return None

    times = [item[0] for item in samples]

    if time <= times[0]:
        return samples[0][1], samples[0][2]
    if time >= times[-1]:
        return samples[-1][1], samples[-1][2]

    index = bisect.bisect_right(times, time)
    left = samples[index - 1]
    right = samples[index]
    dt = right[0] - left[0]
    if dt <= 0:
        return left[1], left[2]

    alpha = (time - left[0]) / dt
    x = left[1] + (right[1] - left[1]) * alpha
    y = left[2] + (right[2] - left[2]) * alpha
    return x, y


# MARK: - Metrics


def compute_dynamics(samples: list[CameraSample]) -> list[DynamicsSample]:
    if len(samples) < 4:
        return []

    vx: list[float] = []
    vy: list[float] = []
    zoom_v: list[float] = []
    speeds: list[float] = []
    times: list[float] = []

    for index in range(1, len(samples)):
        prev = samples[index - 1]
        curr = samples[index]
        dt = max(1e-6, curr.time - prev.time)
        dvx = (curr.x - prev.x) / dt
        dvy = (curr.y - prev.y) / dt
        dz = (curr.zoom - prev.zoom) / dt

        vx.append(dvx)
        vy.append(dvy)
        zoom_v.append(abs(dz))
        speeds.append(math.hypot(dvx, dvy))
        times.append(curr.time)

    ax: list[float] = [0.0]
    ay: list[float] = [0.0]
    for index in range(1, len(vx)):
        dt = max(1e-6, times[index] - times[index - 1])
        ax.append((vx[index] - vx[index - 1]) / dt)
        ay.append((vy[index] - vy[index - 1]) / dt)

    jerk: list[float] = [0.0, 0.0]
    for index in range(2, len(ax)):
        dt = max(1e-6, times[index] - times[index - 1])
        jx = (ax[index] - ax[index - 1]) / dt
        jy = (ay[index] - ay[index - 1]) / dt
        jerk.append(math.hypot(jx, jy))

    while len(jerk) < len(times):
        jerk.append(0.0)

    dynamics: list[DynamicsSample] = []
    for index, t in enumerate(times):
        dynamics.append(
            DynamicsSample(
                time=t,
                pan_speed=speeds[index],
                zoom_speed=zoom_v[index],
                jerk=jerk[index],
            )
        )

    return dynamics


def nearest_dynamics(dynamics: list[DynamicsSample], time: float) -> DynamicsSample | None:
    if not dynamics:
        return None

    times = [sample.time for sample in dynamics]
    index = bisect.bisect_left(times, time)
    if index <= 0:
        return dynamics[0]
    if index >= len(dynamics):
        return dynamics[-1]

    before = dynamics[index - 1]
    after = dynamics[index]
    if abs(before.time - time) <= abs(after.time - time):
        return before
    return after


def detect_movement_episodes(
    camera: list[CameraSample],
    dynamics: list[DynamicsSample],
    dt: float,
) -> list[dict[str, int]]:
    if not dynamics:
        return []

    moving = [sample.pan_speed > 0.015 or sample.zoom_speed > 0.08 for sample in dynamics]
    episodes: list[dict[str, int]] = []
    index = 0
    settle_hold_count = max(3, int(round(0.20 / max(dt, 1e-3))))

    while index < len(moving):
        if not moving[index]:
            index += 1
            continue

        start = index
        while index + 1 < len(moving) and moving[index + 1]:
            index += 1
        end = index

        lookahead_count = max(1, int(round(0.25 / max(dt, 1e-3))))
        target_end = min(len(camera) - 1, end + 1 + lookahead_count)
        window = camera[end + 1:target_end + 1] if end + 1 <= target_end else [camera[end + 1]]

        if not window:
            index += 1
            continue

        target_x = sum(item.x for item in window) / len(window)
        target_y = sum(item.y for item in window) / len(window)
        target_zoom = sum(item.zoom for item in window) / len(window)

        settle_idx: int | None = None
        search_start = min(end + 1, len(camera) - 1)
        for candidate in range(search_start, len(camera) - settle_hold_count):
            local = camera[candidate]
            local_dyn = dynamics[min(candidate, len(dynamics) - 1)]
            dist = math.hypot(local.x - target_x, local.y - target_y)
            zoom_delta = abs(local.zoom - target_zoom)

            if not (
                dist <= 0.01
                and zoom_delta <= 0.02
                and local_dyn.pan_speed <= 0.012
                and local_dyn.zoom_speed <= 0.05
            ):
                continue

            stable = True
            for hold_offset in range(1, settle_hold_count):
                hold_idx = candidate + hold_offset
                hold_sample = camera[hold_idx]
                hold_dyn = dynamics[min(hold_idx, len(dynamics) - 1)]
                hold_dist = math.hypot(hold_sample.x - target_x, hold_sample.y - target_y)
                hold_zoom_delta = abs(hold_sample.zoom - target_zoom)
                if not (
                    hold_dist <= 0.01
                    and hold_zoom_delta <= 0.02
                    and hold_dyn.pan_speed <= 0.012
                    and hold_dyn.zoom_speed <= 0.05
                ):
                    stable = False
                    break

            if stable:
                settle_idx = candidate
                break

        episodes.append(
            {
                "start": start,
                "end": end,
                "settle": settle_idx if settle_idx is not None else -1,
                "target_end": target_end,
            }
        )
        index += 1

    return episodes


def compute_transition_settling_times(camera: list[CameraSample], episodes: list[dict[str, int]]) -> list[float]:
    settling_times: list[float] = []
    for episode in episodes:
        settle = episode["settle"]
        if settle < 0:
            continue

        start_time = camera[episode["start"]].time
        settle_time = camera[min(settle, len(camera) - 1)].time
        elapsed = max(0.0, settle_time - start_time)
        if elapsed > 0:
            settling_times.append(elapsed)

    return settling_times


def compute_overshoot_ratios(camera: list[CameraSample], episodes: list[dict[str, int]]) -> list[float]:
    ratios: list[float] = []

    for episode in episodes:
        start_idx = episode["start"]
        settle_idx = episode["settle"]
        target_end = episode["target_end"]
        if settle_idx < 0 or settle_idx <= start_idx:
            continue

        start = camera[start_idx]
        target_window = camera[episode["end"] + 1:target_end + 1]
        if not target_window:
            continue

        target_x = sum(item.x for item in target_window) / len(target_window)
        target_y = sum(item.y for item in target_window) / len(target_window)
        target_zoom = sum(item.zoom for item in target_window) / len(target_window)

        dx = target_x - start.x
        dy = target_y - start.y
        center_distance = math.hypot(dx, dy)

        ratio_center = 0.0
        if center_distance > 1e-5:
            ux = dx / center_distance
            uy = dy / center_distance
            max_projection = 0.0
            for item in camera[start_idx:settle_idx + 1]:
                projection = (item.x - start.x) * ux + (item.y - start.y) * uy
                if projection > max_projection:
                    max_projection = projection
            overshoot = max(0.0, max_projection - center_distance)
            ratio_center = overshoot / center_distance

        zoom_delta = target_zoom - start.zoom
        ratio_zoom = 0.0
        if abs(zoom_delta) > 1e-4:
            zoom_values = [item.zoom for item in camera[start_idx:settle_idx + 1]]
            if zoom_delta > 0:
                overshoot_zoom = max(0.0, max(zoom_values) - target_zoom)
            else:
                overshoot_zoom = max(0.0, target_zoom - min(zoom_values))
            ratio_zoom = overshoot_zoom / abs(zoom_delta)

        ratio = max(ratio_center, ratio_zoom)
        ratios.append(ratio)

    return ratios


def compute_cursor_alignment_error(
    camera: list[CameraSample],
    cursor_samples: list[tuple[float, float, float]],
) -> list[float]:
    if not camera or not cursor_samples:
        return []

    errors: list[float] = []
    for sample in camera:
        cursor = interpolate_cursor(cursor_samples, sample.time)
        if cursor is None:
            continue
        cursor_x, cursor_y = cursor

        half_width = 0.5 / max(sample.zoom, 1.0)
        dx = abs(cursor_x - sample.x) / max(half_width, 1e-6)
        dy = abs(cursor_y - sample.y) / max(half_width, 1e-6)
        normalized_error = math.hypot(dx, dy) / math.sqrt(2.0)
        errors.append(normalized_error)

    return errors


def compute_readability_retention_score(
    project: dict[str, Any],
    camera: list[CameraSample],
    dynamics: list[DynamicsSample],
) -> float | None:
    frame_analysis = project.get("frameAnalysisCache", [])
    if not camera:
        return None

    candidates: list[dict[str, Any]] = []
    if isinstance(frame_analysis, list):
        candidates = [
            item
            for item in frame_analysis
            if isinstance(item, dict)
            and not bool(item.get("isScrolling", False))
            and float(item.get("changeAmount", 1.0)) < 0.12
            and float(item.get("similarity", 0.0)) > 0.85
        ]
        if not candidates:
            candidates = [
                item
                for item in frame_analysis
                if isinstance(item, dict)
                and not bool(item.get("isScrolling", False))
                and float(item.get("changeAmount", 1.0)) < 0.18
            ]

    if not candidates:
        # Fallback: uniform sampling every ~1 second from camera samples.
        duration = camera[-1].time
        sample_count = max(1, int(duration))
        candidates = [{"time": (duration / sample_count) * index} for index in range(sample_count + 1)]

    scores: list[float] = []
    for frame in candidates:
        t = float(frame.get("time", 0.0))
        camera_state = interpolate_camera_sample(camera, t)
        dynamic_state = nearest_dynamics(dynamics, t)

        pan_speed = dynamic_state.pan_speed if dynamic_state else 0.0
        jerk = dynamic_state.jerk if dynamic_state else 0.0

        zoom_component = clamp((camera_state.zoom - 1.0) / 0.8, 0.0, 1.0)
        stability_component = 1.0 - clamp(pan_speed / 0.25, 0.0, 1.0)
        smoothness_component = 1.0 - clamp(jerk / 20.0, 0.0, 1.0)

        score = (
            0.50 * zoom_component
            + 0.35 * stability_component
            + 0.15 * smoothness_component
        )
        scores.append(clamp(score, 0.0, 1.0))

    if not scores:
        return None
    return sum(scores) / len(scores)


def evaluate_metrics(
    project: dict[str, Any],
    project_path: Path,
    sample_rate: float,
) -> tuple[dict[str, float | None], list[str]]:
    notes: list[str] = []

    camera, camera_source, camera_notes = build_camera_samples(project, sample_rate)
    notes.extend(camera_notes)
    if not camera:
        return {
            "transition_settling_time_p95_sec": None,
            "overshoot_ratio_p95": None,
            "camera_jerk_p95": None,
            "camera_jerk_p99": None,
            "cursor_camera_alignment_error_p95": None,
            "text_readability_retention_score": None,
        }, notes

    dt = 1.0 / max(1.0, sample_rate)
    dynamics = compute_dynamics(camera)
    episodes = detect_movement_episodes(camera, dynamics, dt)

    settling_times = compute_transition_settling_times(camera, episodes)
    overshoot_ratios = compute_overshoot_ratios(camera, episodes)
    jerk_values = [sample.jerk for sample in dynamics if sample.jerk > 0]

    cursor_samples, cursor_notes = extract_cursor_samples(project_path, project)
    notes.extend(cursor_notes)
    alignment_errors = compute_cursor_alignment_error(camera, cursor_samples)

    readability_score = compute_readability_retention_score(project, camera, dynamics)

    if camera_source == "segments" and not episodes:
        notes.append("No movement episodes detected in segment track")

    metrics: dict[str, float | None] = {
        "transition_settling_time_p95_sec": percentile(settling_times, 95),
        "overshoot_ratio_p95": percentile(overshoot_ratios, 95),
        "camera_jerk_p95": percentile(jerk_values, 95),
        "camera_jerk_p99": percentile(jerk_values, 99),
        "cursor_camera_alignment_error_p95": percentile(alignment_errors, 95),
        "text_readability_retention_score": readability_score,
    }

    notes.append(
        f"Computed from {len(camera)} camera samples, {len(dynamics)} dynamics samples, {len(episodes)} movement episodes"
    )

    return metrics, notes


# MARK: - Gates


def compare_metric(value: float, operator: str, threshold: float) -> bool:
    if operator == "<=":
        return value <= threshold
    if operator == "<":
        return value < threshold
    if operator == ">=":
        return value >= threshold
    if operator == ">":
        return value > threshold
    raise ValueError(f"Unsupported operator: {operator}")


def evaluate_gates(metrics: dict[str, float | None], gates: dict[str, Any]) -> tuple[dict[str, str], bool | None]:
    gate_definitions = gates.get("metricGates", {})
    results: dict[str, str] = {}
    has_failure = False
    has_evaluated = False

    for metric_name, gate in gate_definitions.items():
        value = metrics.get(metric_name)
        if value is None:
            results[metric_name] = "insufficient_data"
            continue

        has_evaluated = True
        operator = gate.get("operator", "<=")
        threshold = float(gate.get("threshold", 0.0))
        passed = compare_metric(float(value), operator, threshold)
        results[metric_name] = "pass" if passed else "fail"
        if not passed:
            has_failure = True

    if not has_evaluated:
        return results, None

    return results, not has_failure


# MARK: - Report Formatting


def format_metric_value(value: float | None) -> str:
    if value is None:
        return "n/a"
    if abs(value) >= 100:
        return f"{value:.2f}"
    if abs(value) >= 10:
        return f"{value:.3f}"
    return f"{value:.4f}"


def to_markdown_report(
    evaluations: list[ScenarioEvaluation],
    gates: dict[str, Any],
    timestamp: str,
) -> str:
    lines: list[str] = []
    lines.append("# Smart Generation Quality Report")
    lines.append("")
    lines.append(f"- Generated at: `{timestamp}`")
    lines.append(f"- Gate mode: `{gates.get('mode', 'non_blocking')}`")
    lines.append("")

    headers = [
        "Scenario",
        "Status",
        "Settling p95 (s)",
        "Overshoot p95",
        "Jerk p95",
        "Jerk p99",
        "Cursor Align p95",
        "Readability",
        "Gate",
    ]
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("|" + "---|" * len(headers))

    for evaluation in evaluations:
        metrics = evaluation.metrics
        row = [
            evaluation.scenario_id,
            evaluation.status,
            format_metric_value(metrics.get("transition_settling_time_p95_sec")),
            format_metric_value(metrics.get("overshoot_ratio_p95")),
            format_metric_value(metrics.get("camera_jerk_p95")),
            format_metric_value(metrics.get("camera_jerk_p99")),
            format_metric_value(metrics.get("cursor_camera_alignment_error_p95")),
            format_metric_value(metrics.get("text_readability_retention_score")),
            "n/a" if evaluation.pass_all_gates is None else ("pass" if evaluation.pass_all_gates else "fail"),
        ]
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines) + "\n"


def print_console_summary(evaluations: list[ScenarioEvaluation], gates: dict[str, Any]) -> None:
    print("Smart Generation Quality Report")
    print("=" * 32)
    print(f"Gate mode: {gates.get('mode', 'non_blocking')}")

    evaluated = [item for item in evaluations if item.status == "evaluated"]
    passed = [item for item in evaluated if item.pass_all_gates is True]
    failed = [item for item in evaluated if item.pass_all_gates is False]
    skipped = [item for item in evaluations if item.status != "evaluated"]

    print(f"Evaluated: {len(evaluated)} | Passed: {len(passed)} | Failed: {len(failed)} | Skipped: {len(skipped)}")

    for item in evaluations:
        gate_result = "n/a"
        if item.pass_all_gates is True:
            gate_result = "pass"
        elif item.pass_all_gates is False:
            gate_result = "fail"

        print(f"- {item.scenario_id}: {item.status}, gate={gate_result}")
        for metric_name, metric_value in item.metrics.items():
            print(f"  - {metric_name}: {format_metric_value(metric_value)}")

        if item.notes:
            print(f"  - notes: {'; '.join(item.notes)}")


def build_json_report(
    evaluations: list[ScenarioEvaluation],
    gates: dict[str, Any],
    manifest_path: Path,
) -> dict[str, Any]:
    evaluated = [item for item in evaluations if item.status == "evaluated"]
    gate_checked = [item for item in evaluated if item.pass_all_gates is not None]
    passed = [item for item in gate_checked if item.pass_all_gates is True]

    pass_rate = (len(passed) / len(gate_checked)) if gate_checked else None

    return {
        "manifest": str(manifest_path),
        "gateMode": gates.get("mode", "non_blocking"),
        "passRateTarget": gates.get("passRateTarget", 0.8),
        "summary": {
            "total": len(evaluations),
            "evaluated": len(evaluated),
            "skipped": len(evaluations) - len(evaluated),
            "gateChecked": len(gate_checked),
            "gatePassed": len(passed),
            "passRate": pass_rate,
        },
        "scenarios": [
            {
                "scenarioId": item.scenario_id,
                "status": item.status,
                "projectPath": item.project_path,
                "metrics": item.metrics,
                "gateResults": item.gate_results,
                "passAllGates": item.pass_all_gates,
                "notes": item.notes,
            }
            for item in evaluations
        ],
    }


# MARK: - Main


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Smart Generation quality benchmark report")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("private-docs/benchmarks/smart-generation/scenario-corpus.json"),
        help="Path to scenario corpus manifest JSON",
    )
    parser.add_argument(
        "--gates",
        type=Path,
        default=Path("private-docs/benchmarks/smart-generation/quality-gates.json"),
        help="Path to quality gates JSON",
    )
    parser.add_argument(
        "--sample-rate",
        type=float,
        default=60.0,
        help="Camera sampling rate in Hz",
    )
    parser.add_argument(
        "--output-json",
        type=Path,
        default=None,
        help="Optional path to write machine-readable report JSON",
    )
    parser.add_argument(
        "--output-md",
        type=Path,
        default=None,
        help="Optional path to write markdown report",
    )
    parser.add_argument(
        "--scenario",
        action="append",
        default=[],
        help="Scenario ID to evaluate (repeatable). Default: all ready scenarios",
    )
    parser.add_argument(
        "--enforce-gates",
        action="store_true",
        help="Exit with non-zero code when gate failures exist",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path.cwd()

    manifest_path = args.manifest if args.manifest.is_absolute() else (repo_root / args.manifest)
    gates_path = args.gates if args.gates.is_absolute() else (repo_root / args.gates)

    manifest = load_json(manifest_path)
    gates = load_json(gates_path)

    selected_ids = set(args.scenario)
    scenarios = manifest.get("scenarios", [])

    evaluations: list[ScenarioEvaluation] = []

    for scenario in scenarios:
        scenario_id = str(scenario.get("id", "unknown"))
        if selected_ids and scenario_id not in selected_ids:
            continue

        status = str(scenario.get("status", "planned"))
        project_candidate = scenario.get("projectPath")
        project_path = resolve_path(project_candidate, manifest_path, repo_root)

        if status != "ready":
            evaluations.append(
                ScenarioEvaluation(
                    scenario_id=scenario_id,
                    status="skipped",
                    project_path=str(project_path) if project_path else None,
                    metrics={
                        "transition_settling_time_p95_sec": None,
                        "overshoot_ratio_p95": None,
                        "camera_jerk_p95": None,
                        "camera_jerk_p99": None,
                        "cursor_camera_alignment_error_p95": None,
                        "text_readability_retention_score": None,
                    },
                    gate_results={},
                    pass_all_gates=None,
                    notes=["Scenario status is not ready"],
                )
            )
            continue

        if project_path is None or not project_path.exists():
            evaluations.append(
                ScenarioEvaluation(
                    scenario_id=scenario_id,
                    status="skipped",
                    project_path=str(project_path) if project_path else None,
                    metrics={
                        "transition_settling_time_p95_sec": None,
                        "overshoot_ratio_p95": None,
                        "camera_jerk_p95": None,
                        "camera_jerk_p99": None,
                        "cursor_camera_alignment_error_p95": None,
                        "text_readability_retention_score": None,
                    },
                    gate_results={},
                    pass_all_gates=None,
                    notes=["Project path does not exist"],
                )
            )
            continue

        project_json = project_path / "project.json"
        if not project_json.exists():
            evaluations.append(
                ScenarioEvaluation(
                    scenario_id=scenario_id,
                    status="skipped",
                    project_path=str(project_path),
                    metrics={
                        "transition_settling_time_p95_sec": None,
                        "overshoot_ratio_p95": None,
                        "camera_jerk_p95": None,
                        "camera_jerk_p99": None,
                        "cursor_camera_alignment_error_p95": None,
                        "text_readability_retention_score": None,
                    },
                    gate_results={},
                    pass_all_gates=None,
                    notes=["project.json missing in scenario package"],
                )
            )
            continue

        project = load_json(project_json)
        metrics, notes = evaluate_metrics(project, project_path, args.sample_rate)
        gate_results, pass_all = evaluate_gates(metrics, gates)

        evaluations.append(
            ScenarioEvaluation(
                scenario_id=scenario_id,
                status="evaluated",
                project_path=str(project_path),
                metrics=metrics,
                gate_results=gate_results,
                pass_all_gates=pass_all,
                notes=notes,
            )
        )

    print_console_summary(evaluations, gates)

    report_json = build_json_report(evaluations, gates, manifest_path)

    if args.output_json:
        output_json = args.output_json if args.output_json.is_absolute() else (repo_root / args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(json.dumps(report_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Wrote JSON report: {output_json}")

    if args.output_md:
        from datetime import datetime, timezone

        timestamp = datetime.now(timezone.utc).isoformat()
        markdown = to_markdown_report(evaluations, gates, timestamp)
        output_md = args.output_md if args.output_md.is_absolute() else (repo_root / args.output_md)
        output_md.parent.mkdir(parents=True, exist_ok=True)
        output_md.write_text(markdown, encoding="utf-8")
        print(f"Wrote Markdown report: {output_md}")

    failed = [item for item in evaluations if item.status == "evaluated" and item.pass_all_gates is False]
    if args.enforce_gates and failed:
        print(f"Gate enforcement failed: {len(failed)} scenario(s) did not meet thresholds")
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
