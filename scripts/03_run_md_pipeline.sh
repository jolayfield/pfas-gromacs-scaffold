#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

ensure_dirs
write_provenance

if [[ "$USE_QGMX" == "1" ]]; then
  require_command "$QGMX"
else
  require_command "$GMX"
fi

require_file "$TOPOLOGY"
require_file "$BUILD_DIR/system_ions.gro"

cd "$(dirname "$TOPOLOGY")"

run_stage() {
  local stage="$1"
  local mdp="$2"
  local input_gro="$3"
  local ref_gro="${4:-}"

  local dir_name
  case "$stage" in
    em)         dir_name="01_em" ;;
    nvt)        dir_name="02_nvt" ;;
    npt)        dir_name="03_npt" ;;
    production) dir_name="04_production" ;;
    *)          dir_name="$stage" ;;
  esac
  local dir="$RUNS_DIR/$dir_name"

  mkdir -p "$dir"

  if [[ "$USE_QGMX" == "1" ]]; then
    "$QGMX" \
      -f "$ROOT_DIR/mdp/$mdp" \
      -c "$input_gro" \
      -oc "$dir/$stage.gro" \
      -p "$TOPOLOGY" \
      -nt "$NPROCS"
  else
    if [[ -n "$ref_gro" ]]; then
      "$GMX" grompp -f "$ROOT_DIR/mdp/$mdp" -c "$input_gro" -r "$ref_gro" \
        -p "$TOPOLOGY" -o "$dir/$stage.tpr" -maxwarn "${MAXWARN:-0}"
    else
      "$GMX" grompp -f "$ROOT_DIR/mdp/$mdp" -c "$input_gro" \
        -p "$TOPOLOGY" -o "$dir/$stage.tpr" -maxwarn "${MAXWARN:-0}"
    fi
    "$GMX" mdrun -deffnm "$dir/$stage"
  fi
}

run_stage em        minim.mdp "$BUILD_DIR/system_ions.gro"
run_stage nvt       nvt.mdp   "$RUNS_DIR/01_em/em.gro"   "$RUNS_DIR/01_em/em.gro"
run_stage npt       npt.mdp   "$RUNS_DIR/02_nvt/nvt.gro" "$RUNS_DIR/02_nvt/nvt.gro"
run_stage production md.mdp   "$RUNS_DIR/03_npt/npt.gro"

printf 'Production output prefix: %s\n' "$RUNS_DIR/04_production/production"
