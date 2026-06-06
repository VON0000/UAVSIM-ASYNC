(* Continuous 3D true-state conflict model. *)

let name = "continuous3d_conflict"

let is_conflict ~cfg (a : Types.uav_state) (b : Types.uav_state) =
  Vec3.distance a.Types.pos b.Types.pos < cfg.Types.safety_radius

let pair_distance ~cfg:_ (a : Types.uav_state) (b : Types.uav_state) =
  Vec3.distance a.pos b.pos
