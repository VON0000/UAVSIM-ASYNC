(* Runtime mode registry tying together airspace, conflict, motion, planner, evaluator. *)

type mode_bundle = {
  mode_name : string;
  airspace : (module Airspace_model.AIRSPACE_MODEL);
  conflict : (module Conflict_model.CONFLICT_MODEL);
  motion : (module Motion_model.MOTION_MODEL);
  planner : (module Planner_adapter.PLANNER_ADAPTER);
  evaluator : (module Evaluation_model.EVALUATION_MODEL);
}

let layered =
  {
    mode_name = "layered";
    airspace = (module Layered_airspace);
    conflict = (module Layered_conflict);
    motion = (module Layered_motion);
    planner = (module Layered_planner_adapter);
    evaluator = (module Layered_evaluation);
  }

let continuous3d =
  {
    mode_name = "continuous3d";
    airspace = (module Continuous3d_airspace);
    conflict = (module Continuous3d_conflict);
    motion = (module Continuous3d_motion);
    planner = (module Continuous3d_planner_adapter);
    evaluator = (module Continuous3d_evaluation);
  }

let by_name = function
  | "layered" -> layered
  | "continuous3d" -> continuous3d
  | other -> invalid_arg ("unknown mode: " ^ other)
