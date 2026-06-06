(** Minimal text scenario loader and initial-state builder. *)

type uav_spec = {
  id : int;
  start : Vec3.t;
  goal : Vec3.t;
  uav_type : Types.uav_type_params;
  initial_level : int;
}

type t = {
  name : string;
  uavs : uav_spec list;
}

val load_file : string -> t

val to_initial_states :
  bundle:Mode_registry.mode_bundle ->
  cfg:Types.sim_config ->
  t ->
  Types.uav_state array
