(** Broadcast communication model with packet loss, delay, and range. *)

type t

val create : cfg:Types.sim_config -> n_uavs:int -> rng:Random_utils.t -> t

val maybe_broadcast :
  t ->
  now:float ->
  true_states:Types.uav_state array ->
  on_send:(Types.neighbor_msg -> unit) ->
  on_drop:(sender:int -> receiver:int -> unit) ->
  Types.neighbor_msg list
