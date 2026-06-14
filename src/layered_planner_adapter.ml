(* Layered ORCA planner adapter. *)

let name = "layered_orca"

let plan_once ~cfg ~now ~(self : Types.self_state) ~neighbors ~last_command =
  let res = Layered_orca.solve ~cfg ~now ~self ~neighbors ~last_command in
  {
    Types.uav_id = self.id;
    stamp = now;
    target_vel = res.target_vel;
    target_level = Some res.target_level;
    start_level_change = res.start_level_change;
    emergency = res.emergency;
    theta_used = res.theta_used;
    compute_time_ms = 0.0;
  }
