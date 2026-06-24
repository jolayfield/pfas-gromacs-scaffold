# GROMACS Simulation Plan From LigParGen Files

Created: 2026-06-23

## Scope

This scaffold is for building generic GROMACS simulations of PFAS and other organic molecules in water from LigParGen-generated `.gro` and `.itp` files. It assumes:

- GROMACS command: `gmx`
- Force field family: OPLS-AA
- Water model: TIP3P-style water via the OPLS-AA topology includes
- Starting inputs: one `.gro` and one `.itp` per solute molecule
- System type: organic molecules and PFAS in bulk water

The scaffold supports two initial-placement paths:

- Packmol, recommended for mixed solute systems with multiple molecule types
- `gmx insert-molecules`, useful for simpler single-species or sequential insertion builds

## Directory Layout

```text
inputs/
  molecules.csv
  ligpargen/
    README.md

topology/
  system.top

packmol/
  packmol.inp.template

mdp/
  ions.mdp
  minim.mdp
  nvt.mdp
  npt.mdp
  md.mdp

scripts/
  common.sh
  validate_gromacs_inputs.py
  01_build_with_packmol.sh
  01_build_with_insert_molecules.sh
  02_solvate_and_ionize.sh
  03_run_md_pipeline.sh

build/
  generated coordinate files

runs/
  em/
  nvt/
  npt/
  production/
```

## Input Inventory

Place LigParGen files in `inputs/ligpargen/`. For each molecule, record one row in `inputs/molecules.csv`.

Required columns:

- `name`: GROMACS molecule name from the `.itp` `[ moleculetype ]` section
- `resname`: residue name used in the `.gro` coordinate file
- `gro`: path to the molecule coordinate file
- `itp`: path to the molecule topology file
- `count`: number of molecules to place
- `charge`: expected total charge per molecule

Before building the system, confirm:

- the `name` value matches the `[ moleculetype ]` name in the `.itp`
- the `.gro` file contains the expected residue name
- molecule counts match the intended concentration or composition
- net system charge is chemically sensible before ions are added

## Topology Strategy

The main topology is `topology/system.top`. It includes:

1. OPLS-AA force-field definitions
2. each LigParGen `.itp`
3. TIP3P water topology
4. ion topology
5. the final `[ molecules ]` count table

LigParGen `.itp` files sometimes contain overlapping `[ atomtypes ]` or force-field-level settings. If GROMACS reports duplicate atom types or conflicting defaults, inspect the relevant `.itp` files and consolidate shared definitions intentionally.

## Build Path A: Packmol

Use Packmol when the system contains multiple PFAS or organic molecules. The script `scripts/01_build_with_packmol.sh` reads `inputs/molecules.csv`, creates `build/packmol.inp`, and runs Packmol if available.

For the detailed version of this workflow, including why solvent and ions should usually be handled by GROMACS after Packmol places the solutes, see `docs/packmol-solute-workflow.md`.

Expected output:

```text
build/system_unsolvated.gro
```

Main settings are controlled through environment variables:

- `BOX_X`, `BOX_Y`, `BOX_Z`: box lengths in nm
- `PACKMOL_TOLERANCE`: minimum atom-atom tolerance in angstrom
- `GMX`: GROMACS command, default `gmx`

Example:

```bash
BOX_X=8 BOX_Y=8 BOX_Z=8 scripts/01_build_with_packmol.sh
```

## Build Path B: `gmx insert-molecules`

Use `scripts/01_build_with_insert_molecules.sh` for a GROMACS-only build path. It inserts molecules sequentially into a box.

This path is simpler to run but can struggle with dense systems or complex mixtures. For difficult packing, use Packmol.

Example:

```bash
BOX_X=8 BOX_Y=8 BOX_Z=8 scripts/01_build_with_insert_molecules.sh
```

## Solvation And Ionization

After creating `build/system_unsolvated.gro`, run:

```bash
scripts/02_solvate_and_ionize.sh
```

The script:

1. solvates the box
2. updates solvent count in `topology/system.top`
3. prepares an ionization `.tpr`
4. replaces water molecules with ions
5. writes `build/system_ions.gro`

Useful variables:

- `WATER_MODEL_GRO`: solvent coordinate template, default `spc216.gro`
- `ION_CONC`: salt concentration in mol/L, default `0.15`
- `PNAME`: cation name, default `NA`
- `NNAME`: anion name, default `CL`

## Minimization, Equilibration, And Production

Run:

```bash
scripts/03_run_md_pipeline.sh
```

The pipeline stages are:

1. energy minimization
2. NVT equilibration
3. NPT equilibration
4. short production run

The starter `.mdp` files are intentionally conservative and short. Treat them as validation settings, not final publication settings.

## Validation Checklist

Before trusting any trajectory, verify:

- `scripts/validate_gromacs_inputs.py` passes
- `gmx grompp` does not emit unresolved topology errors
- total charge is expected before neutralization
- final topology molecule counts match coordinates
- minimization converges without severe force warnings
- NVT temperature stabilizes
- NPT density and box volume behave reasonably
- production has no repeated LINCS warnings
- visual inspection shows no chemically impossible structures

## Common Failure Modes

Duplicate atom types:

- Cause: multiple LigParGen `.itp` files define the same atom type.
- Response: consolidate or remove duplicate definitions after confirming they are identical.

Molecule name mismatch:

- Cause: `[ molecules ]` uses a name that does not match `[ moleculetype ]`.
- Response: update `inputs/molecules.csv` and `topology/system.top`.

Coordinate/topology count mismatch:

- Cause: build script inserted a different number of molecules than the topology declares.
- Response: rebuild from `inputs/molecules.csv`, then rerun validation.

Bad packing:

- Cause: initial molecules overlap or are too densely packed.
- Response: increase box size, reduce molecule count, or use Packmol with a higher tolerance.

Unstable early MD:

- Cause: bad initial geometry, bad topology, too-large timestep, or unconverged minimization.
- Response: inspect minimization, lower timestep, increase equilibration, and visualize the structure.
