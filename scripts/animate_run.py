#!/usr/bin/env python3
"""Animate simulator state.csv traces.

Outputs animated GIFs using matplotlib + Pillow. Optionally also writes an
interactive HTML replay that can be opened directly in a browser.
"""

import argparse
import csv
import json
import math
import os
from collections import defaultdict
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")

import matplotlib.animation as animation
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401


COLORS = [
    "#1f77b4",
    "#d62728",
    "#2ca02c",
    "#9467bd",
    "#ff7f0e",
    "#17becf",
    "#8c564b",
    "#e377c2",
]


def load_states(path):
    by_time = defaultdict(dict)
    traces = defaultdict(list)
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            t = round(float(row["time"]), 6)
            uav_id = int(row["uav_id"])
            point = {
                "time": t,
                "id": uav_id,
                "x": float(row["x"]),
                "y": float(row["y"]),
                "z": float(row["z"]),
                "level": int(row["level"]),
                "active": row["active"].lower() == "true",
                "reached": row["reached"].lower() == "true",
            }
            by_time[t][uav_id] = point
            traces[uav_id].append(point)
    times = sorted(by_time)
    uav_ids = sorted(traces)
    return times, uav_ids, by_time, dict(traces)


def padded_bounds(values, min_pad=1.0):
    low = min(values)
    high = max(values)
    if math.isclose(low, high):
        return low - min_pad, high + min_pad
    pad = max(min_pad, (high - low) * 0.08)
    return low - pad, high + pad


def nearest_frame_step(times, target_dt):
    if len(times) < 2:
        return 1
    source_dt = min(
        b - a for a, b in zip(times, times[1:]) if b > a + 1e-9
    )
    return max(1, int(round(target_dt / source_dt)))


def frame_indices_for(times, frame_dt):
    frame_step = nearest_frame_step(times, frame_dt)
    frame_indices = list(range(0, len(times), frame_step))
    if frame_indices[-1] != len(times) - 1:
        frame_indices.append(len(times) - 1)
    return frame_indices


def setup_level_lines(ax, z_values, xmin, xmax):
    levels = sorted(set(round(z, 6) for z in z_values))
    for z in levels:
        ax.axhline(z, color="#d8d8d8", linewidth=0.9, linestyle="--")
        ax.text(xmax, z, f" z={z:g}", va="center", ha="right", fontsize=8, color="#606060")


def write_dashboard_gif(times, uav_ids, by_time, traces, out_path, fps, frame_dt, trail):
    frame_indices = frame_indices_for(times, frame_dt)

    xs = [p["x"] for trace in traces.values() for p in trace]
    ys = [p["y"] for trace in traces.values() for p in trace]
    zs = [p["z"] for trace in traces.values() for p in trace]
    xmin, xmax = padded_bounds(xs)
    ymin, ymax = padded_bounds(ys)
    zmin, zmax = padded_bounds(zs, min_pad=0.5)

    fig, (ax_xy, ax_xz) = plt.subplots(1, 2, figsize=(14, 6))
    ax_xy.set_title("Top view: XY avoidance")
    ax_xy.set_aspect("equal", adjustable="box")
    ax_xy.set_xlim(xmin, xmax)
    ax_xy.set_ylim(ymin, ymax)
    ax_xy.set_xlabel("x")
    ax_xy.set_ylabel("y")
    ax_xy.grid(True, color="#dddddd", linewidth=0.8)

    ax_xz.set_title("Front view: XZ layer changes")
    ax_xz.set_xlim(xmin, xmax)
    ax_xz.set_ylim(zmin, zmax)
    ax_xz.set_xlabel("x")
    ax_xz.set_ylabel("z")
    ax_xz.grid(True, color="#dddddd", linewidth=0.8)
    setup_level_lines(ax_xz, zs, xmin, xmax)

    xy_all_paths = {}
    xy_trails = {}
    xy_markers = {}
    xy_labels = {}
    xz_all_paths = {}
    xz_trails = {}
    xz_markers = {}
    xz_labels = {}
    for idx, uav_id in enumerate(uav_ids):
        color = COLORS[idx % len(COLORS)]
        full_x = [p["x"] for p in traces[uav_id]]
        full_y = [p["y"] for p in traces[uav_id]]
        full_z = [p["z"] for p in traces[uav_id]]

        (xy_all,) = ax_xy.plot(full_x, full_y, color=color, linewidth=1.0, alpha=0.15)
        (xy_trail,) = ax_xy.plot([], [], color=color, linewidth=2.3)
        xy_marker = ax_xy.scatter([], [], s=85, color=color, edgecolors="white", linewidths=1.2, zorder=5)
        xy_label = ax_xy.text(0, 0, "", color=color, fontsize=10, weight="bold")

        (xz_all,) = ax_xz.plot(full_x, full_z, color=color, linewidth=1.0, alpha=0.15)
        (xz_trail,) = ax_xz.plot([], [], color=color, linewidth=2.3)
        xz_marker = ax_xz.scatter([], [], s=85, color=color, edgecolors="white", linewidths=1.2, zorder=5)
        xz_label = ax_xz.text(0, 0, "", color=color, fontsize=10, weight="bold")

        xy_all_paths[uav_id] = xy_all
        xy_trails[uav_id] = xy_trail
        xy_markers[uav_id] = xy_marker
        xy_labels[uav_id] = xy_label
        xz_all_paths[uav_id] = xz_all
        xz_trails[uav_id] = xz_trail
        xz_markers[uav_id] = xz_marker
        xz_labels[uav_id] = xz_label

    title = fig.suptitle("")

    def update(frame_index):
        t = times[frame_index]
        start_t = max(times[0], t - trail)
        artists = [title]
        for uav_id in uav_ids:
            trace = [p for p in traces[uav_id] if start_t <= p["time"] <= t]
            if trace:
                xy_trails[uav_id].set_data(
                    [p["x"] for p in trace], [p["y"] for p in trace]
                )
                xz_trails[uav_id].set_data(
                    [p["x"] for p in trace], [p["z"] for p in trace]
                )
            point = by_time[t].get(uav_id)
            if point is None:
                continue
            xy_markers[uav_id].set_offsets([[point["x"], point["y"]]])
            xy_labels[uav_id].set_position((point["x"], point["y"]))
            xy_labels[uav_id].set_text(f"  {uav_id}")
            xz_markers[uav_id].set_offsets([[point["x"], point["z"]]])
            xz_labels[uav_id].set_position((point["x"], point["z"]))
            xz_labels[uav_id].set_text(f"  {uav_id}")
            artists.extend([
                xy_trails[uav_id],
                xy_markers[uav_id],
                xy_labels[uav_id],
                xz_trails[uav_id],
                xz_markers[uav_id],
                xz_labels[uav_id],
            ])
        title.set_text(f"UAV replay  t={t:.2f}s")
        return artists

    fig.tight_layout(rect=[0, 0.07, 1, 0.93])
    ani = animation.FuncAnimation(
        fig,
        update,
        frames=frame_indices,
        interval=1000 / fps,
        blit=False,
    )
    ani.save(out_path, writer=animation.PillowWriter(fps=fps))
    plt.close(fig)


