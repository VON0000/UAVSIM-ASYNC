(* Simple layered motion integration and level-change state machine. *)

let name = "layered_motion"

let clamp_speed_xy vmax v =
  let n = Vec3.norm_xy v in
  if n <= vmax || n <= 1e-9 then { v with Vec3.z = 0.0 }
  else { x = v.Vec3.x *. vmax /. n; y = v.y *. vmax /. n; z = 0.0 }

let transition_steps ~dt ~(uav_type : Types.uav_type_params) ~target_z ~current_z =
  let distance = abs_float (target_z -. current_z) in
  let climb_rate = max 1e-9 uav_type.climb_rate_max in
  let step_dt = max 1e-9 dt in
  max 1 (int_of_float (ceil ((distance /. climb_rate) /. step_dt)))

let advance_transition cfg ~dt ~uav_type pos mode_state cmd =
  match mode_state with
  | Types.Layered ({ current_level; transition = Types.LevelStable } as ls) -> (
      match (cmd.Types.start_level_change, cmd.target_level) with
      | true, Some target when target <> current_level ->
          let target_z = Layered_airspace.z_of_level cfg target in
          let steps_total =
            transition_steps ~dt ~uav_type ~target_z ~current_z:pos.Vec3.z
          in
          let next =
            Types.LevelChanging
              {
                from_level = current_level;
                target_level = target;
                target_z;
                steps_total;
                steps_left = steps_total - 1;
              }
          in
          let frac = 1.0 /. float_of_int steps_total in
          ( Vec3.lerp pos { pos with Vec3.z = target_z } frac,
            Types.Layered { ls with transition = next } )
      | _ -> (pos, mode_state))
  | Types.Layered
      {
        transition =
          Types.LevelChanging
            { from_level; target_level; target_z; steps_total; steps_left };
        _;
      } ->
      if steps_left <= 1 then
        ( { pos with Vec3.z = target_z },
          Types.Layered { current_level = target_level; transition = Types.LevelStable }
        )
      else
        let done_steps = steps_total - steps_left + 1 in
        let frac = float_of_int done_steps /. float_of_int steps_total in
        let z0 = Layered_airspace.z_of_level cfg from_level in
        let z = z0 +. ((target_z -. z0) *. frac) in
        ( { pos with Vec3.z = z },
          Types.Layered
            {
              current_level = from_level;
              transition =
                Types.LevelChanging
                  {
                    from_level;
                    target_level;
                    target_z;
                    steps_total;
                    steps_left = steps_left - 1;
                  };
            } )
  | Types.Continuous3D ->
      failwith "Layered_motion called on Continuous3D state"

let reached ~cfg (s : Types.uav_state) =
  Vec3.distance_xy s.pos s.goal <= cfg.Types.safety_radius

let step ~cfg ~dt ~cmd (s : Types.uav_state) =
  if not s.Types.active then s
  else
    let target_vel = clamp_speed_xy s.Types.uav_type.vmax cmd.Types.target_vel in
    let xy_pos = Vec3.add s.pos (Vec3.scale dt target_vel) in
    let pos, mode_state =
      advance_transition cfg ~dt ~uav_type:s.uav_type { xy_pos with z = s.pos.z }
        s.mode_state cmd
    in
    let next = { s with Types.pos; vel = target_vel; acc = Vec3.zero; mode_state } in
    let did_reach = reached ~cfg next in
    { next with reached = did_reach; active = not did_reach }
