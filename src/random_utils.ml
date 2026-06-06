(* Seeded random helpers. All simulator randomness should flow through here. *)

type t = Random.State.t

let make seed = Random.State.make [| seed |]

let uniform rng low high = low +. ((high -. low) *. Random.State.float rng 1.0)

let uniform_01 rng = uniform rng 0.0 1.0

let bernoulli rng p =
  if p <= 0.0 then false
  else if p >= 1.0 then true
  else Random.State.float rng 1.0 < p

let normal rng mean std =
  let u1 = max 1e-12 (Random.State.float rng 1.0) in
  let u2 = Random.State.float rng 1.0 in
  let z0 = sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2) in
  mean +. (std *. z0)

let int_below rng n = Random.State.int rng n
