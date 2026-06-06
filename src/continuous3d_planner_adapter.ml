(* Stub 3D planner adapter. TODO: wire in main.ml/Avoid core here. *)

let name = "continuous3d_stub"

let plan_once ~cfg:_ ~now ~(self : Types.self_state) ~neighbors:_ ~last_command:_ =
  let delta = Vec3.sub self.Types.goal self.pos in
  let dist = Vec3.norm delta in
  let target_vel =
    if dist <= 1e-9 then Vec3.zero
    else Vec3.scale (self.uav_type.Types.vmax /. dist) delta
  in
  {
    Types.uav_id = self.id;
    stamp = now;
    target_vel;
    target_level = None;
    start_level_change = false;
    emergency = false;
    theta_used = None;
    compute_time_ms = 0.0;
  }
