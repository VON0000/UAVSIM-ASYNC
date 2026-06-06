(* Runtime-selectable true-state conflict checks for evaluation. *)

module type CONFLICT_MODEL = sig
  val name : string

  val is_conflict :
    cfg:Types.sim_config -> Types.uav_state -> Types.uav_state -> bool

  val pair_distance :
    cfg:Types.sim_config -> Types.uav_state -> Types.uav_state -> float
end
