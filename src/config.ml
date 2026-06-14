(* Default simulator configuration. CLI overrides selected fields. *)

open Types

let default_config : sim_config =
  {
    world_dt = 0.05;
    max_time = 20.0;
    planner_period = 0.5;
    planner_jitter = 0.05;
    stale_timeout = 2.0;
    broadcast_rate = 5.0;
    delay_mean = 0.05;
    delay_jitter = 0.02;
    packet_loss = 0.0;
    comm_range = infinity;
    k_delay_radius = 0.1;
    layer_spacing = 5.0;
    layer_count = 5;
    safety_radius = 1.5;
    random_seed = 1;
    state_log_path = "results/raw/state.csv";
    event_log_path = "results/raw/events.csv";
    summary_log_path = "results/raw/summary.csv";
  }

let with_output_dir cfg out_dir =
  let join file = Filename.concat out_dir file in
  {
    cfg with
    state_log_path = join "state.csv";
    event_log_path = join "events.csv";
    summary_log_path = join "summary.csv";
  }
