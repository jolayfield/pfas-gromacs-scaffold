#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

ensure_dirs
require_command "$GMX"
require_file "$MOLECULES_CSV"

"$ROOT_DIR/scripts/validate_gromacs_inputs.py"
write_topology_from_csv

current=""
index=0
csv_rows | while IFS=, read -r name resname gro itp count charge; do
  [[ -n "${name:-}" ]] || continue
  index=$((index + 1))
  next="$BUILD_DIR/insert_${index}_${name}.gro"
  if [[ "$index" -eq 1 ]]; then
    "$GMX" insert-molecules -box "$BOX_X" "$BOX_Y" "$BOX_Z" \
      -ci "$SIM_DIR/$gro" -nmol "$count" -o "$next"
  else
    "$GMX" insert-molecules -f "$current" -ci "$SIM_DIR/$gro" -nmol "$count" -o "$next"
  fi
  current="$next"
  cp "$current" "$BUILD_DIR/system_unsolvated.gro"
done

printf 'Wrote %s\n' "$BUILD_DIR/system_unsolvated.gro"
