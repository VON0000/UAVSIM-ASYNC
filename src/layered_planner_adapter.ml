(* Stub layered planner adapter. TODO: wire in resolstage_move_once_3d core here. *)

let name = "layered_stub"

let plan_once ~cfg ~now ~(self : Types.self_state) ~neighbors:_ ~last_command:_ =
  let current_level =
    match self.Types.mode_state with
    | Types.Layered { current_level; _ } -> current_level
    | Types.Continuous3D ->
        failwith "Layered_planner_adapter: got Continuous3D mode_state"
  in
  let delta = Vec3.sub self.Types.goal self.pos in
  let dist = Vec3.norm_xy delta in
  let speed = min self.uav_type.Types.vmax (dist /. max cfg.Types.planner_period 1e-9) in
  let target_vel =
    if dist <= 1e-9 then Vec3.zero
    else { Vec3.x = delta.x *. speed /. dist; y = delta.y *. speed /. dist; z = 0.0 }
  in
  {
    Types.uav_id = self.id;
    stamp = now;
    target_vel;
    target_level = Some current_level;
    start_level_change = false;
    emergency = false;
    theta_used = None;
    compute_time_ms = 0.0;
  }
