(* Simple first-order continuous 3D motion integration. *)

let name = "continuous3d_motion"

let clamp_speed vmax v =
  let n = Vec3.norm v in
  if n <= vmax || n <= 1e-9 then v else Vec3.scale (vmax /. n) v

let reached ~cfg (s : Types.uav_state) =
  Vec3.distance s.pos s.goal <= cfg.Types.safety_radius

let step ~cfg ~dt ~cmd (s : Types.uav_state) =
  if not s.Types.active then s
  else
    let target_vel = clamp_speed s.Types.uav_type.vmax cmd.Types.target_vel in
    let pos = Vec3.add s.pos (Vec3.scale dt target_vel) in
    let next = { s with Types.pos; vel = target_vel; acc = Vec3.zero } in
    let did_reach = reached ~cfg next in
    { next with reached = did_reach; active = not did_reach }
