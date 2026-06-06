(* Layered airspace helpers. *)

let name = "layered"

let occupied_layers (s : Types.uav_state) =
  match s.mode_state with
  | Types.Layered { current_level; transition = Types.LevelStable } ->
      [ current_level ]
  | Types.Layered
      { transition = Types.LevelChanging { from_level; target_level; _ }; _ } ->
      [ from_level; target_level ]
  | Types.Continuous3D ->
      failwith "Layered_airspace called on Continuous3D state"

let z_of_level cfg level = float_of_int level *. cfg.Types.layer_spacing

let level_of_z cfg z =
  let raw = int_of_float (floor ((z /. cfg.Types.layer_spacing) +. 0.5)) in
  max 0 (min (cfg.Types.layer_count - 1) raw)

let initial_level_of_goal cfg ~goal:_ ~start =
  level_of_z cfg start.Vec3.z

let initial_mode_state _cfg ~initial_level =
  Types.Layered
    { current_level = initial_level; transition = Types.LevelStable }

let log_layer_fields (s : Types.uav_state) =
  match s.mode_state with
  | Types.Layered { current_level; transition = Types.LevelStable } ->
      (current_level, -1, -1, 0)
  | Types.Layered
      { transition = Types.LevelChanging { from_level; target_level; _ }; _ } ->
      (from_level, from_level, target_level, 1)
  | Types.Continuous3D ->
      failwith "Layered_airspace.log_layer_fields called on Continuous3D state"
