(* Minimal text scenario parser and initial-state conversion. *)

type uav_spec = {
  id : int;
  start : Vec3.t;
  goal : Vec3.t;
  uav_type : Types.uav_type_params;
  initial_level : int;
}

type t = {
  name : string;
  uavs : uav_spec list;
}

let default_uav_type : Types.uav_type_params =
  {
    Types.type_name = "default";
    vmax = 2.0;
    amax_xy = 3.0;
    az_up_max = 2.0;
    az_down_max = 2.0;
    jerk_max = 5.0;
    yaw_rate_max = 1.5;
    yaw_acc_max = 3.0;
    climb_rate_max = 2.0;
    radius = 0.5;
  }

let words line =
  line |> String.trim |> Str.split (Str.regexp "[ \t]+")

let vec x y z = Vec3.{ x; y; z }

let parse_uav tokens =
  match tokens with
  | [
   "uav";
   id;
   "start";
   sx;
   sy;
   sz;
   "goal";
   gx;
   gy;
   gz;
   "type";
   _typ;
   "level";
   level;
  ] ->
      {
        id = int_of_string id;
        start = vec (float_of_string sx) (float_of_string sy) (float_of_string sz);
        goal = vec (float_of_string gx) (float_of_string gy) (float_of_string gz);
        uav_type = default_uav_type;
        initial_level = int_of_string level;
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
