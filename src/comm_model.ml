(* Broadcast communication model for delayed neighbor observations. *)

type t = {
  cfg : Types.sim_config;
  rng : Random_utils.t;
  mutable next_broadcast : float array;
}

let create ~cfg ~n_uavs ~rng =
  let period =
    if cfg.Types.broadcast_rate <= 0.0 then infinity
    else 1.0 /. cfg.broadcast_rate
  in
  {
    cfg;
    rng;
    next_broadcast = Array.init n_uavs (fun i -> float_of_int i *. period /. max 1.0 (float_of_int n_uavs));
  }

let in_range cfg (a : Types.uav_state) (b : Types.uav_state) =
  cfg.Types.comm_range = infinity || Vec3.distance a.Types.pos b.Types.pos <= cfg.comm_range

let make_msg t ~now (sender : Types.uav_state) (receiver : Types.uav_state) =
  let delay =
    max 0.0
      (t.cfg.Types.delay_mean
      +. Random_utils.uniform t.rng (-.t.cfg.delay_jitter) t.cfg.delay_jitter)
  in
  {
    Types.sender_id = sender.Types.id;
    receiver_id = receiver.Types.id;
    sent_time = now;
    receive_time = now +. delay;
    pos = sender.pos;
    vel = sender.vel;
    radius = sender.uav_type.radius;
  }

let maybe_broadcast t ~now ~true_states ~on_send ~on_drop =
  let period =
    if t.cfg.Types.broadcast_rate <= 0.0 then infinity
    else 1.0 /. t.cfg.broadcast_rate
  in
  let emitted = ref [] in
  Array.iteri
    (fun i (sender : Types.uav_state) ->
      if sender.Types.active && now +. 1e-9 >= t.next_broadcast.(i) then (
        t.next_broadcast.(i) <- now +. period;
        Array.iter
          (fun (receiver : Types.uav_state) ->
            if receiver.Types.id <> sender.id then
              if (not (in_range t.cfg sender receiver))
                 || Random_utils.bernoulli t.rng t.cfg.packet_loss
              then on_drop ~sender:sender.id ~receiver:receiver.id
              else
                let msg = make_msg t ~now sender receiver in
                on_send msg;
                emitted := msg :: !emitted)
          true_states))
    true_states;
  List.rev !emitted
