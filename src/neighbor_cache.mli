(** Per-UAV cache of latest delayed neighbor messages. *)

type t

val create : unit -> t
val ingest : t -> Types.neighbor_msg -> unit

val get_valid_neighbors :
  t ->
  now:float ->
  cfg:Types.sim_config ->
  self_id:int ->
  Types.neighbor_observation list
