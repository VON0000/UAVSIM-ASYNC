(* Layered true-state conflict model. *)

let name = "layered_conflict"

let has_intersection a b =
  List.exists (fun x -> List.exists (( = ) x) b) a

let is_transitioning (s : Types.uav_state) =
  match s.Types.mode_state with
  | Types.Layered { transition = Types.LevelChanging _; _ } -> true
  | _ -> false

let separation_distance (a : Types.uav_state) (b : Types.uav_state) =
  if is_transitioning a || is_transitioning b then Vec3.distance a.pos b.pos
  else Vec3.distance_xy a.pos b.pos

let is_conflict ~cfg (a : Types.uav_state) (b : Types.uav_state) =
  a.Types.active && b.Types.active
  && has_intersection
    (Layered_airspace.occupied_layers a)
    (Layered_airspace.occupied_layers b)
  && separation_distance a b < cfg.Types.safety_radius

let pair_distance ~cfg:_ (a : Types.uav_state) (b : Types.uav_state) =
  if a.Types.active && b.Types.active then separation_distance a b else infinity
