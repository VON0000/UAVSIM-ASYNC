(* Per-UAV neighbor cache with first-order extrapolation. *)

type t = (int, Types.neighbor_msg) Hashtbl.t

let create () = Hashtbl.create 16

let ingest t msg =
  let replace =
    match Hashtbl.find_opt t msg.Types.sender_id with
    | None -> true
    | Some (old : Types.neighbor_msg) -> msg.sent_time >= old.sent_time
  in
  if replace then Hashtbl.replace t msg.sender_id msg

let observation_of_msg ~now ~cfg msg =
  let age = max 0.0 (now -. msg.Types.sent_time) in
  let pos = Vec3.add msg.pos (Vec3.scale age msg.vel) in
  {
    Types.id = msg.sender_id;
    pos;
    vel = msg.vel;
    acc = msg.acc;
    yaw = msg.yaw;
    mode_state = msg.mode_state;
    radius = msg.radius;
    effective_radius = msg.radius +. (cfg.Types.k_delay_radius *. age);
    age;
    is_stale = age > cfg.stale_timeout;
  }

let get_valid_neighbors t ~now ~cfg ~self_id =
  Hashtbl.fold
    (fun sender msg acc ->
      if sender = self_id then acc else observation_of_msg ~now ~cfg msg :: acc)
    t []
