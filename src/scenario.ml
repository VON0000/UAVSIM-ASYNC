(* Minimal text scenario parser and initial-state conversion. *)

type uav_spec = {
  id : int;
  start : Vec3.t;
  goal : Vec3.t;
  uav_type : Types.uav_type_params;
  initial_level : int;
  planner_start_time : float option;
  planner_period : float option;
}

type t = {
  name : string;
  uavs : uav_spec list;
}

let default_uav_type : Types.uav_type_params =
  (* speed=10, radius=norme=80, climb_rate=layer_spacing/climb_step=160/5. *)
  {
    Types.type_name = "default";
    vmax = 10.0;
    amax_xy = 3.0;
    az_up_max = 2.0;
    az_down_max = 2.0;
    jerk_max = 5.0;
    yaw_rate_max = 1.5;
    yaw_acc_max = 3.0;
    climb_rate_max = 32.0;
    radius = 80.0;
  }

let words line =
  line |> String.trim |> Str.split (Str.regexp "[ \t]+")

let vec x y z = Vec3.{ x; y; z }

let parse_optional_uav_fields tokens =
  let rec loop start_time period = function
    | [] -> (start_time, period)
    | "planner_start" :: value :: rest ->
        loop (Some (float_of_string value)) period rest
    | "planner_period" :: value :: rest ->
        loop start_time (Some (float_of_string value)) rest
    | toks ->
        invalid_arg ("bad optional uav fields: " ^ String.concat " " toks)
  in
  loop None None tokens

let parse_uav tokens =
  match tokens with
  | "uav" :: id :: "start" :: sx :: sy :: sz :: "goal" :: gx :: gy :: gz
    :: "type" :: _typ :: "level" :: level :: optional ->
      let planner_start_time, planner_period =
        parse_optional_uav_fields optional
      in
      {
        id = int_of_string id;
        start = vec (float_of_string sx) (float_of_string sy) (float_of_string sz);
        goal = vec (float_of_string gx) (float_of_string gy) (float_of_string gz);
        uav_type = default_uav_type;
        initial_level = int_of_string level;
        planner_start_time;
        planner_period;
      }
  | _ -> invalid_arg ("bad uav line: " ^ String.concat " " tokens)

let load_file path =
  let ch = open_in path in
  let name = ref (Filename.basename path) in
  let uavs = ref [] in
  (try
     while true do
       let line = input_line ch in
       let line =
         match String.index_opt line '#' with
         | None -> line
         | Some i -> String.sub line 0 i
       in
       match words line with
       | [] -> ()
       | [ "name"; n ] -> name := n
       | "uav" :: _ as toks -> uavs := parse_uav toks :: !uavs
       | toks -> invalid_arg ("bad scenario line: " ^ String.concat " " toks)
     done
   with End_of_file -> close_in ch);
  { name = !name; uavs = List.rev !uavs }

let to_initial_states ~bundle ~cfg scenario =
  let module A = (val bundle.Mode_registry.airspace : Airspace_model.AIRSPACE_MODEL) in
  scenario.uavs
  |> List.map (fun spec ->
         {
           Types.id = spec.id;
           pos = spec.start;
           vel = Vec3.zero;
           acc = Vec3.zero;
           yaw = 0.0;
           yaw_rate = 0.0;
           mode_state = A.initial_mode_state cfg ~initial_level:spec.initial_level;
           goal = spec.goal;
           active = true;
           reached = false;
           stalled = false;
           uav_type = spec.uav_type;
         })
  |> Array.of_list

let planner_timings ~cfg ~rng scenario =
  scenario.uavs
  |> List.map (fun spec ->
         let period =
           match spec.planner_period with
           | Some period -> period
           | None ->
               cfg.Types.planner_period
               +. Random_utils.uniform rng (-.cfg.planner_jitter) cfg.planner_jitter
         in
         let period = max cfg.world_dt period in
         let start_time =
           match spec.planner_start_time with
           | Some start_time -> max 0.0 start_time
           | None -> Random_utils.uniform rng 0.0 period
         in
         Planner_scheduler.{ start_time; period })
  |> Array.of_list
