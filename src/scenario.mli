(** Minimal text scenario loader and initial-state builder. *)

type uav_spec = {
  id : int;
  start : Vec3.t;
  goal : Vec3.t;
  uav_type : Types.uav_type_params;
  initial_level : int;
  planner_start_time : float option;
  planner_period : float option;
}

type t = {
  name : string;
  uavs : uav_spec list;
}

val load_file : string -> t

val planner_timings :
  cfg:Types.sim_config -> rng:Random_utils.t -> t -> Planner_scheduler.uav_timing array

val to_initial_states :
  bundle:Mode_registry.mode_bundle ->
  cfg:Types.sim_config ->
  t ->
  Types.uav_state array
