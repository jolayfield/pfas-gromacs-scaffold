# PFAS GROMACS Template

Generic scaffold for building GROMACS simulations of PFAS and other organic molecules in water from LigParGen `.gro` and `.itp` files.

Start here:

1. Put LigParGen files in `inputs/ligpargen/`.
2. Edit `inputs/molecules.csv`.
3. Read `docs/gromacs-ligpargen-template-plan.md`.
4. For the recommended mixed-solute path, read `docs/packmol-solute-workflow.md`.
5. If you will run PFOA, PFOS, mixtures, or replicates separately, read `docs/multiple-simulations-management-plan.md`.
6. Run `scripts/validate_gromacs_inputs.py`.
7. Build coordinates with either:

```bash
scripts/01_build_with_packmol.sh
```

or (alternative, GROMACS-only path):

```bash
scripts/01_alt_build_with_insert_molecules.sh
```

Then solvate, ionize, minimize, equilibrate, and run short production:

```bash
scripts/02_solvate_and_ionize.sh
scripts/03_run_md_pipeline.sh
```

Common knobs:

```bash
BOX_X=8 BOX_Y=8 BOX_Z=8 scripts/01_build_with_packmol.sh
ION_CONC=0.10 scripts/02_solvate_and_ionize.sh
GMX=gmx scripts/03_run_md_pipeline.sh
```

All supported variables are documented in `.env.template`. Copy it to `.env`, uncomment any overrides, and `source .env` before running — or export variables directly on the command line as shown above.

The example `inputs/molecules.csv` intentionally points to placeholder files. Replace those rows before running a real system.

For PFAS plus mixed organic solutes, the recommended default is Packmol for solute placement, then GROMACS for water and ions.

## Running multiple simulations

Use `sim_init.sh` to create an isolated directory for each system, then pass `SIM_DIR` to scope all scripts to that directory:

```bash
scripts/sim_init.sh pfoa-water-001
# Edit simulations/pfoa-water-001/inputs/molecules.csv and add LigParGen files.
SIM_DIR=simulations/pfoa-water-001 scripts/01_build_with_packmol.sh
SIM_DIR=simulations/pfoa-water-001 scripts/02_solvate_and_ionize.sh
SIM_DIR=simulations/pfoa-water-001 scripts/03_run_md_pipeline.sh
```

Each simulation directory is self-contained: its `inputs/`, `topology/`, `build/`, and `runs/` subdirectories are independent from every other simulation. See `docs/multiple-simulations-management-plan.md` for naming conventions and layout details.

## Running on an HPC cluster

Set `USE_QGMX=1` to submit MD stages through the `qgmx` cluster wrapper instead of calling `gmx grompp` + `gmx mdrun` directly. `NPROCS` controls the `-nt` argument passed to `qgmx`.

```bash
USE_QGMX=1 NPROCS=8 SIM_DIR=simulations/pfoa-water-001 scripts/03_run_md_pipeline.sh
```

With `USE_QGMX=0` (the default), all stages run locally via standard GROMACS commands.
