(* Continuous 3D airspace helpers. *)

let name = "continuous3d"

let occupied_layers (_ : Types.uav_state) = []

let z_of_level cfg level = float_of_int level *. cfg.Types.layer_spacing

let level_of_z cfg z =
  int_of_float (floor ((z /. cfg.Types.layer_spacing) +. 0.5))

let initial_level_of_goal _cfg ~goal:_ ~start:_ = 0

let initial_mode_state _cfg ~initial_level:_ = Types.Continuous3D

let log_layer_fields (_ : Types.uav_state) = (-1, -1, -1, 0)
