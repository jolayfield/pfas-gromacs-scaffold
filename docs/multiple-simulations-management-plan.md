# Managing Multiple GROMACS Simulations

Created: 2026-06-23

## Short Answer

The current scaffold is a reusable template, but its default scripts are one-active-system-at-a-time. If you run PFOA and then PFOS in the same top-level `build/`, `runs/`, and `topology/system.top` locations, the second setup can overwrite files from the first.

For multiple simulations, keep shared templates at the project root and create one self-contained directory per simulation under `simulations/`.

## Recommended Layout

```text
PFAS Sims/
  docs/
  mdp/
  scripts/
  templates/

  simulations/
    pfoa-water-001/
      README.md
      inputs/
        molecules.csv
        ligpargen/
          pfoa.gro
          pfoa.itp
      topology/
        system.top
      build/
        packmol.inp
        system_unsolvated.gro
        system_solvated.gro
        system_ions.gro
      runs/
        em/
        nvt/
        npt/
        production/
      analysis/
      logs/

    pfos-water-001/
      README.md
      inputs/
        molecules.csv
        ligpargen/
          pfos.gro
          pfos.itp
      topology/
        system.top
      build/
      runs/
      analysis/
      logs/

    pfoa-pfos-mixture-001/
      README.md
      inputs/
        molecules.csv
        ligpargen/
          pfoa.gro
          pfoa.itp
          pfos.gro
          pfos.itp
      topology/
        system.top
      build/
      runs/
      analysis/
      logs/
```

## What Goes Where

Use the root-level files for reusable methods:

- `docs/`: workflow documentation
- `mdp/`: starter parameter files shared across simulations
- `scripts/`: reusable helper scripts
- `packmol/`: reusable Packmol templates

Use each `simulations/<simulation-id>/` directory for one concrete system:

- `inputs/`: the exact LigParGen files and molecule inventory used for this simulation
- `topology/`: the generated or manually edited `system.top`
- `build/`: generated coordinate files before MD
- `runs/`: minimization, equilibration, and production outputs
- `analysis/`: post-processing outputs
- `logs/`: setup notes, command logs, warnings, and decisions

## Naming Simulations

Use names that encode chemistry, environment, and replicate/variant:

```text
pfoa-water-001
pfos-water-001
pfoa-water-150mm-nacl-001
pfoa-pfos-mixture-001
pfoa-water-largebox-001
pfos-water-replicate-002
```

Avoid names like:

```text
test1
new-run
final
final2
```

Simulation names should be stable enough to cite in notes and analysis.

## Recommended Per-Simulation README

Each simulation directory should have a small `README.md` with:

```text
# pfoa-water-001

Purpose:
- Single-solute PFOA in TIP3P water using OPLS-AA/LigParGen topology.

Composition:
- PFOA: 40
- Water: added by gmx solvate
- Na/Cl: added by gmx genion, 0.15 M, neutralized

Build path:
- Packmol for solute placement
- GROMACS for water and ions

Box:
- 8 x 8 x 8 nm

Inputs:
- inputs/ligpargen/pfoa.gro
- inputs/ligpargen/pfoa.itp

Notes:
- Record warnings, topology edits, duplicate atomtype handling, and grompp decisions here.
```

## PFOA Versus PFOS Example

For PFOA only:

```text
simulations/pfoa-water-001/inputs/molecules.csv
simulations/pfoa-water-001/topology/system.top
simulations/pfoa-water-001/build/system_ions.gro
simulations/pfoa-water-001/runs/production/production.xtc
```

For PFOS only:

```text
simulations/pfos-water-001/inputs/molecules.csv
simulations/pfos-water-001/topology/system.top
simulations/pfos-water-001/build/system_ions.gro
simulations/pfos-water-001/runs/production/production.xtc
```

For a PFOA/PFOS mixture:

```text
simulations/pfoa-pfos-mixture-001/inputs/molecules.csv
simulations/pfoa-pfos-mixture-001/topology/system.top
simulations/pfoa-pfos-mixture-001/build/system_ions.gro
simulations/pfoa-pfos-mixture-001/runs/production/production.xtc
```

## Operational Plan

1. Create a new simulation directory under `simulations/`.
2. Copy or place the relevant LigParGen `.gro` and `.itp` files into that simulation's `inputs/ligpargen/`.
3. Create that simulation's `inputs/molecules.csv`.
4. Generate that simulation's `topology/system.top`.
5. Build solute coordinates with Packmol into that simulation's `build/`.
6. Add water and ions into that simulation's `build/`.
7. Run minimization, NVT, NPT, and production into that simulation's `runs/`.
8. Put post-processing outputs into that simulation's `analysis/`.
9. Record all topology edits, warnings, and decisions in that simulation's `README.md` or `logs/`.

## Why This Is Better Than One Shared `runs/` Folder

Keeping each simulation self-contained prevents:

- overwriting PFOA outputs with PFOS outputs
- mixing topology files between systems
- losing which `.itp` version created a trajectory
- confusing replicate runs with parameter variants
- analyzing a trajectory against the wrong topology

It also makes simulations easier to archive, compare, rerun, and share.

## Near-Term Script Improvement

The current scripts can be adapted to this layout by adding a `SIM_DIR` variable:

```bash
SIM_DIR=simulations/pfoa-water-001 scripts/01_build_with_packmol.sh
SIM_DIR=simulations/pfoa-water-001 scripts/02_solvate_and_ionize.sh
SIM_DIR=simulations/pfoa-water-001 scripts/03_run_md_pipeline.sh
```

With that change, the scripts should read:

```text
$SIM_DIR/inputs/molecules.csv
$SIM_DIR/topology/system.top
```

and write:

```text
$SIM_DIR/build/
$SIM_DIR/runs/
```

Until the scripts are updated for `SIM_DIR`, treat the root-level scaffold as a template or scratch system and manually move/copy it into a per-simulation folder before running a second system.