def write_3d_gif(times, uav_ids, by_time, traces, out_path, fps, frame_dt, trail):
    frame_indices = frame_indices_for(times, frame_dt)
    xs = [p["x"] for trace in traces.values() for p in trace]
    ys = [p["y"] for trace in traces.values() for p in trace]
    zs = [p["z"] for trace in traces.values() for p in trace]
    xmin, xmax = padded_bounds(xs)
    ymin, ymax = padded_bounds(ys)
    zmin, zmax = padded_bounds(zs, min_pad=0.5)

    fig = plt.figure(figsize=(9, 7))
    ax = fig.add_subplot(111, projection="3d")
    ax.set_xlim(xmin, xmax)
    ax.set_ylim(ymin, ymax)
    ax.set_zlim(zmin, zmax)
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_zlabel("z")
    ax.view_init(elev=24, azim=-58)

    all_paths = {}
    trails = {}
    markers = {}
    labels = {}
    for idx, uav_id in enumerate(uav_ids):
        color = COLORS[idx % len(COLORS)]
        full_x = [p["x"] for p in traces[uav_id]]
        full_y = [p["y"] for p in traces[uav_id]]
        full_z = [p["z"] for p in traces[uav_id]]
        (all_line,) = ax.plot(full_x, full_y, full_z, color=color, linewidth=1.0, alpha=0.14)
        (trail_line,) = ax.plot([], [], [], color=color, linewidth=2.4)
        marker = ax.scatter([], [], [], s=80, color=color, edgecolors="white", linewidths=1.0)
        label = ax.text(0, 0, 0, "", color=color, fontsize=10, weight="bold")
        all_paths[uav_id] = all_line
        trails[uav_id] = trail_line
        markers[uav_id] = marker
        labels[uav_id] = label

    title = ax.set_title("")

    def update(frame_index):
        t = times[frame_index]
        start_t = max(times[0], t - trail)
        artists = [title]
        for uav_id in uav_ids:
            trace = [p for p in traces[uav_id] if start_t <= p["time"] <= t]
            if trace:
                trails[uav_id].set_data_3d(
                    [p["x"] for p in trace],
                    [p["y"] for p in trace],
                    [p["z"] for p in trace],
                )
            point = by_time[t].get(uav_id)
            if point is None:
                continue
            markers[uav_id]._offsets3d = ([point["x"]], [point["y"]], [point["z"]])
            labels[uav_id].set_position((point["x"], point["y"]))
            labels[uav_id].set_3d_properties(point["z"])
            labels[uav_id].set_text(f" UAV {uav_id}")
            artists.extend([trails[uav_id], markers[uav_id], labels[uav_id]])
        title.set_text(f"3D UAV replay  t={t:.2f}s")
        return artists

    ani = animation.FuncAnimation(
        fig,
        update,
        frames=frame_indices,
        interval=1000 / fps,
        blit=False,
    )
    ani.save(out_path, writer=animation.PillowWriter(fps=fps))
    plt.close(fig)


