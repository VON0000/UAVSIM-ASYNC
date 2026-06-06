(* Runtime-selectable planner adapter interface. *)

module type PLANNER_ADAPTER = sig
  val name : string

  val plan_once :
    cfg:Types.sim_config ->
    now:float ->
    self:Types.self_state ->
    neighbors:Types.neighbor_observation list ->
    last_command:Types.planner_command option ->
    Types.planner_command
end
