(* Truth-state world and controlled planner-facing snapshot API. *)

type t = {
  cfg : Types.sim_config;
  motion : (module Motion_model.MOTION_MODEL);
  mutable states : Types.uav_state array;
  last_commands : (Types.planner_command option) array;
}

let hold_command now (s : Types.uav_state) =
  {
    Types.uav_id = s.id;
    stamp = now;
    target_vel = s.vel;
    target_level = None;
    start_level_change = false;
    emergency = false;
    theta_used = None;
    compute_time_ms = 0.0;
  }

let create ~cfg ~bundle ~initial =
  {
    cfg;
    motion = bundle.Mode_registry.motion;
    states = Array.copy initial;
    last_commands = Array.make (Array.length initial) None;
  }

let step t ~now ~dt =
  let module M = (val t.motion : Motion_model.MOTION_MODEL) in
  t.states <-
    Array.mapi
      (fun i s ->
        let cmd =
          match t.last_commands.(i) with
          | Some c -> c
          | None -> hold_command now s
        in
        M.step ~cfg:t.cfg ~dt ~cmd s)
      t.states

let set_command t cmd =
  if cmd.Types.uav_id >= 0 && cmd.uav_id < Array.length t.last_commands then
    t.last_commands.(cmd.uav_id) <- Some cmd

let get_self_state t ~uav_id ~now =
  let s = t.states.(uav_id) in
  {
    Types.id = s.id;
    stamp = now;
    pos = s.pos;
    vel = s.vel;
    acc = s.acc;
    yaw = s.yaw;
    yaw_rate = s.yaw_rate;
    mode_state = s.mode_state;
    goal = s.goal;
    uav_type = s.uav_type;
  }

let all_states_for_evaluator t = Array.copy t.states

let n_uavs t = Array.length t.states

let all_finished t = Array.for_all (fun s -> not s.Types.active) t.states
