(* ORCA-style layered planner core adapted from ../ORCA-ORIGIN. *)

type v2 = { x : float; y : float }

type constraint_ = {
  shift : v2;
  normal : v2;
  range : float;
}

type result = {
  target_vel : Vec3.t;
  target_level : int;
  start_level_change : bool;
  theta_used : float option;
  emergency : bool;
}

let epsilon = 1e-9
let facets = 20
let horizon = 50.0
let relax_angles = [| Float.pi /. 4.0; Float.pi /. 2.0 |]
let w = 2.0

let make x y = { x; y }
let of_vec3_xy (p : Vec3.t) : v2 = { x = p.x; y = p.y }
let to_vec3_xy (v : v2) : Vec3.t = Vec3.{ x = v.x; y = v.y; z = 0.0 }
let add a b = { x = a.x +. b.x; y = a.y +. b.y }
let sub a b = { x = a.x -. b.x; y = a.y -. b.y }
let scale k v = { x = k *. v.x; y = k *. v.y }
let dot a b = (a.x *. b.x) +. (a.y *. b.y)
let cross a b = (a.x *. b.y) -. (a.y *. b.x)
let norm_sq v = dot v v
let norm v = sqrt (norm_sq v)
let distance a b = norm (sub a b)

let normalize v =
  let n = norm v in
  if n <= epsilon then { x = 1.0; y = 0.0 } else scale (1.0 /. n) v

let clamp lo hi x = max lo (min hi x)

let angle_between a b =
  let na = norm a in
  let nb = norm b in
  if na <= epsilon || nb <= epsilon then 0.0
  else
    let c = dot a b /. (na *. nb) |> clamp (-1.0) 1.0 in
    acos c

let projection_length u v =
  let vv = norm_sq v in
  if vv <= epsilon then 0.0 else abs_float (dot u v /. sqrt vv)

let point_in_half_plane point p n =
  dot (sub point p) n >= -.epsilon

let segment_line_intersection a b p n =
  let da = dot (sub a p) n in
  let db = dot (sub b p) n in
  let denom = da -. db in
  if abs_float denom <= epsilon then a
  else
    let t = da /. denom in
    add a (scale t (sub b a))

let clip_polygon poly p n =
  match poly with
  | [] -> []
  | first :: _ ->
      let rec loop acc prev prev_inside = function
        | [] ->
            let first_inside = point_in_half_plane first p n in
            let acc =
              match (prev_inside, first_inside) with
              | true, true -> acc
              | true, false -> segment_line_intersection prev first p n :: acc
              | false, true ->
                  first :: segment_line_intersection prev first p n :: acc
              | false, false -> acc
            in
            List.rev acc
        | cur :: rest ->
            let cur_inside = point_in_half_plane cur p n in
            let acc =
              match (prev_inside, cur_inside) with
              | true, true -> cur :: acc
              | true, false -> segment_line_intersection prev cur p n :: acc
              | false, true ->
                  cur :: segment_line_intersection prev cur p n :: acc
              | false, false -> acc
            in
            loop acc cur cur_inside rest
      in
      loop [] first (point_in_half_plane first p n) (List.tl poly)

let polygon_contains p poly =
  let rec loop has_pos has_neg = function
    | a :: (b :: _ as rest) ->
        let c = cross (sub b a) (sub p a) in
        loop (has_pos || c > epsilon) (has_neg || c < -.epsilon) rest
    | [ a ] -> (
        match poly with
        | b :: _ ->
            let c = cross (sub b a) (sub p a) in
            not ((has_pos || c > epsilon) && (has_neg || c < -.epsilon))
        | [] -> false)
    | [] -> false
  in
  match poly with [] | [ _ ] -> false | _ -> loop false false poly

let project_point_to_segment p a b =
  let ab = sub b a in
  let ab2 = norm_sq ab in
  if ab2 <= epsilon then a
  else
    let t = dot (sub p a) ab /. ab2 |> clamp 0.0 1.0 in
    add a (scale t ab)

let project_to_polygon p poly =
  match poly with
  | [] -> p
  | first :: _ ->
      let best_point = ref first in
      let best_dist = ref infinity in
      let consider a b =
        let q = project_point_to_segment p a b in
        let d = distance p q in
        if d < !best_dist then (
          best_dist := d;
          best_point := q)
      in
      let rec loop = function
        | a :: (b :: _ as rest) ->
            consider a b;
            loop rest
        | [ a ] -> consider a first
        | [] -> ()
      in
      loop poly;
      !best_point

let project_velocity preferred poly =
  if polygon_contains preferred poly then preferred else project_to_polygon preferred poly

let speed_box ~max_speed ~heading =
  let n = norm heading in
  let angle = if n <= epsilon then 0.0 else atan2 heading.y heading.x in
  Array.init (facets + 1) (fun i ->
      let a = angle +. (float_of_int i *. 2.0 *. Float.pi /. float_of_int facets) in
      { x = max_speed *. cos a; y = max_speed *. sin a })
  |> Array.to_list

