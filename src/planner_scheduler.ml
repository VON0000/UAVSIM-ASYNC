(* Async planner scheduler with fixed per-UAV planning periods. *)

type uav_timing = {
  start_time : float;
  period : float;
}

type t = {
  cfg : Types.sim_config;
  mutable next_plan : float array;
  periods : float array;
}

let create ~cfg ~timings =
  let next_plan = Array.map (fun timing -> max 0.0 timing.start_time) timings in
  let periods =
    Array.map (fun timing -> max cfg.Types.world_dt timing.period) timings
  in
  { cfg; next_plan; periods }

let due_uavs t ~now =
  let due = ref [] in
  Array.iteri (fun i next -> if now +. 1e-9 >= next then due := i :: !due) t.next_plan;
  List.rev !due

let schedule_next t ~uav_id ~now =
  t.next_plan.(uav_id) <- now +. t.periods.(uav_id)
