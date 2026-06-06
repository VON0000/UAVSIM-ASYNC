(* Runtime-selectable airspace model interface. *)

module type AIRSPACE_MODEL = sig
  val name : string
  val occupied_layers : Types.uav_state -> int list
  val z_of_level : Types.sim_config -> int -> float
  val level_of_z : Types.sim_config -> float -> int
  val initial_level_of_goal : Types.sim_config -> goal:Vec3.t -> start:Vec3.t -> int

  (** Build this mode's initial mode_state from a scenario initial level. *)
  val initial_mode_state :
    Types.sim_config -> initial_level:int -> Types.mode_state

  (** Layer-related fields written to state.csv:
      (level, from_level, target_level, is_changing). *)
  val log_layer_fields : Types.uav_state -> int * int * int * int
end
