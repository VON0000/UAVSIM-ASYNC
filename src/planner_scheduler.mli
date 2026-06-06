(** Async per-UAV planning timer scheduler. *)

type t

val create : cfg:Types.sim_config -> n_uavs:int -> rng:Random_utils.t -> t
val due_uavs : t -> now:float -> int list
val schedule_next : t -> uav_id:int -> now:float -> unit
