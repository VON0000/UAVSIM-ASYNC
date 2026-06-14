#!/usr/bin/env python3
"""Plot simulator state.csv traces to simple SVG files.

The script intentionally uses only the Python standard library so it works in
minimal experiment environments.
"""

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path


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
    traces = defaultdict(list)
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            uav_id = int(row["uav_id"])
            traces[uav_id].append(
                {
                    "time": float(row["time"]),
                    "x": float(row["x"]),
                    "y": float(row["y"]),
                    "z": float(row["z"]),
                    "active": row["active"].lower() == "true",
                    "reached": row["reached"].lower() == "true",
                }
            )
    return dict(sorted(traces.items()))


def bounds(values):
    low = min(values)
    high = max(values)
    if math.isclose(low, high):
        pad = max(1.0, abs(low) * 0.1)
        return low - pad, high + pad
    pad = (high - low) * 0.08
    return low - pad, high + pad


def make_projector(xmin, xmax, ymin, ymax, width, height, margin):
    def project(x, y):
        px = margin + (x - xmin) / (xmax - xmin) * (width - 2 * margin)
        py = height - margin - (y - ymin) / (ymax - ymin) * (height - 2 * margin)
        return px, py

    return project


def polyline(points, color, width=2.5):
    pts = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
    return (
        f'<polyline points="{pts}" fill="none" stroke="{color}" '
        f'stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>'
    )


def circle(x, y, r, color, fill="white"):
    return f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r}" fill="{fill}" stroke="{color}" stroke-width="2"/>'


def text(x, y, value, size=13, anchor="start"):
    return (
        f'<text x="{x:.2f}" y="{y:.2f}" font-family="Arial, sans-serif" '
        f'font-size="{size}" text-anchor="{anchor}" fill="#202020">{value}</text>'
    )


def svg_page(width, height, title, body):
    return "\n".join(
        [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
            '<rect width="100%" height="100%" fill="white"/>',
            text(24, 32, title, size=20),
            *body,
            "</svg>",
            "",
        ]
    )


def write_trajectory(traces, out_path):
    width, height, margin = 960, 720, 72
    xs = [p["x"] for trace in traces.values() for p in trace]
    ys = [p["y"] for trace in traces.values() for p in trace]
    xmin, xmax = bounds(xs)
    ymin, ymax = bounds(ys)
    project = make_projector(xmin, xmax, ymin, ymax, width, height, margin)

    body = [
        f'<rect x="{margin}" y="{margin}" width="{width - 2 * margin}" height="{height - 2 * margin}" fill="#fafafa" stroke="#d0d0d0"/>',
        text(margin, height - 28, f"x: {xmin:.1f} .. {xmax:.1f}"),
        text(width - margin, height - 28, f"y: {ymin:.1f} .. {ymax:.1f}", anchor="end"),
    ]
    for idx, (uav_id, trace) in enumerate(traces.items()):
        color = COLORS[idx % len(COLORS)]
        points = [project(p["x"], p["y"]) for p in trace]
        body.append(polyline(points, color))
        sx, sy = points[0]
        ex, ey = points[-1]
        body.append(circle(sx, sy, 5, color))
        body.append(circle(ex, ey, 5, color, fill=color))
        body.append(text(ex + 8, ey - 8, f"UAV {uav_id}", size=12))
    out_path.write_text(svg_page(width, height, "Top-down UAV trajectories", body))


def write_altitude(traces, out_path):
    width, height, margin = 960, 520, 72
    ts = [p["time"] for trace in traces.values() for p in trace]
    zs = [p["z"] for trace in traces.values() for p in trace]
    tmin, tmax = bounds(ts)
    zmin, zmax = bounds(zs)
    project = make_projector(tmin, tmax, zmin, zmax, width, height, margin)

    body = [
        f'<rect x="{margin}" y="{margin}" width="{width - 2 * margin}" height="{height - 2 * margin}" fill="#fafafa" stroke="#d0d0d0"/>',
        text(margin, height - 28, f"time: {tmin:.1f} .. {tmax:.1f}s"),
        text(width - margin, height - 28, f"z: {zmin:.1f} .. {zmax:.1f}", anchor="end"),
    ]
    for idx, (uav_id, trace) in enumerate(traces.items()):
        color = COLORS[idx % len(COLORS)]
        points = [project(p["time"], p["z"]) for p in trace]
        body.append(polyline(points, color))
        ex, ey = points[-1]
        body.append(text(ex + 8, ey - 8, f"UAV {uav_id}", size=12))
    out_path.write_text(svg_page(width, height, "Altitude over time", body))


def main():
    parser = argparse.ArgumentParser(description="Plot run_async state.csv output")
    parser.add_argument("run_dir", type=Path, help="Directory containing state.csv")
    parser.add_argument("--out-dir", type=Path, help="Output directory for SVG files")
    args = parser.parse_args()

    state_path = args.run_dir / "state.csv"
    out_dir = args.out_dir or args.run_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    traces = load_states(state_path)
    if not traces:
        raise SystemExit(f"no state rows found in {state_path}")

    trajectory_path = out_dir / "trajectory_xy.svg"
    altitude_path = out_dir / "altitude_z.svg"
    write_trajectory(traces, trajectory_path)
    write_altitude(traces, altitude_path)
    print(f"wrote {trajectory_path}")
    print(f"wrote {altitude_path}")


if __name__ == "__main__":
    main()
