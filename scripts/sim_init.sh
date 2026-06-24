#!/usr/bin/env bash
# Scaffold a new per-simulation directory under simulations/<sim-id>/.
# Usage: scripts/sim_init.sh <sim-id>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

sim_id="${1:-}"
[[ -n "$sim_id" ]] || { printf 'Usage: %s <sim-id>\n' "$0" >&2; exit 1; }

sim_dir="$ROOT_DIR/simulations/$sim_id"
[[ ! -e "$sim_dir" ]] || { printf 'ERROR: %s already exists\n' "$sim_dir" >&2; exit 1; }

mkdir -p \
  "$sim_dir/inputs/ligpargen" \
  "$sim_dir/topology" \
  "$sim_dir/build" \
  "$sim_dir/runs/em" \
  "$sim_dir/runs/nvt" \
  "$sim_dir/runs/npt" \
  "$sim_dir/runs/production" \
  "$sim_dir/logs"

cp "$ROOT_DIR/inputs/molecules.csv" "$sim_dir/inputs/molecules.csv"

cat > "$sim_dir/inputs/ligpargen/README.md" <<'EOF'
Place LigParGen-generated .gro and .itp files here, one pair per molecule.
EOF

today=$(date +%Y-%m-%d)
cat > "$sim_dir/README.md" <<EOF
# $sim_id

Created: $today

## Purpose

<!-- Describe this simulation: molecules, concentrations, box size, variations. -->

## Composition

<!-- e.g.
Solute:   40 PFOA molecules
Water:    added by gmx solvate
Ions:     NA/CL at 0.15 M (gmx genion)
-->

## Box

<!-- e.g. 8 x 8 x 8 nm -->

## Inputs

<!-- List the LigParGen .gro/.itp files used and their origin. -->

## Notes

<!-- Record grompp warnings, topology edits, duplicate-atomtype handling, etc. -->
EOF

printf 'Initialized %s\n' "$sim_dir"
printf '\nNext steps:\n'
printf '  1. Place LigParGen files in simulations/%s/inputs/ligpargen/\n' "$sim_id"
printf '  2. Edit simulations/%s/inputs/molecules.csv\n' "$sim_id"
printf '  3. SIM_DIR=simulations/%s scripts/01_build_with_packmol.sh\n' "$sim_id"
printf '  4. SIM_DIR=simulations/%s scripts/02_solvate_and_ionize.sh\n' "$sim_id"
printf '  5. SIM_DIR=simulations/%s scripts/03_run_md_pipeline.sh\n' "$sim_id"
