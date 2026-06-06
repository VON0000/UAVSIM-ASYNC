(* Runtime-selectable evaluation accumulator interface. *)

module type EVALUATION_MODEL = sig
  val name : string

  type accumulator

  val empty : Types.sim_config -> accumulator

  val on_planning :
    accumulator -> cmd:Types.planner_command -> accumulator

  val on_step :
    accumulator ->
    now:float ->
    states:Types.uav_state array ->
    pair_distance:(Types.uav_state -> Types.uav_state -> float) ->
    is_conflict:(Types.uav_state -> Types.uav_state -> bool) ->
    accumulator

  val on_comm_event :
    accumulator ->
    [ `Sent | `Dropped | `Received of float ] ->
    accumulator

  val summary_row :
    accumulator -> cfg:Types.sim_config -> (string * string) list
end
