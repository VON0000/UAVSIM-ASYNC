(* CSV logger for state traces, events, and one-row summaries. *)

type t = {
  bundle : Mode_registry.mode_bundle;
  state : out_channel;
  events : out_channel;
  summary : out_channel;
}

let rec ensure_dir path =
  if path <> "" && not (Sys.file_exists path) then (
    ensure_dir (Filename.dirname path);
    Unix.mkdir path 0o755)

let ensure_parent path = ensure_dir (Filename.dirname path)

let csv_escape s =
  if String.exists (fun c -> c = ',' || c = '"' || c = '\n') s then
    "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""
  else s

let create ~cfg ~bundle =
  ensure_parent cfg.Types.state_log_path;
  ensure_parent cfg.event_log_path;
  ensure_parent cfg.summary_log_path;
  let state = open_out cfg.state_log_path in
  let events = open_out cfg.event_log_path in
  let summary = open_out cfg.summary_log_path in
  output_string state
    "time,uav_id,x,y,z,vx,vy,vz,yaw,level,from_level,target_level,is_changing,reached,active\n";
  output_string events
    "time,event,uav_id,other_id,value1,value2,desc\n";
  { bundle; state; events; summary }

let close t =
  close_out_noerr t.state;
  close_out_noerr t.events;
  close_out_noerr t.summary

let write_state_row t ~now ~(states : Types.uav_state array) =
  let module A = (val t.bundle.airspace : Airspace_model.AIRSPACE_MODEL) in
  Array.iter
    (fun (s : Types.uav_state) ->
      let level, from_level, target_level, is_changing =
        A.log_layer_fields s
      in
      Printf.fprintf t.state
        "%.6f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%b,%b\n"
        now s.id s.pos.Vec3.x s.pos.y s.pos.z s.vel.x s.vel.y s.vel.z s.yaw
        level from_level target_level is_changing s.reached s.active)
    states

let opt_int = function None -> "" | Some x -> string_of_int x
let opt_float = function None -> "" | Some x -> Printf.sprintf "%.6f" x

let write_event t ~now ~event ~uav_id ?other_id ?value1 ?value2 ?desc () =
  Printf.fprintf t.events "%f,%s,%d,%s,%s,%s,%s\n" now (csv_escape event) uav_id
    (opt_int other_id) (opt_float value1) (opt_float value2)
    (csv_escape (Option.value desc ~default:""))

let write_summary t ~scenario ~seed ~mode ~summary_row =
  let headers =
    [ "scenario"; "seed"; "mode" ] @ List.map fst summary_row
  in
  let values =
    [ scenario; string_of_int seed; mode ] @ List.map snd summary_row
  in
  output_string t.summary (String.concat "," (List.map csv_escape headers) ^ "\n");
  output_string t.summary (String.concat "," (List.map csv_escape values) ^ "\n")