def write_html(times, uav_ids, by_time, traces, out_path):
    frames = [
        {
            "time": t,
            "uavs": [by_time[t][uav_id] for uav_id in uav_ids if uav_id in by_time[t]],
        }
        for t in times
    ]
    xs = [p["x"] for trace in traces.values() for p in trace]
    ys = [p["y"] for trace in traces.values() for p in trace]
    zs = [p["z"] for trace in traces.values() for p in trace]
    xmin, xmax = padded_bounds(xs)
    ymin, ymax = padded_bounds(ys)
    zmin, zmax = padded_bounds(zs, min_pad=0.5)
    payload = {
        "frames": frames,
        "uavIds": uav_ids,
        "colors": COLORS,
        "bounds": {"xmin": xmin, "xmax": xmax, "ymin": ymin, "ymax": ymax, "zmin": zmin, "zmax": zmax},
    }
    html = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>UAV Replay</title>
<style>
body {{ margin: 0; font-family: Arial, sans-serif; color: #202020; background: #f5f5f5; }}
.bar {{ display: flex; gap: 12px; align-items: center; padding: 12px 16px; background: white; border-bottom: 1px solid #ddd; }}
button {{ padding: 6px 12px; }}
input[type=range] {{ flex: 1; }}
#wrap {{ display: grid; grid-template-columns: minmax(0, 1fr) 300px; gap: 0; height: calc(100vh - 54px); }}
#views {{ display: grid; grid-template-columns: 1fr 1fr; min-width: 0; }}
canvas {{ width: 100%; height: 100%; background: white; display: block; }}
#side {{ padding: 16px; border-left: 1px solid #ddd; background: #fafafa; font-size: 14px; }}
.row {{ margin: 0 0 8px; }}
</style>
</head>
<body>
<div class="bar">
  <button id="play">Pause</button>
  <input id="scrub" type="range" min="0" max="0" value="0">
  <span id="clock"></span>
</div>
<div id="wrap">
  <div id="views">
    <canvas id="xy"></canvas>
    <canvas id="xz"></canvas>
  </div>
  <div id="side"></div>
</div>
<script>
const data = {json.dumps(payload)};
const xyCanvas = document.getElementById('xy');
const xzCanvas = document.getElementById('xz');
const xyCtx = xyCanvas.getContext('2d');
const xzCtx = xzCanvas.getContext('2d');
const scrub = document.getElementById('scrub');
const play = document.getElementById('play');
const clock = document.getElementById('clock');
const side = document.getElementById('side');
let frame = 0;
let playing = true;
scrub.max = data.frames.length - 1;
function resize() {{
  const dpr = window.devicePixelRatio || 1;
  [xyCanvas, xzCanvas].forEach(c => {{
    c.width = Math.floor(c.clientWidth * dpr);
    c.height = Math.floor(c.clientHeight * dpr);
  }});
  xyCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  xzCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  draw();
}}
function project(canvas, x, y, xmin, xmax, ymin, ymax) {{
  const m = 50, w = canvas.clientWidth, h = canvas.clientHeight;
  return [
    m + (x - xmin) / (xmax - xmin) * (w - 2*m),
    h - m - (y - ymin) / (ymax - ymin) * (h - 2*m)
  ];
}}
function projectXY(x, y) {{
  const b = data.bounds;
  return project(xyCanvas, x, y, b.xmin, b.xmax, b.ymin, b.ymax);
}}
function projectXZ(x, z) {{
  const b = data.bounds;
  return project(xzCanvas, x, z, b.xmin, b.xmax, b.zmin, b.zmax);
}}
function clearPanel(ctx, canvas, title) {{
  const w = canvas.clientWidth, h = canvas.clientHeight;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#ddd';
  ctx.strokeRect(50, 50, w - 100, h - 100);
  ctx.fillStyle = '#202020';
  ctx.font = '16px Arial';
  ctx.fillText(title, 20, 28);
}}
function draw() {{
  clearPanel(xyCtx, xyCanvas, 'Top view: XY avoidance');
  clearPanel(xzCtx, xzCanvas, 'Front view: XZ layer changes');
  const levels = [...new Set(data.frames.flatMap(f => f.uavs.map(u => u.z.toFixed(6))))].map(Number).sort((a,b) => a-b);
  levels.forEach(z => {{
    const [x1, y1] = projectXZ(data.bounds.xmin, z);
    const [x2, y2] = projectXZ(data.bounds.xmax, z);
    xzCtx.strokeStyle = '#d8d8d8';
    xzCtx.setLineDash([5, 5]);
    xzCtx.beginPath();
    xzCtx.moveTo(x1, y1);
    xzCtx.lineTo(x2, y2);
    xzCtx.stroke();
    xzCtx.setLineDash([]);
  }});
  data.uavIds.forEach((id, idx) => {{
    const color = data.colors[idx % data.colors.length];
    xyCtx.strokeStyle = color;
    xzCtx.strokeStyle = color;
    xyCtx.lineWidth = 2;
    xzCtx.lineWidth = 2;
    xyCtx.globalAlpha = 0.22;
    xzCtx.globalAlpha = 0.22;
    xyCtx.beginPath();
    xzCtx.beginPath();
    let startedXY = false;
    let startedXZ = false;
    for (let i = 0; i <= frame; i++) {{
      const p = data.frames[i].uavs.find(u => u.id === id);
      if (!p) continue;
      const [xyX, xyY] = projectXY(p.x, p.y);
      const [xzX, xzY] = projectXZ(p.x, p.z);
      if (!startedXY) {{ xyCtx.moveTo(xyX, xyY); startedXY = true; }} else xyCtx.lineTo(xyX, xyY);
      if (!startedXZ) {{ xzCtx.moveTo(xzX, xzY); startedXZ = true; }} else xzCtx.lineTo(xzX, xzY);
    }}
    xyCtx.stroke();
    xzCtx.stroke();
    xyCtx.globalAlpha = 1;
    xzCtx.globalAlpha = 1;
  }});
  const f = data.frames[frame];
  side.innerHTML = `<h2>t=${{f.time.toFixed(2)}}s</h2>`;
  f.uavs.forEach((u, idx) => {{
    const color = data.colors[idx % data.colors.length];
    const [xyX, xyY] = projectXY(u.x, u.y);
    const [xzX, xzY] = projectXZ(u.x, u.z);
    [ [xyCtx, xyX, xyY], [xzCtx, xzX, xzY] ].forEach(([ctx, x, y]) => {{
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#111';
      ctx.fillText(`UAV ${{u.id}}`, x + 10, y - 10);
    }});
    side.innerHTML += `<div class="row" style="color:${{color}}"><b>UAV ${{u.id}}</b>: x=${{u.x.toFixed(2)}}, y=${{u.y.toFixed(2)}}, z=${{u.z.toFixed(2)}}, level=${{u.level}}</div>`;
  }});
  scrub.value = frame;
  clock.textContent = `frame ${{frame + 1}} / ${{data.frames.length}}`;
}}
function tick() {{
  if (playing) frame = (frame + 1) % data.frames.length;
  draw();
}}
play.onclick = () => {{ playing = !playing; play.textContent = playing ? 'Pause' : 'Play'; }};
scrub.oninput = () => {{ frame = Number(scrub.value); playing = false; play.textContent = 'Play'; draw(); }};
window.onresize = resize;
resize();
setInterval(tick, 50);
</script>
</body>
</html>
"""
    out_path.write_text(html)


def main():
    parser = argparse.ArgumentParser(description="Create animated replay from run_async output")
    parser.add_argument("run_dir", type=Path, help="Directory containing state.csv")
    parser.add_argument("--gif", type=Path, help="Output GIF path")
    parser.add_argument("--html", type=Path, help="Output HTML path")
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--frame-dt", type=float, default=0.1, help="Simulation seconds per GIF frame")
    parser.add_argument("--trail", type=float, default=5.0, help="Seconds of trail shown in GIF")
    parser.add_argument(
        "--view",
        choices=["dashboard", "3d", "both"],
        default="both",
        help="GIF view to render",
    )
    args = parser.parse_args()

    state_path = args.run_dir / "state.csv"
    times, uav_ids, by_time, traces = load_states(state_path)
    if not times:
        raise SystemExit(f"no state rows found in {state_path}")

    gif_path = args.gif or (args.run_dir / "replay.gif")
    gif_3d_path = args.run_dir / "replay_3d.gif"
    html_path = args.html or (args.run_dir / "replay.html")
    if args.view in ("dashboard", "both"):
        write_dashboard_gif(times, uav_ids, by_time, traces, gif_path, args.fps, args.frame_dt, args.trail)
        print(f"wrote {gif_path}")
    if args.view in ("3d", "both"):
        write_3d_gif(times, uav_ids, by_time, traces, gif_3d_path, args.fps, args.frame_dt, args.trail)
        print(f"wrote {gif_3d_path}")
    write_html(times, uav_ids, by_time, traces, html_path)
    print(f"wrote {html_path}")


if __name__ == "__main__":
    main()
