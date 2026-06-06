(** CSV logger for state, event, and summary outputs. *)

type t

val create : cfg:Types.sim_config -> bundle:Mode_registry.mode_bundle -> t
val close : t -> unit

val write_state_row :
  t -> now:float -> states:Types.uav_state array -> unit

val write_event :
  t ->
  now:float ->
  event:string ->
  uav_id:int ->
  ?other_id:int ->
  ?value1:float ->
  ?value2:float ->
  ?desc:string ->
  unit ->
  unit

val write_summary :
  t ->
  scenario:string ->
  seed:int ->
  mode:string ->
  summary_row:(string * string) list ->
  unit
