(* Async planner scheduler with per-UAV jitter. *)

type t = {
  cfg : Types.sim_config;
  rng : Random_utils.t;
  mutable next_plan : float array;
}

let jittered_period t =
  max t.cfg.Types.world_dt
    (t.cfg.planner_period
    +. Random_utils.uniform t.rng (-.t.cfg.planner_jitter) t.cfg.planner_jitter)

let create ~cfg ~n_uavs ~rng =
  let t = { cfg; rng; next_plan = Array.make n_uavs 0.0 } in
  Array.iteri (fun i _ -> t.next_plan.(i) <- Random_utils.uniform rng 0.0 cfg.planner_period) t.next_plan;
  t

let due_uavs t ~now =
  let due = ref [] in
  Array.iteri (fun i next -> if now +. 1e-9 >= next then due := i :: !due) t.next_plan;
  List.rev !due

let schedule_next t ~uav_id ~now =
  t.next_plan.(uav_id) <- now +. jittered_period t
