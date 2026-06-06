(* Runtime-selectable motion integration interface. *)

module type MOTION_MODEL = sig
  val name : string

  val step :
    cfg:Types.sim_config ->
    dt:float ->
    cmd:Types.planner_command ->
    Types.uav_state ->
    Types.uav_state

  val reached : cfg:Types.sim_config -> Types.uav_state -> bool
end
