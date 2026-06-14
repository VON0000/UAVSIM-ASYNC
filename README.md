# Multi-UAV Async Simulator Skeleton

OCaml event-driven asynchronous multi-UAV simulator scaffold with two runtime-selectable modes:

- `layered`
- `continuous3d`

The planners are intentionally stubs. They fly straight toward the goal and do not avoid conflicts.

## Build

```sh
make
```

This uses `ocamlfind ocamlopt` with `unix` and `str`; dune is not used.

## Run

```sh
./_build/run_async --mode layered --scenario scenarios/head_on_2.txt --seed 42 --out-dir results/raw/test1
./_build/run_async --mode continuous3d --scenario scenarios/head_on_2.txt --seed 42 --out-dir results/raw/test2
```

Each run writes:

- `state.csv`
- `events.csv`
- `summary.csv`

Visualize one run as SVG:

```sh
python3 scripts/plot_metrics.py results/raw/test1
```

This writes `trajectory_xy.svg` and `altitude_z.svg` in the run directory.

Create an animated replay:

```sh
python3 scripts/animate_run.py results/raw/test1
```

This writes `replay.gif` and `replay.html`. Open `replay.html` in a browser for
an interactive full-run playback with a scrubber. `replay.gif` shows a
synchronized top-down XY view and front XZ view; `replay_3d.gif` shows the same
run in a 3D view.

## Scenario Format

```text
name head_on_2
uav 0 start 0 0 0 goal 20 0 0 type default level 0
uav 1 start 20 0 0 goal 0 0 0 type default level 0
```

The `level` field is used by `layered`; `continuous3d` ignores it.

Optional per-UAV planner timing fields can be appended to each `uav` line:

```text
uav 0 start 0 0 0 goal 20 0 0 type default level 0 planner_start 0.0 planner_period 0.5
uav 1 start 20 0 0 goal 0 0 0 type default level 0 planner_start 0.2 planner_period 0.3
```

`planner_start` is the first planning trigger time for that UAV, which also
delays movement while the held command is zero velocity. `planner_period` is
fixed for the whole run. If omitted, the simulator samples a start offset and a
single fixed per-UAV period from the default config and seed.

## Adapter TODOs

- `src/continuous3d_planner_adapter.ml`: connect the extracted 3D ORCA `Avoid` core.
- `src/layered_planner_adapter.ml`: connect the extracted layered ORCA/Maneuver core.
