#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

WATER_MODEL_GRO="${WATER_MODEL_GRO:-spc216.gro}"
ION_CONC="${ION_CONC:-0.15}"
PNAME="${PNAME:-NA}"
NNAME="${NNAME:-CL}"

ensure_dirs
require_command "$GMX"
require_file "$TOPOLOGY"
require_file "$BUILD_DIR/system_unsolvated.gro"

solvated="$BUILD_DIR/system_solvated.gro"
ions_tpr="$BUILD_DIR/ions.tpr"
with_ions="$BUILD_DIR/system_ions.gro"

cd "$ROOT_DIR/topology"
"$GMX" solvate -cp "$BUILD_DIR/system_unsolvated.gro" -cs "$WATER_MODEL_GRO" -o "$solvated" -p "$TOPOLOGY"
"$GMX" grompp -f "$ROOT_DIR/mdp/ions.mdp" -c "$solvated" -p "$TOPOLOGY" -o "$ions_tpr" -maxwarn "${MAXWARN:-0}"
printf 'SOL\n' | "$GMX" genion -s "$ions_tpr" -o "$with_ions" -p "$TOPOLOGY" -pname "$PNAME" -nname "$NNAME" -neutral -conc "$ION_CONC"

printf 'Wrote %s\n' "$with_ions"