let escape_constraint ~dt ~max_speed ~separation pa sa pb sb =
  let rec loop tau sep =
    if tau <= dt || sep <= epsilon then None
    else
      let pr = sub pb pa in
      let npr = norm pr in
      if npr < sep then loop (tau -. dt) (sep -. (2.0 *. max_speed *. dt))
      else
        let prbis = scale (1.0 /. tau) pr in
        let nprbis = norm prbis in
        let vr = sub sa sb in
        let nvr = norm vr in
        let vrbis = sub vr prbis in
        let nvrbis = norm vrbis in
        let neutral () =
          let dir =
            if nvrbis <= epsilon then normalize prbis else scale (1.0 /. nvrbis) vrbis
          in
          let normal = scale (1.0 /. w) dir in
          let radius = (sep /. tau) -. nvrbis in
          Some { shift = scale radius normal; normal; range = npr }
        in
        if npr <= epsilon then neutral ()
        else
          let ratio = sep /. npr |> clamp (-1.0) 1.0 in
          let theta = asin ratio in
          let npa = atan2 pr.y pr.x in
          let nva = atan2 vr.y vr.x in
          let npa1 = npa -. theta in
          let npa2 = npa +. theta in
          let p1 =
            {
              x = nprbis *. cos theta *. cos npa1;
              y = nprbis *. cos theta *. sin npa1;
            }
          in
          let p2 =
            {
              x = nprbis *. cos theta *. cos npa2;
              y = nprbis *. cos theta *. sin npa2;
            }
          in
          if cross (sub p1 prbis) (sub vr prbis) > 0.0
             && cross (sub vr prbis) (sub pr prbis) >= 0.0
          then
            let alpha = nva -. npa1 in
            let nvrsa = nvr *. sin alpha in
            let normal =
              { x = cos (npa1 -. (Float.pi /. 2.0)) /. w; y = sin (npa1 -. (Float.pi /. 2.0)) /. w }
            in
            Some { shift = scale nvrsa normal; normal; range = npr }
          else if cross (sub pr prbis) (sub vr prbis) > 0.0
                  && cross (sub vr prbis) (sub p2 prbis) >= 0.0
          then
            let alpha = npa2 -. nva in
            let nvrsa = nvr *. sin alpha in
            let normal =
              { x = cos (npa2 +. (Float.pi /. 2.0)) /. w; y = sin (npa2 +. (Float.pi /. 2.0)) /. w }
            in
            Some { shift = scale nvrsa normal; normal; range = npr }
          else neutral ()
  in
  loop horizon separation

let cut_constraints ~limit_range initbox speed constraints =
  let rec attempt constraints =
    let box = ref initbox in
    try
      List.iter
        (fun c ->
          let p = add speed c.shift in
          let next = clip_polygon !box p c.normal in
          if next = [] then raise Exit;
          box := next)
        constraints;
      Some !box
    with Exit -> (
      match constraints with
      | [] -> None
      | c :: rest ->
          if c.range < limit_range then None else attempt rest)
  in
  attempt constraints

let occupied_levels_of_z cfg z =
  let spacing = max epsilon cfg.Types.layer_spacing in
  let raw = z /. spacing in
  let lo = int_of_float (floor raw) in
  let hi = int_of_float (ceil raw) in
  let clamp_level l = max 0 (min (cfg.Types.layer_count - 1) l) in
  let lo = clamp_level lo in
  let hi = clamp_level hi in
  if lo = hi || abs_float (raw -. float_of_int lo) < 1e-4 then [ lo ] else [ lo; hi ]

let current_level_of_self (self : Types.self_state) =
  match self.mode_state with
  | Types.Layered { current_level; transition = Types.LevelStable } ->
      `Stable current_level
  | Types.Layered
      { transition = Types.LevelChanging { from_level; target_level; _ }; _ } ->
      `Changing (from_level, target_level)
  | Types.Continuous3D ->
      failwith "Layered_orca called on Continuous3D state"

let preferred_velocity ~cfg (self : Types.self_state) =
  let delta = Vec3.sub self.goal self.pos in
  let dist = Vec3.norm_xy delta in
  if dist <= epsilon then make 0.0 0.0
  else
    make
      (delta.x *. self.uav_type.vmax /. dist)
      (delta.y *. self.uav_type.vmax /. dist)

let will_enter_separation ~horizon ~separation pa va pb vb =
  let p0 = sub pb pa in
  let v = sub vb va in
  let v2 = norm_sq v in
  let t =
    if v2 <= epsilon then 0.0 else -.dot p0 v /. v2 |> clamp 0.0 horizon
  in
  let p = add p0 (scale t v) in
  norm_sq p < separation *. separation

