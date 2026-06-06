(* Minimal event queue; list-backed is sufficient for the scaffold. *)

type t = { mutable messages : Types.neighbor_msg list }

let create () = { messages = [] }

let push t msg = t.messages <- msg :: t.messages

let pop_ready t ~now =
  let ready, pending =
    List.partition (fun m -> m.Types.receive_time <= now) t.messages
  in
  t.messages <- pending;
  List.sort
    (fun a b -> compare a.Types.receive_time b.Types.receive_time)
    ready
