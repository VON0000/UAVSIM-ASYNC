(** ORCA-style layered planner core adapted from ../ORCA-ORIGIN. *)

type result = {
  target_vel : Vec3.t;
  target_level : int;
  start_level_change : bool;
  theta_used : float option;
  emergency : bool;
}

val solve :
  cfg:Types.sim_config ->
  now:float ->
  self:Types.self_state ->
  neighbors:Types.neighbor_observation list ->
  last_command:Types.planner_command option ->
  result
