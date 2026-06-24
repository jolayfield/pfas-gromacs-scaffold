#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

PACKMOL="${PACKMOL:-packmol}"
PACKMOL_TOLERANCE="${PACKMOL_TOLERANCE:-2.0}"

ensure_dirs
write_provenance
require_command "$GMX"
require_command "$PACKMOL"
require_file "$MOLECULES_CSV"

"$ROOT_DIR/scripts/validate_gromacs_inputs.py"
write_topology_from_csv

packmol_input="$BUILD_DIR/packmol.inp"
packmol_pdb="$BUILD_DIR/system_unsolvated.pdb"
unsolvated_gro="$BUILD_DIR/system_unsolvated.gro"

# Convert each molecule .gro to .pdb before writing packmol.inp.
# packmol.inp uses only basenames to stay within Packmol's 90-char
# internal filename buffer; Packmol is run from BUILD_DIR to find them.
csv_rows | while IFS=, read -r name resname gro itp count charge; do
  [[ -n "${name:-}" ]] || continue
  "$GMX" editconf -f "$SIM_DIR/$gro" -o "$BUILD_DIR/${name}.pdb" >/dev/null 2>&1
done

{
  printf 'tolerance %s\n' "$PACKMOL_TOLERANCE"
  printf 'filetype pdb\n'
  printf 'output system_unsolvated.pdb\n\n'

  csv_rows | while IFS=, read -r name resname gro itp count charge; do
    [[ -n "${name:-}" ]] || continue
    printf 'structure %s\n' "${name}.pdb"
    printf '  number %s\n' "$count"
    printf '  inside box 0. 0. 0. %.3f %.3f %.3f\n' \
      "$(awk "BEGIN {print $BOX_X * 10}")" \
      "$(awk "BEGIN {print $BOX_Y * 10}")" \
      "$(awk "BEGIN {print $BOX_Z * 10}")"
    printf 'end structure\n\n'
  done
} > "$packmol_input"

(cd "$BUILD_DIR" && "$PACKMOL" < "$packmol_input")
"$GMX" editconf -f "$packmol_pdb" -o "$unsolvated_gro" -box "$BOX_X" "$BOX_Y" "$BOX_Z"

printf 'Wrote %s\n' "$unsolvated_gro"