let level_is_safe ~cfg ~separation ~self_pos ~candidate_speed ~neighbors level =
  List.for_all
    (fun (n : Types.neighbor_observation) ->
      (not (List.mem level (occupied_levels_of_z cfg n.pos.z)))
      ||
      Vec3.distance_xy self_pos n.pos >= separation
      && not
           (will_enter_separation ~horizon ~separation (of_vec3_xy self_pos)
              candidate_speed (of_vec3_xy n.pos) (of_vec3_xy n.vel)))
    neighbors

let condition_of_velocity ~max_speed preferred theta candidate =
  angle_between preferred candidate < theta
  && projection_length candidate preferred > max_speed /. 4.0

let solve ~cfg ~now:_ ~(self : Types.self_state) ~neighbors ~last_command:_ =
  let source_level, forced_target, stable_level =
    match current_level_of_self self with
    | `Stable current_level -> (current_level, None, Some current_level)
    | `Changing (from_level, target_level) ->
        (from_level, Some target_level, None)
  in
      let max_speed = self.uav_type.vmax in
      let preferred = preferred_velocity ~cfg self in
      let current_speed = of_vec3_xy self.vel in
      let heading = if norm current_speed <= epsilon then preferred else current_speed in
      let limit_range = cfg.Types.safety_radius +. (max_speed *. horizon) in
      let constraints_by_level =
        Array.init cfg.Types.layer_count (fun _ -> ([] : constraint_ list))
      in
      let self_pos = of_vec3_xy self.pos in
      List.iter
        (fun (n : Types.neighbor_observation) ->
          let neighbor_pos = of_vec3_xy n.pos in
          let neighbor_vel = of_vec3_xy n.vel in
          let separation =
            max cfg.Types.safety_radius (self.uav_type.radius +. n.effective_radius)
          in
          match
            escape_constraint ~dt:cfg.world_dt ~max_speed ~separation
              self_pos current_speed neighbor_pos neighbor_vel
          with
          | None -> ()
          | Some c ->
              List.iter
                (fun lvl ->
                  constraints_by_level.(lvl) <- c :: constraints_by_level.(lvl))
                (occupied_levels_of_z cfg n.pos.z))
        neighbors;
      for lvl = 0 to cfg.Types.layer_count - 1 do
        constraints_by_level.(lvl) <-
          List.sort
            (fun a b -> compare b.range a.range)
            constraints_by_level.(lvl)
      done;
      let initbox = speed_box ~max_speed ~heading in
      let solve_level lvl =
        if lvl < 0 || lvl >= cfg.Types.layer_count then None
        else
          let constraints =
            match forced_target with
            | Some _ when lvl <> source_level ->
                constraints_by_level.(source_level) @ constraints_by_level.(lvl)
            | _ -> constraints_by_level.(lvl)
          in
          match
            cut_constraints ~limit_range initbox current_speed constraints
          with
          | None -> None
          | Some box ->
              let candidate = project_velocity preferred box in
              Some (lvl, candidate)
      in
      let try_level theta lvl =
        match solve_level lvl with
        | Some (lvl, candidate)
          when condition_of_velocity ~max_speed preferred theta candidate
               && (lvl = source_level
                  || level_is_safe ~cfg
                       ~separation:cfg.Types.safety_radius ~self_pos:self.pos
                       ~candidate_speed:candidate ~neighbors lvl) ->
            Some (lvl, candidate)
        | _ -> None
      in
      let best_adjacent theta =
        let best = ref None in
        for
          lvl = max 0 (source_level - 1)
          to min (cfg.Types.layer_count - 1) (source_level + 1)
        do
          if lvl <> source_level then
            match try_level theta lvl with
            | None -> ()
            | Some (_, candidate) ->
                let angle = angle_between preferred candidate in
                (match !best with
                | None -> best := Some (angle, lvl, candidate)
                | Some (best_angle, _, _) when angle < best_angle ->
                    best := Some (angle, lvl, candidate)
                | _ -> ())
        done;
        match !best with
        | None -> None
        | Some (_, lvl, candidate) -> Some (lvl, candidate)
      in
      let choose theta =
        match forced_target with
        | Some target_level -> try_level theta target_level
        | None -> (
            match try_level theta source_level with
            | Some _ as ok -> ok
            | None -> best_adjacent theta)
      in
      let rec choose_with_relax idx =
        if idx >= Array.length relax_angles then None
        else
          let theta = relax_angles.(idx) in
          match choose theta with
          | Some (lvl, candidate) -> Some (theta, lvl, candidate)
          | None -> choose_with_relax (idx + 1)
      in
      match choose_with_relax 0 with
      | Some (theta, lvl, candidate) ->
          let start_level_change =
            match stable_level with
            | Some current_level -> lvl <> current_level
            | None -> false
          in
          {
            target_vel = to_vec3_xy candidate;
            target_level = lvl;
            start_level_change;
            theta_used = Some theta;
            emergency = false;
          }
      | None ->
          let current_level =
            match stable_level with
            | Some current_level -> current_level
            | None -> source_level
          in
          {
            target_vel = to_vec3_xy preferred;
            target_level = current_level;
            start_level_change = false;
            theta_used = None;
            emergency = true;
          }
