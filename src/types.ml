(* Shared simulator data types crossing mode, world, comm, planner, and logs. *)

type v2 = { x : float; y : float }

type uav_type_params = {
  type_name : string;
  vmax : float;
  amax_xy : float;
  az_up_max : float;
  az_down_max : float;
  jerk_max : float;
  yaw_rate_max : float;
  yaw_acc_max : float;
  climb_rate_max : float;
  radius : float;
}

type transition_state =
  | LevelStable
  | LevelChanging of {
      from_level : int;
      target_level : int;
      target_z : float;
      steps_total : int;
      steps_left : int;
    }

type layered_state = {
  current_level : int;
  transition : transition_state;
}

type mode_state =
  | Layered of layered_state
  | Continuous3D

type uav_state = {
  id : int;
  pos : Vec3.t;
  vel : Vec3.t;
  acc : Vec3.t;
  yaw : float;
  yaw_rate : float;
  mode_state : mode_state;
  goal : Vec3.t;
  active : bool;
  reached : bool;
  stalled : bool;
  uav_type : uav_type_params;
}

type self_state = {
  id : int;
  stamp : float;
  pos : Vec3.t;
  vel : Vec3.t;
  acc : Vec3.t;
  yaw : float;
  yaw_rate : float;
  mode_state : mode_state;
  goal : Vec3.t;
  uav_type : uav_type_params;
}

type neighbor_msg = {
  sender_id : int;
  receiver_id : int;
  sent_time : float;
  receive_time : float;
  pos : Vec3.t;
  vel : Vec3.t;
  radius : float;
}

type neighbor_observation = {
  id : int;
  pos : Vec3.t;
  vel : Vec3.t;
  radius : float;
  effective_radius : float;
  age : float;
  is_stale : bool;
}

type planner_command = {
  uav_id : int;
  stamp : float;
  target_vel : Vec3.t;
  target_level : int option;
  start_level_change : bool;
  emergency : bool;
  theta_used : float option;
  compute_time_ms : float;
}

type sim_config = {
  world_dt : float;
  max_time : float;
  planner_period : float;
  planner_jitter : float;
  stale_timeout : float;
  broadcast_rate : float;
  delay_mean : float;
  delay_jitter : float;
  packet_loss : float;
  comm_range : float;
  k_delay_radius : float;
  layer_spacing : float;
  layer_count : int;
  safety_radius : float;
  random_seed : int;
  state_log_path : string;
  event_log_path : string;
  summary_log_path : string;
}
