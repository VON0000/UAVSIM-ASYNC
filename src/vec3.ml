(* Basic 3D vector operations shared by all simulator modules. *)

type t = { x : float; y : float; z : float }

let zero = { x = 0.0; y = 0.0; z = 0.0 }

let make x y z = { x; y; z }

let add a b = { x = a.x +. b.x; y = a.y +. b.y; z = a.z +. b.z }

let sub a b = { x = a.x -. b.x; y = a.y -. b.y; z = a.z -. b.z }

let scale k v = { x = k *. v.x; y = k *. v.y; z = k *. v.z }

let dot a b = (a.x *. b.x) +. (a.y *. b.y) +. (a.z *. b.z)

let norm_sq v = dot v v

let norm v = sqrt (norm_sq v)

let norm_xy v = sqrt ((v.x *. v.x) +. (v.y *. v.y))

let distance a b = norm (sub a b)

let distance_xy a b = norm_xy (sub a b)

let normalize v =
  let n = norm v in
  if n <= 1e-9 then zero else scale (1.0 /. n) v

let lerp a b t = add a (scale t (sub b a))
