# Packmol Workflow For Multiple LigParGen Solutes

Created: 2026-06-23

## Recommendation

Use Packmol to place the PFAS and organic solute molecules, then use GROMACS to add solvent and ions.

Recommended division of labor:

```text
LigParGen .gro/.itp files
  -> Packmol places solute molecules
  -> GROMACS converts/checks coordinates
  -> gmx solvate adds TIP3P water and updates SOL count
  -> gmx grompp validates topology
  -> gmx genion replaces water with ions and updates ion counts
  -> minimization/equilibration/production
```

Packmol is excellent at building mixed initial solute configurations. GROMACS is better for solvent and ions because it keeps the coordinate file and topology bookkeeping synchronized.

## Why Not Put Everything In Packmol?

You can pack solutes, water, and ions all at once with Packmol, but it is usually not the best default for this scaffold.

Reasons to prefer GROMACS for water and ions:

- `gmx solvate` automatically updates the `SOL` count in `topology/system.top`.
- `gmx genion` replaces solvent molecules and updates ion counts.
- `gmx grompp` checks whether topology, charges, molecule names, and coordinates agree.
- GROMACS uses the solvent and ion topology definitions already included by the selected force field.
- It reduces manual counting errors, especially after water molecules are removed during ion placement.

Use Packmol for solvent only when you have a special reason:

- nonstandard solvent mixture
- explicit cosolvents
- prebuilt solvent boxes
- confined pores or unusual geometry
- interfaces where you need precise initial placement
- systems where `gmx solvate` fills a region you intentionally want empty

If Packmol places water or ions, you must manually ensure the `[ molecules ]` counts in `topology/system.top` match the coordinate file exactly.

## Inputs

Put LigParGen files here:

```text
inputs/ligpargen/
```

Then edit:

```text
inputs/molecules.csv
```

Example:

```csv
name,resname,gro,itp,count,charge
PFOS,PFO,inputs/ligpargen/pfos.gro,inputs/ligpargen/pfos.itp,40,-1
PFOA,POA,inputs/ligpargen/pfoa.gro,inputs/ligpargen/pfoa.itp,40,-1
BENZ,BEN,inputs/ligpargen/benzene.gro,inputs/ligpargen/benzene.itp,20,0
```

The `name` column must match the molecule name in the `.itp` `[ moleculetype ]` section. The `count` column is the number of molecules Packmol will place and the number written to the topology.

## Step 1: Validate The Molecule Inventory

Run:

```bash
scripts/validate_gromacs_inputs.py
```

This checks:

- all listed `.gro` files exist
- all listed `.itp` files exist
- inventory molecule names match `.itp` `[ moleculetype ]` names
- residue names look plausible in the `.gro` files
- expected total solute charge before adding ions

## Step 2: Build The Unsolvated Solute Box With Packmol

Run:

```bash
BOX_X=8 BOX_Y=8 BOX_Z=8 scripts/01_build_with_packmol.sh
```

This script:

1. validates `inputs/molecules.csv`
2. regenerates `topology/system.top` from the inventory
3. converts each molecule `.gro` file to a temporary `.pdb`
4. writes `build/packmol.inp`
5. runs Packmol
6. converts Packmol output back to GROMACS `.gro`
7. writes `build/system_unsolvated.gro`

Key variables:

```bash
BOX_X=8
BOX_Y=8
BOX_Z=8
PACKMOL_TOLERANCE=2.0
GMX=gmx
PACKMOL=packmol
```

`BOX_X`, `BOX_Y`, and `BOX_Z` are in nm. `PACKMOL_TOLERANCE` is in angstrom because Packmol uses angstrom-style PDB coordinates.

## Step 3: Inspect Packmol Output

Before adding water, visually inspect:

```text
build/system_unsolvated.gro
```

Check for:

- obviously overlapping solutes
- molecules outside the box
- unexpected orientation or aggregation
- wrong number of each molecule type

If packing fails or looks too dense, increase the box size or increase `PACKMOL_TOLERANCE`.

## Step 4: Solvate And Add Ions With GROMACS

Run:

```bash
ION_CONC=0.15 scripts/02_solvate_and_ionize.sh
```

This script:

1. runs `gmx solvate`
2. lets GROMACS update the `SOL` count in `topology/system.top`
3. runs `gmx grompp` using `mdp/ions.mdp`
4. runs `gmx genion`
5. lets GROMACS update ion and solvent counts
6. writes `build/system_ions.gro`

The default solvent coordinate source is:

```bash
WATER_MODEL_GRO=spc216.gro
```

That filename is normal in GROMACS workflows. The actual water topology comes from the topology include:

```gromacs
#include "oplsaa.ff/tip3p.itp"
```

Confirm the exact water include exists in your local GROMACS OPLS-AA installation. Some installations name or organize water model files differently.

## Step 5: Minimize And Equilibrate

Run:

```bash
scripts/03_run_md_pipeline.sh
```

This performs:

- energy minimization
- short NVT equilibration
- short NPT equilibration
- short production validation run

Treat these `.mdp` files as starting points. For final science, tune temperature, pressure coupling, timestep, output frequency, simulation length, and restraints for the specific system.

## Manual Packmol Pattern

If you want to write a Packmol input by hand, the core pattern is:

```text
tolerance 2.0
filetype pdb
output build/system_unsolvated.pdb

structure build/PFOS.pdb
  number 40
  inside box 0. 0. 0. 80. 80. 80.
end structure

structure build/PFOA.pdb
  number 40
  inside box 0. 0. 0. 80. 80. 80.
end structure

structure build/BENZ.pdb
  number 20
  inside box 0. 0. 0. 80. 80. 80.
end structure
```

The `80. 80. 80.` values are angstrom. That corresponds to an 8 nm GROMACS box.

Convert the result back to `.gro`:

```bash
gmx editconf -f build/system_unsolvated.pdb -o build/system_unsolvated.gro -box 8 8 8
```

## Quality Checks

After Packmol:

```bash
grep -c PFOS build/system_unsolvated.gro
grep -c PFOA build/system_unsolvated.gro
grep -c BENZ build/system_unsolvated.gro
```

After solvation/ionization:

```bash
gmx grompp -f mdp/minim.mdp -c build/system_ions.gro -p topology/system.top -o build/check.tpr
```

If `grompp` fails, fix the topology mismatch before running MD. Do not use `-maxwarn` to push through unexplained charge, topology, or atom-name problems.

