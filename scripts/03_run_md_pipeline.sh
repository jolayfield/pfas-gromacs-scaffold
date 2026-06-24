#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

ensure_dirs
require_command "$GMX"
require_file "$TOPOLOGY"
require_file "$BUILD_DIR/system_ions.gro"

cd "$(dirname "$TOPOLOGY")"

run_stage() {
  local stage="$1"
  local mdp="$2"
  local input_gro="$3"
  local extra_ref="${4:-}"
  local dir="$RUNS_DIR/$stage"

  mkdir -p "$dir"
  if [[ -n "$extra_ref" ]]; then
    "$GMX" grompp -f "$ROOT_DIR/mdp/$mdp" -c "$input_gro" -r "$extra_ref" -p "$TOPOLOGY" -o "$dir/$stage.tpr" -maxwarn "${MAXWARN:-0}"
  else
    "$GMX" grompp -f "$ROOT_DIR/mdp/$mdp" -c "$input_gro" -p "$TOPOLOGY" -o "$dir/$stage.tpr" -maxwarn "${MAXWARN:-0}"
  fi
  "$GMX" mdrun -deffnm "$dir/$stage"
}

run_stage em minim.mdp "$BUILD_DIR/system_ions.gro"
run_stage nvt nvt.mdp "$RUNS_DIR/em/em.gro" "$RUNS_DIR/em/em.gro"
run_stage npt npt.mdp "$RUNS_DIR/nvt/nvt.gro" "$RUNS_DIR/nvt/nvt.gro"
run_stage production md.mdp "$RUNS_DIR/npt/npt.gro"

printf 'Production output prefix: %s\n' "$RUNS_DIR/production/production"
