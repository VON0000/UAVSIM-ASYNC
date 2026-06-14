OCAMLFIND := ocamlfind
OCAMLOPT := $(OCAMLFIND) ocamlopt
PKGS := unix,str
BUILD := _build

SRC := \
  src/vec3.ml \
  src/random_utils.ml \
  src/types.ml \
  src/config.ml \
  src/airspace_model.ml \
  src/conflict_model.ml \
  src/motion_model.ml \
  src/planner_adapter.ml \
  src/evaluation_model.ml \
  src/layered_airspace.ml \
  src/layered_conflict.ml \
  src/layered_motion.ml \
  src/layered_orca.mli \
  src/layered_orca.ml \
  src/layered_planner_adapter.ml \
  src/continuous3d_airspace.ml \
  src/continuous3d_conflict.ml \
  src/continuous3d_motion.ml \
  src/continuous3d_planner_adapter.ml \
  src/layered_evaluation.ml \
  src/continuous3d_evaluation.ml \
  src/mode_registry.ml \
  src/event_queue.mli src/event_queue.ml \
  src/neighbor_cache.mli src/neighbor_cache.ml \
  src/comm_model.mli src/comm_model.ml \
  src/planner_scheduler.mli src/planner_scheduler.ml \
  src/world.mli src/world.ml \
  src/logger.mli src/logger.ml \
  src/scenario.mli src/scenario.ml

COMMON_CMX := $(patsubst %.ml,$(BUILD)/%.cmx,$(filter %.ml,$(SRC)))
INTERFACE_CMI := $(patsubst %.mli,$(BUILD)/%.cmi,$(filter %.mli,$(SRC)))

.PHONY: all clean dirs

all: dirs $(BUILD)/run_async $(BUILD)/run_batch $(BUILD)/export_rviz_log

dirs:
	mkdir -p $(BUILD)/src $(BUILD)/bin

$(BUILD)/%.cmi: %.mli | dirs
	$(OCAMLOPT) -package $(PKGS) -I $(BUILD)/src -c $< -o $@

$(BUILD)/%.cmx: %.ml | dirs
	$(OCAMLOPT) -package $(PKGS) -I $(BUILD)/src -c $< -o $@

$(BUILD)/src/event_queue.cmx: $(BUILD)/src/event_queue.cmi
$(BUILD)/src/neighbor_cache.cmx: $(BUILD)/src/neighbor_cache.cmi
$(BUILD)/src/comm_model.cmx: $(BUILD)/src/comm_model.cmi
$(BUILD)/src/planner_scheduler.cmx: $(BUILD)/src/planner_scheduler.cmi
$(BUILD)/src/layered_orca.cmx: $(BUILD)/src/layered_orca.cmi
$(BUILD)/src/world.cmx: $(BUILD)/src/world.cmi
$(BUILD)/src/logger.cmx: $(BUILD)/src/logger.cmi
$(BUILD)/src/scenario.cmx: $(BUILD)/src/scenario.cmi

$(BUILD)/run_async: $(COMMON_CMX) $(BUILD)/bin/run_async.cmx
	$(OCAMLOPT) -package $(PKGS) -linkpkg -I $(BUILD)/src $^ -o $@

$(BUILD)/run_batch: $(BUILD)/bin/run_batch.cmx
	$(OCAMLOPT) -package $(PKGS) -linkpkg $^ -o $@

$(BUILD)/export_rviz_log: $(BUILD)/bin/export_rviz_log.cmx
	$(OCAMLOPT) -package $(PKGS) -linkpkg $^ -o $@

clean:
	rm -rf $(BUILD)
