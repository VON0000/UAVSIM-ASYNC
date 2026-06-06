(* Layered evaluation accumulator and CSV summary fields. *)

let name = "layered_evaluation"

type accumulator = {
  mutable initialized : bool;
  mutable last_pos : Vec3.t array;
  mutable path_length : float array;
  mutable collision_pair_step_count : int;
  mutable min_distance : float;
  mutable planning_count : int;
  mutable compute_time_ms : float;
  mutable sent : int;
  mutable dropped : int;
  mutable received : int;
  mutable last_time : float;
  mutable layer_change_count : int;
  mutable dual_layer_conflict_count : int;
  mutable time_in_transition : float;
}

let empty (_cfg : Types.sim_config) =
  {
    initialized = false;
    last_pos = [||];
    path_length = [||];
    collision_pair_step_count = 0;
    min_distance = infinity;
    planning_count = 0;
    compute_time_ms = 0.0;
    sent = 0;
    dropped = 0;
    received = 0;
    last_time = 0.0;
    layer_change_count = 0;
    dual_layer_conflict_count = 0;
    time_in_transition = 0.0;
  }

let on_planning acc ~cmd =
  acc.planning_count <- acc.planning_count + 1;
  acc.compute_time_ms <- acc.compute_time_ms +. cmd.Types.compute_time_ms;
  if cmd.start_level_change then acc.layer_change_count <- acc.layer_change_count + 1;
  acc

let ensure acc (states : Types.uav_state array) =
  if not acc.initialized then (
    acc.initialized <- true;
    acc.last_pos <- Array.map (fun (s : Types.uav_state) -> s.pos) states;
    acc.path_length <- Array.make (Array.length states) 0.0)

let is_transitioning (s : Types.uav_state) =
  match s.Types.mode_state with
  | Types.Layered { transition = Types.LevelChanging _; _ } -> true
  | _ -> false

let on_step acc ~now ~(states : Types.uav_state array) ~pair_distance ~is_conflict =
  ensure acc states;
  let dt = max 0.0 (now -. acc.last_time) in
  Array.iteri
    (fun i (s : Types.uav_state) ->
      if i < Array.length acc.last_pos then (
        acc.path_length.(i) <-
          acc.path_length.(i) +. Vec3.distance acc.last_pos.(i) s.pos;
        acc.last_pos.(i) <- s.pos);
      if is_transitioning s then acc.time_in_transition <- acc.time_in_transition +. dt)
    states;
  for i = 0 to Array.length states - 1 do
    for j = i + 1 to Array.length states - 1 do
      let d = pair_distance states.(i) states.(j) in
      acc.min_distance <- min acc.min_distance d;
      if is_conflict states.(i) states.(j) then (
        acc.collision_pair_step_count <- acc.collision_pair_step_count + 1;
        let li = Layered_airspace.occupied_layers states.(i) in
        let lj = Layered_airspace.occupied_layers states.(j) in
        if List.length li > 1 || List.length lj > 1 then
          acc.dual_layer_conflict_count <- acc.dual_layer_conflict_count + 1)
    done
  done;
  acc.last_time <- now;
  acc

let on_comm_event acc ev =
  (match ev with
  | `Sent -> acc.sent <- acc.sent + 1
  | `Dropped -> acc.dropped <- acc.dropped + 1
  | `Received _ -> acc.received <- acc.received + 1);
  acc

let fmt_float x = Printf.sprintf "%.6f" x

let summary_row acc ~cfg:_ =
  let total_path = Array.fold_left ( +. ) 0.0 acc.path_length in
  let pdr =
    if acc.sent = 0 then 0.0 else float_of_int acc.received /. float_of_int acc.sent
  in
  [
    ("success", string_of_bool (acc.collision_pair_step_count = 0));
    ("collision_pair_step_count", string_of_int acc.collision_pair_step_count);
    ("min_distance", fmt_float acc.min_distance);
    ("flight_time", fmt_float acc.last_time);
    ("path_length", fmt_float total_path);
    ("avg_speed", fmt_float (if acc.last_time <= 0.0 then 0.0 else total_path /. acc.last_time));
    ("planning_count", string_of_int acc.planning_count);
    ("compute_time_ms", fmt_float acc.compute_time_ms);
    ("packet_delivery_ratio", fmt_float pdr);
    ("layer_change_count", string_of_int acc.layer_change_count);
    ("failed_layer_change_count", "0");
    ("dual_layer_conflict_count", string_of_int acc.dual_layer_conflict_count);
    ("time_in_transition", fmt_float acc.time_in_transition);
    ("return_to_original_layer_ratio", "0");
  ]
