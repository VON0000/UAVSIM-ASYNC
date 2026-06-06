(** Minimal receive-time ordered message queue. *)

type t

val create : unit -> t
val push : t -> Types.neighbor_msg -> unit
val pop_ready : t -> now:float -> Types.neighbor_msg list
