(* Layered true-state conflict model. *)

let name = "layered_conflict"

let has_intersection a b =
  List.exists (fun x -> List.exists (( = ) x) b) a

let is_conflict ~cfg (a : Types.uav_state) (b : Types.uav_state) =
  has_intersection
    (Layered_airspace.occupied_layers a)
    (Layered_airspace.occupied_layers b)
  && Vec3.distance_xy a.Types.pos b.Types.pos < cfg.Types.safety_radius

let pair_distance ~cfg:_ (a : Types.uav_state) (b : Types.uav_state) =
  Vec3.distance_xy a.pos b.pos
