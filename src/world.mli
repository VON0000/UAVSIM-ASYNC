(** Truth-state world. Planners only receive self_state snapshots through this API. *)

type t

val create :
  cfg:Types.sim_config ->
  bundle:Mode_registry.mode_bundle ->
  initial:Types.uav_state array ->
  t

val step : t -> now:float -> dt:float -> unit
val set_command : t -> Types.planner_command -> unit
val get_self_state : t -> uav_id:int -> now:float -> Types.self_state
val all_states_for_evaluator : t -> Types.uav_state array
val n_uavs : t -> int
val all_finished : t -> bool
