#!/usr/bin/env python3
"""Lightweight checks for the generic LigParGen/GROMACS scaffold."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "inputs" / "molecules.csv"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_moleculetype(path: Path) -> str | None:
    lines = path.read_text().splitlines()
    in_section = False
    for line in lines:
        stripped = line.split(";", 1)[0].strip()
        if not stripped:
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped.strip("[]").strip() == "moleculetype"
            continue
        if in_section:
            return stripped.split()[0]
    return None


def gro_resnames(path: Path) -> set[str]:
    lines = path.read_text().splitlines()
    resnames: set[str] = set()
    for line in lines[2:-1]:
        if len(line) >= 10:
            token = line[:10]
            match = re.match(r"\s*\d+([A-Za-z0-9_+-]+)", token)
            if match:
                resnames.add(match.group(1))
    return resnames


def main() -> None:
    if not CSV_PATH.exists():
        fail(f"Missing molecule inventory: {CSV_PATH.relative_to(ROOT)}")

    rows = list(csv.DictReader(CSV_PATH.open()))
    if not rows:
        fail("inputs/molecules.csv has no molecule rows")

    required = {"name", "resname", "gro", "itp", "count", "charge"}
    missing = required - set(rows[0].keys())
    if missing:
        fail(f"inputs/molecules.csv is missing columns: {', '.join(sorted(missing))}")

    names: set[str] = set()
    total_charge = 0.0

    for row in rows:
        name = row["name"].strip()
        resname = row["resname"].strip()
        gro = ROOT / row["gro"].strip()
        itp = ROOT / row["itp"].strip()

        if not name:
            fail("Found row with empty molecule name")
        if name in names:
            fail(f"Duplicate molecule name in inventory: {name}")
        names.add(name)

        if not gro.exists():
            fail(f"Missing .gro for {name}: {gro.relative_to(ROOT)}")
        if not itp.exists():
            fail(f"Missing .itp for {name}: {itp.relative_to(ROOT)}")

        try:
            count = int(row["count"])
        except ValueError:
            fail(f"Invalid count for {name}: {row['count']}")
        if count < 0:
            fail(f"Negative count for {name}: {count}")

        try:
            charge = float(row["charge"])
        except ValueError:
            fail(f"Invalid charge for {name}: {row['charge']}")
        total_charge += count * charge

        moleculetype = read_moleculetype(itp)
        if moleculetype != name:
            fail(
                f"{itp.relative_to(ROOT)} moleculetype is {moleculetype!r}, "
                f"but inventory name is {name!r}"
            )

        residues = gro_resnames(gro)
        if resname and resname not in residues:
            print(
                f"WARNING: {gro.relative_to(ROOT)} does not appear to contain "
                f"residue {resname!r}; found {sorted(residues)}",
                file=sys.stderr,
            )

    print(f"Validated {len(rows)} molecule definitions.")
    print(f"Expected solute charge before ions: {total_charge:g}")


if __name__ == "__main__":
    main()

