(* CLI entry point for the asynchronous multi-UAV simulator. *)

type cli = {
  mutable mode : string;
  mutable scenario : string;
  mutable seed : int;
  mutable out_dir : string;
}

let parse_cli () =
  let mode = ref "layered" in
  let scenario = ref "scenarios/head_on_2.txt" in
  let seed = ref 1 in
  let out_dir = ref "results/raw/run" in
  let specs =
    [
      ("--mode", Arg.Set_string mode, "layered | continuous3d");
      ("--scenario", Arg.Set_string scenario, "scenario file path");
      ("--seed", Arg.Set_int seed, "random seed");
      ("--out-dir", Arg.Set_string out_dir, "output directory");
    ]
  in
  Arg.parse specs (fun s -> raise (Arg.Bad ("unexpected argument: " ^ s))) "run_async";
  { mode = !mode; scenario = !scenario; seed = !seed; out_dir = !out_dir }

let make_config cli =
  if Config.default_config.Types.planner_period < Config.default_config.world_dt then
    invalid_arg "planner_period must be >= world_dt";
  { (Config.with_output_dir Config.default_config cli.out_dir) with random_seed = cli.seed }

let handle_messages logger ev_ref e_on_comm queue caches now ready =
  List.iter
    (fun (m : Types.neighbor_msg) ->
      Neighbor_cache.ingest caches.(m.receiver_id) m;
      Logger.write_event logger ~now ~event:"MESSAGE_RECEIVED" ~uav_id:m.receiver_id
        ~other_id:m.sender_id ~value1:(now -. m.sent_time) ();
      ev_ref := e_on_comm !ev_ref (`Received (now -. m.sent_time)))
    ready;
  ignore queue

let run () =
  let cli = parse_cli () in
  let bundle = Mode_registry.by_name cli.mode in
  let cfg = make_config cli in
  let rng = Random_utils.make cfg.random_seed in
  let scenario = Scenario.load_file cli.scenario in
  let initial = Scenario.to_initial_states ~bundle ~cfg scenario in
  let world = World.create ~cfg ~bundle ~initial in
  let n = World.n_uavs world in
  let comm = Comm_model.create ~cfg ~n_uavs:n ~rng in
  let queue = Event_queue.create () in
  let caches = Array.init n (fun _ -> Neighbor_cache.create ()) in
  let sched = Planner_scheduler.create ~cfg ~n_uavs:n ~rng in
  let logger = Logger.create ~cfg ~bundle in
  let module P = (val bundle.planner : Planner_adapter.PLANNER_ADAPTER) in
  let module E = (val bundle.evaluator : Evaluation_model.EVALUATION_MODEL) in
  let module C = (val bundle.conflict : Conflict_model.CONFLICT_MODEL) in
  let pair_distance a b = C.pair_distance ~cfg a b in
  let is_conflict a b = C.is_conflict ~cfg a b in
  let ev = ref (E.empty cfg) in
  let last_cmd : Types.planner_command option array = Array.make n None in
  let now = ref 0.0 in
  while !now < cfg.max_time && not (World.all_finished world) do
    World.step world ~now:!now ~dt:cfg.world_dt;
    let true_states = World.all_states_for_evaluator world in
    let msgs =
      Comm_model.maybe_broadcast comm ~now:!now ~true_states
        ~on_send:(fun m ->
          Logger.write_event logger ~now:!now ~event:"MESSAGE_SENT"
            ~uav_id:m.sender_id ~other_id:m.receiver_id ();
          ev := E.on_comm_event !ev `Sent)
        ~on_drop:(fun ~sender ~receiver ->
          Logger.write_event logger ~now:!now ~event:"MESSAGE_DROPPED"
            ~uav_id:sender ~other_id:receiver ();
          ev := E.on_comm_event !ev `Dropped)
    in
    List.iter (Event_queue.push queue) msgs;
    let ready = Event_queue.pop_ready queue ~now:!now in
    handle_messages logger ev E.on_comm_event queue caches !now ready;
    Planner_scheduler.due_uavs sched ~now:!now
    |> List.iter (fun uav_id ->
           let self = World.get_self_state world ~uav_id ~now:!now in
           let neighbors =
             Neighbor_cache.get_valid_neighbors caches.(uav_id) ~now:!now ~cfg
               ~self_id:uav_id
           in
           List.iter
             (fun obs ->
               if obs.Types.is_stale then
                 Logger.write_event logger ~now:!now ~event:"STALE_NEIGHBOR"
                   ~uav_id ~other_id:obs.id ~value1:obs.age ())
             neighbors;
           let t0 = Sys.time () in
           let cmd =
             P.plan_once ~cfg ~now:!now ~self ~neighbors ~last_command:last_cmd.(uav_id)
           in
           let cmd = { cmd with compute_time_ms = (Sys.time () -. t0) *. 1000.0 } in
           Logger.write_event logger ~now:!now ~event:"PLAN_DONE" ~uav_id
             ~value1:cmd.compute_time_ms ();
           World.set_command world cmd;
           last_cmd.(uav_id) <- Some cmd;
           ev := E.on_planning !ev ~cmd;
           Planner_scheduler.schedule_next sched ~uav_id ~now:!now);
    ev :=
      E.on_step !ev ~now:!now ~states:true_states ~pair_distance ~is_conflict;
    Logger.write_state_row logger ~now:!now ~states:true_states;
    now := !now +. cfg.world_dt
  done;
  Logger.write_summary logger ~scenario:scenario.name ~seed:cfg.random_seed
    ~mode:bundle.mode_name ~summary_row:(E.summary_row !ev ~cfg);
  Logger.close logger

let () = run ()
