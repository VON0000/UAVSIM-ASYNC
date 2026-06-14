(** Async per-UAV planning timer scheduler. *)

type t

type uav_timing = {
  start_time : float;
  period : float;
}

val create : cfg:Types.sim_config -> timings:uav_timing array -> t
val due_uavs : t -> now:float -> int list
val schedule_next : t -> uav_id:int -> now:float -> unit
