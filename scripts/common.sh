#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GMX="${GMX:-gmx}"
MOLECULES_CSV="${MOLECULES_CSV:-$ROOT_DIR/inputs/molecules.csv}"
TOPOLOGY="$ROOT_DIR/topology/system.top"
BUILD_DIR="$ROOT_DIR/build"
RUNS_DIR="$ROOT_DIR/runs"

BOX_X="${BOX_X:-6}"
BOX_Y="${BOX_Y:-6}"
BOX_Z="${BOX_Z:-6}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || die "Missing file: $1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

ensure_dirs() {
  mkdir -p "$BUILD_DIR" "$RUNS_DIR"/{em,nvt,npt,production}
}

csv_rows() {
  require_file "$MOLECULES_CSV"
  tail -n +2 "$MOLECULES_CSV" | awk 'NF && $0 !~ /^#/'
}

write_topology_from_csv() {
  {
    printf '; Generated from inputs/molecules.csv\n\n'
    printf '#include "oplsaa.ff/forcefield.itp"\n\n'
    printf '; LigParGen solute topologies.\n'
    csv_rows | while IFS=, read -r name resname gro itp count charge; do
      [[ -n "${name:-}" ]] || continue
      printf '#include "../%s"\n' "$itp"
    done
    printf '\n'
    printf '#include "oplsaa.ff/tip3p.itp"\n'
    printf '#include "oplsaa.ff/ions.itp"\n\n'
    printf '[ system ]\n'
    printf 'PFAS and organic molecules in TIP3P water\n\n'
    printf '[ molecules ]\n'
    printf '; name      count\n'
    csv_rows | while IFS=, read -r name resname gro itp count charge; do
      [[ -n "${name:-}" ]] || continue
      printf '%-10s %s\n' "$name" "$count"
    done
  } > "$TOPOLOGY"
}

append_or_replace_molecule_count() {
  local molecule="$1"
  local count="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v mol="$molecule" -v count="$count" '
    BEGIN { in_molecules = 0; replaced = 0 }
    /^\[ *molecules *\]/ { in_molecules = 1; print; next }
    /^\[/ && in_molecules { in_molecules = 0 }
    in_molecules && $1 == mol { printf "%-10s %s\n", mol, count; replaced = 1; next }
    { print }
    END {
      if (!replaced) {
        printf "%-10s %s\n", mol, count
      }
    }
  ' "$TOPOLOGY" > "$tmp"
  mv "$tmp" "$TOPOLOGY"
}
