(* Default simulator configuration. CLI overrides selected fields. *)

open Types

let default_config : sim_config =
  (* Mirrors ../ORCA-ORIGIN/config.ml: pas=1, norme=80, fly_level_nb=4. *)
  {
    world_dt = 1.0;
    max_time = 2000.0;
    planner_period = 1.0;
    planner_jitter = 0.0;
    stale_timeout = 2.0;
    broadcast_rate = 20.0;
    delay_mean = 0.0;
    delay_jitter = 0.0;
    packet_loss = 0.0;
    comm_range = infinity;
    k_delay_radius = 0.0;
    layer_spacing = 160.0;
    layer_count = 4;
    safety_radius = 160.0;
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
