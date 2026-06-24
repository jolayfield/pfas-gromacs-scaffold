---
title: "feat: Improve GROMACS scaffold for reproducibility and ease of use"
date: 2026-06-24
status: active
---

# feat: Improve GROMACS Scaffold for Reproducibility and Ease of Use

## Summary

The current scaffold is a working single-simulation template with good bones: numbered scripts, shared `common.sh`, a pre-flight validator, and two build paths. Five areas need strengthening before the scaffold is reliably reproducible across multiple simulations and research collaborators:

1. **Multi-simulation isolation** — scripts write to shared `build/` and `runs/`, so a second system overwrites the first. Implementing `SIM_DIR` support (already documented in `docs/multiple-simulations-management-plan.md`) fixes this.
2. **Repository hygiene** — binary GROMACS outputs have no `.gitignore`; the `packmol/packmol.inp.template` is orphaned; the two `01_` scripts share a prefix that makes tab-completion ambiguous.
3. **Environment and provenance** — there is no central place to set run parameters, and no record of which software versions produced a given run.
4. **HPC runner integration** — the `qgmx` cluster wrapper is not wired into the pipeline. `03_run_md_pipeline.sh` calls `gmx mdrun` directly, which bypasses the job scheduler.
5. **MDP physics gaps** — `DispCorr` is absent from NPT and production runs (important for OPLS-AA energy accuracy with periodic boundary conditions).

---

## Problem Frame

The scaffold is used for PFAS and organic-molecule simulations in TIP3P water, built from LigParGen-generated `.gro`/`.itp` files and run on a university HPC cluster via a `qgmx` wrapper. A researcher moving from one molecule to a second system risks overwriting their first run's outputs. There is also no way to reconstruct the exact software environment used to produce a trajectory, which is required for scientific reproducibility. The MDP files are conservative but contain physics-level omissions that affect result quality for NPT and production runs.

---

## Requirements

- R1: A second simulation can be built and run without disturbing outputs from the first.
- R2: All environment variables needed to configure a run are documented in a single template file.
- R3: Each completed build records the GROMACS version, date, and key parameters used.
- R4: Binary GROMACS outputs are excluded from version control.
- R5: The pipeline script can call `qgmx` for HPC submission instead of `gmx mdrun` directly.
- R6: NPT and production MDP files include `DispCorr = EnerPres`.
- R8: Repository files and naming are internally consistent (no duplicate prefixes, no orphaned templates).

---

## Key Technical Decisions

**SIM_DIR defaults to root for backward compatibility.** Setting `SIM_DIR` to the repository root when unset means all existing scripts continue to work unchanged. When `SIM_DIR` is set to `simulations/pfoa-water-001`, the scripts resolve all paths relative to it. This avoids a hard break for existing single-simulation use.

**`qgmx` wraps grompp + mdrun in a single call.** The wrapper interface (`-f` mdp, `-c` coordinates, `-oc` output GRO, `-p` topology, `-nt` processors) replaces the current two-step `grompp` + `mdrun` pattern. The `run_stage` function in `03_run_md_pipeline.sh` should be refactored to branch on a `USE_QGMX` flag rather than producing a parallel implementation. One open question flagged below: `qgmx` flags for position-restraint reference coordinates (`-r`) must be confirmed before the NVT and NPT stages can use it correctly.

**Provenance goes to a `sim.log` in each simulation directory.** This is a plain-text append-only file written by `common.sh` at the start of each script invocation. It captures timestamp, script name, key variables, GROMACS version, and Python version. It does not replace GROMACS's own `.log` files; it captures the setup-level context those files omit.

**The orphaned `packmol/packmol.inp.template` is removed.** The script `01_build_with_packmol.sh` generates the Packmol input programmatically from `molecules.csv` and never reads this file. Keeping it implies it is used or intentional, which misleads users.

---

## Scope Boundaries

### In Scope
- Implementing `SIM_DIR` in `common.sh` and all three numbered scripts
- Adding `sim_init.sh` to scaffold a new simulation directory
- Adding `.gitignore`
- Adding `.env.template`
- Adding provenance capture to `common.sh`
- Adding `USE_QGMX` and `NPROCS` support to `03_run_md_pipeline.sh`
- Updating `mdp/npt.mdp` and `mdp/md.mdp` with `DispCorr`
- Renaming `01_build_with_insert_molecules.sh` to remove prefix ambiguity
- Removing `packmol/packmol.inp.template`
- Updating `README.md` and relevant docs for all of the above

### Deferred to Follow-Up Work
- Analysis scripts for energy, density, and RDF (no trajectory data exists yet to validate against)
- PLUMED integration (flags exist in `qgmx` but not yet needed)
- Position restraints during equilibration (requires index file generation, which adds complexity beyond this plan's scope)
- Automated replicate-run management (fixed seeds, batch launch)
- Container or conda environment specification (requires knowing the exact software versions in use)

---

## Open Questions

**OQ1 (blocking for U4):** Does `qgmx` accept a `-r` flag for position-restraint reference coordinates? The current NVT and NPT `run_stage` calls pass `-r` to `gmx grompp`. If `qgmx` does not expose this, NVT and NPT must still use the grompp+mdrun path and only EM and production can use `qgmx`. Verify with `qgmx --help` or the wrapper's documentation before implementing U4.

**OQ2 (deferred):** Does `qgmx` wait for the job to finish before returning, or does it fire-and-forget? The current pipeline is sequential (each stage feeds the next stage's GRO). If `qgmx` is asynchronous, `03_run_md_pipeline.sh` will need job-ID tracking or a polling loop. This may push to a follow-up once the basic integration is confirmed working.

---

## High-Level Technical Design

### SIM_DIR Path Resolution

```
SIM_DIR (env var, default = ROOT_DIR)
  ├── inputs/
  │     molecules.csv
  │     ligpargen/
  ├── topology/
  │     system.top
  ├── build/
  │     system_unsolvated.gro
  │     system_solvated.gro
  │     system_ions.gro
  ├── runs/
  │     em/
  │     nvt/
  │     npt/
  │     production/
  └── sim.log          ← new: provenance capture

ROOT_DIR (always the project root)
  ├── scripts/         ← shared, never per-simulation
  ├── mdp/             ← shared, never per-simulation
  └── simulations/     ← one subdirectory per system
```

Scripts resolve `BUILD_DIR`, `RUNS_DIR`, `TOPOLOGY`, and `MOLECULES_CSV` relative to `SIM_DIR`. The `mdp/` and `scripts/` directories remain at `ROOT_DIR` and are shared across all simulations.

### qgmx Pipeline Branching

```
USE_QGMX=0 (default)                USE_QGMX=1
┌─────────────────────┐             ┌──────────────────────────────────┐
│ gmx grompp          │             │ qgmx -f <mdp>                    │
│   -f <mdp>          │             │      -c <input.gro>              │
│   -c <input.gro>    │             │      -oc <output.gro>            │
│   -p <top>          │             │      -p <top>                    │
│   [-r <ref.gro>]    │             │      -nt <NPROCS>                │
│   -o <stage.tpr>    │             │ [see OQ1: -r support unknown]    │
│ gmx mdrun           │             └──────────────────────────────────┘
│   -deffnm <stage>   │
└─────────────────────┘
```

Both paths share the same stage sequence (em → nvt → npt → production) and produce a `<stage>.gro` output that feeds the next stage as input.

---

## Implementation Units

### U1. Repository Hygiene

**Goal:** Remove confusing and misleading files; make binary outputs invisible to git; clarify script naming.

**Requirements:** R4, R8

**Dependencies:** none

**Files:**
- `.gitignore` (create)
- `packmol/packmol.inp.template` (delete)
- `scripts/01_build_with_insert_molecules.sh` → `scripts/01_alt_build_with_insert_molecules.sh` (rename)
- `README.md` (update references to renamed script)
- `docs/gromacs-ligpargen-template-plan.md` (update references)

**Approach:**
`.gitignore` should exclude: `*.tpr`, `*.trr`, `*.xtc`, `*.edr`, `*.cpt`, `*.log` (GROMACS run logs), `build/*.gro`, `build/*.pdb`, `runs/` directory contents (but keep `.gitkeep`), and `.DS_Store`. LigParGen input files in `inputs/ligpargen/` should remain tracked — they are source inputs, not outputs. Add a `simulations/` entry that ignores simulation outputs while keeping the directory tracked.

Rename the insert-molecules script with an `_alt_` infix to signal it is a non-default alternative. Update all documentation references accordingly.

Delete `packmol/packmol.inp.template`. The file is never read by any script; the manual Packmol pattern it illustrates already appears in `docs/packmol-solute-workflow.md`.

**Test scenarios:**
- Adding a dummy `.xtc` file to `build/` then running `git status` shows it as untracked (not staged)
- Adding a `.itp` file to `inputs/ligpargen/` then running `git status` shows it as untracked (not excluded — intended to be committed)
- `scripts/01_alt_build_with_insert_molecules.sh` runs and produces the same output as the old `01_build_with_insert_molecules.sh`
- `README.md` and all docs reference the new `01_alt_` name with no broken cross-references

**Verification:** `git status` after a full build run shows no unexpected tracked files; all three numbered scripts exist under their new names and run without errors.

---

### U2. SIM_DIR Multi-Simulation Support

**Goal:** All three numbered scripts and `common.sh` resolve their working paths from a `SIM_DIR` variable, enabling fully isolated per-simulation directories.

**Requirements:** R1

**Dependencies:** U1 (script naming must be stable before adding `SIM_DIR` logic)

**Files:**
- `scripts/common.sh` (modify)
- `scripts/01_build_with_packmol.sh` (modify)
- `scripts/01_alt_build_with_insert_molecules.sh` (modify)
- `scripts/02_solvate_and_ionize.sh` (modify)
- `scripts/03_run_md_pipeline.sh` (modify)
- `scripts/sim_init.sh` (create)
- `README.md` (update with `SIM_DIR` usage)
- `docs/multiple-simulations-management-plan.md` (update to reflect implementation complete)

**Approach:**
In `common.sh`, add: `SIM_DIR="${SIM_DIR:-$ROOT_DIR}"`. Then resolve all data paths relative to `SIM_DIR`:

```bash
MOLECULES_CSV="${MOLECULES_CSV:-$SIM_DIR/inputs/molecules.csv}"
TOPOLOGY="$SIM_DIR/topology/system.top"
BUILD_DIR="$SIM_DIR/build"
RUNS_DIR="$SIM_DIR/runs"
```

`ROOT_DIR` keeps pointing at the project root (scripts and MDP files live there). `SIM_DIR` governs where data lives. When unset, `SIM_DIR` defaults to `ROOT_DIR`, preserving all current behavior.

`ensure_dirs` should create `$SIM_DIR/build`, `$SIM_DIR/runs/{em,nvt,npt,production}`, and `$SIM_DIR/logs`.

`sim_init.sh <sim-id>` creates a new directory at `simulations/<sim-id>/` containing: `inputs/ligpargen/` (with its README), an example `inputs/molecules.csv`, a copy of `topology/system.top` template, empty `build/`, `runs/`, `logs/`, and a `README.md` stub pre-filled with the sim ID and creation date. If the target directory already exists, the script prints an error and exits rather than overwriting.

Document the standard usage in `README.md`:

```bash
scripts/sim_init.sh pfoa-water-001
# edit simulations/pfoa-water-001/inputs/molecules.csv
SIM_DIR=simulations/pfoa-water-001 scripts/01_build_with_packmol.sh
SIM_DIR=simulations/pfoa-water-001 scripts/02_solvate_and_ionize.sh
SIM_DIR=simulations/pfoa-water-001 scripts/03_run_md_pipeline.sh
```

**Patterns to follow:** `ROOT_DIR` derivation in `common.sh`; `BOX_X="${BOX_X:-6}"` pattern for optional env-var overrides.

**Test scenarios:**
- Running scripts with no `SIM_DIR` set writes to root-level `build/` and `runs/` (backward-compatible, unchanged behavior)
- Running with `SIM_DIR=simulations/pfoa-water-001` writes all files under that directory and never touches root-level `build/` or `runs/`
- Running two simulations sequentially (`SIM_DIR=simulations/pfoa-water-001` then `SIM_DIR=simulations/pfos-water-001`) leaves both directories complete and independent — neither overwrites the other
- `sim_init.sh pfoa-water-001` creates the expected directory structure including README stub
- `sim_init.sh` called with an existing directory name prints a clear error and exits without overwriting

**Verification:** Both `simulations/pfoa-water-001/build/system_ions.gro` and `simulations/pfos-water-001/build/system_ions.gro` exist after running both systems; file modification timestamps confirm neither was touched by the other's run.

---

### U3. Environment Template and Provenance Capture

**Goal:** Collect all tunable environment variables in one template file; write a provenance record to each simulation directory at the start of each script run.

**Requirements:** R2, R3

**Dependencies:** U2 (SIM_DIR must exist so provenance is written to the correct simulation directory)

**Files:**
- `.env.template` (create)
- `scripts/common.sh` (modify — add `write_provenance` function)
- `README.md` (add `.env` usage note)

**Approach:**
`.env.template` documents every environment variable the scripts accept, with its default value and a one-line description. Users copy it to `.env` and `source .env` before running. Do not auto-source `.env` from `common.sh` — explicit sourcing keeps behavior transparent and avoids surprising behavior when the file is stale or wrong.

`write_provenance` appended to `common.sh` writes to `$SIM_DIR/sim.log` (creating it if absent). Each entry should record:
- ISO timestamp
- invoking script name (`$0`)
- key variables: `SIM_DIR`, `GMX`, `BOX_X/Y/Z`, `ION_CONC`, `USE_QGMX`, `NPROCS`
- GROMACS version (`"$GMX" --version 2>&1 | head -5`; write "version unknown" if this fails rather than aborting)
- Python version (`python3 --version 2>&1`)

Call `write_provenance` near the top of each numbered script after `source common.sh` but before the first GROMACS command. `sim.log` is plain text, append-only, and intentionally tracked in git for simulation directories so the record travels with the data.

**Test scenarios:**
- After running `01_build_with_packmol.sh`, `$SIM_DIR/sim.log` exists and contains a timestamped entry with the script name and variable snapshot
- Running all three scripts sequentially produces three separate entries in the same `sim.log`
- `sim.log` contains a non-empty GROMACS version string
- With an invalid `GMX` path, `write_provenance` writes "version unknown" and the script continues normally (does not abort on the version check)
- `.env.template` covers all variables used in `common.sh`, `01_build_with_packmol.sh`, `01_alt_build_with_insert_molecules.sh`, `02_solvate_and_ionize.sh`, and `03_run_md_pipeline.sh`

**Verification:** `sim.log` in a completed simulation directory contains one timestamped entry per script run, each with a GROMACS version string; `.env.template` lists every env var that `grep -rh 'env:-\|:-' scripts/` finds.

---

### U4. qgmx HPC Runner Integration

**Goal:** `03_run_md_pipeline.sh` can call `qgmx` instead of `gmx grompp` + `gmx mdrun` when `USE_QGMX=1`, with `NPROCS` controlling thread count.

**Requirements:** R5

**Dependencies:** U2 (SIM_DIR paths must be correct before wiring up the runner); U3 (NPROCS and USE_QGMX should appear in `.env.template`)

**Files:**
- `scripts/03_run_md_pipeline.sh` (modify)
- `scripts/common.sh` (modify — add `NPROCS` and `USE_QGMX` defaults)
- `.env.template` (update — add `USE_QGMX` and `NPROCS` entries)
- `README.md` (add HPC usage example)
- `docs/gromacs-ligpargen-template-plan.md` (add HPC runner section)

**Approach:**
Add to `common.sh`: `USE_QGMX="${USE_QGMX:-0}"` and `NPROCS="${NPROCS:-1}"`.

Refactor the `run_stage` function in `03_run_md_pipeline.sh` to branch on `USE_QGMX`:

- `USE_QGMX=0` (default): unchanged — `gmx grompp` then `gmx mdrun -deffnm`.
- `USE_QGMX=1`: call `qgmx -f "$ROOT_DIR/mdp/$mdp" -c "$input_gro" -oc "$dir/$stage.gro" -p "$TOPOLOGY" -nt "$NPROCS"`.

**Position restraints (OQ1):** The NVT and NPT `run_stage` calls pass a `-r` reference structure to `grompp`. If `qgmx` does not accept `-r`, those two stages must fall back to the grompp+mdrun path even when `USE_QGMX=1`. Add a clearly marked comment block at the relevant branch point directing the implementer to verify `qgmx --help` before finalizing. A safe default is: attempt `qgmx` for all stages; if `-r` is unsupported, use `gmx grompp`+`gmx mdrun` for NVT and NPT only.

The output GRO file from `qgmx` (`-oc "$dir/$stage.gro"`) must match the path the next stage reads as input. The existing naming convention (`$RUNS_DIR/em/em.gro`, `$RUNS_DIR/nvt/nvt.gro`, etc.) should be preserved.

Add `require_command qgmx` inside the `USE_QGMX=1` branch so the failure is caught before any work begins.

**Patterns to follow:** `GMX="${GMX:-gmx}"` override pattern in `common.sh`; the existing `run_stage` branching on `extra_ref`.

**Test scenarios:**
- With `USE_QGMX=0` (default), the pipeline runs unchanged using `gmx grompp` + `gmx mdrun`
- With `USE_QGMX=1` and `qgmx` not installed, the script exits with "Missing command: qgmx" before any stage runs
- With `USE_QGMX=1` and `qgmx` available, the energy minimization stage calls `qgmx` and produces `$RUNS_DIR/em/em.gro`
- `NPROCS=4 USE_QGMX=1` passes `-nt 4` to `qgmx`
- All four pipeline stages complete in sequence when `USE_QGMX=1`, with each stage's input GRO file produced by the prior stage

**Verification:** `USE_QGMX=1 NPROCS=4 scripts/03_run_md_pipeline.sh` on a system with `qgmx` available produces output GRO files for all four stages in the correct `runs/` subdirectories.

---

### U5. MDP Physics Improvements

**Goal:** `npt.mdp` and `md.mdp` gain `DispCorr = EnerPres`.

**Requirements:** R6

**Dependencies:** none (self-contained MDP edits; can be implemented in any order relative to other units)

**Files:**
- `mdp/npt.mdp` (modify)
- `mdp/md.mdp` (modify)
- `docs/gromacs-ligpargen-template-plan.md` (update Minimization/Equilibration/Production section)

**Approach:**

Add to `npt.mdp` and `md.mdp`:
```
DispCorr    = EnerPres
```
This applies long-range Lennard-Jones correction to both energy and pressure — the standard setting for OPLS-AA under periodic boundary conditions. It is not needed for `nvt.mdp` (no pressure coupling) or for `ions.mdp` / `minim.mdp` (energy minimization, not production thermodynamics).

Note on thermostat groups: the existing `tc-grps = System` with V-rescale is physically correct. V-rescale (Bussi, Donadio & Parrinello 2007, *J. Chem. Phys.* 126:014101) properly samples the canonical ensemble and does not exhibit the flying ice cube artifact that motivates separate coupling groups. Splitting groups would add complexity without fixing a real problem for this thermostat. Leave the thermostat configuration unchanged.

*`gen_seed` note (documentation only):* `gen_seed = -1` in `nvt.mdp` selects a random seed at runtime. For exact trajectory reproduction, the seed GROMACS chose is printed in the NVT `.log` file. Add a comment to `nvt.mdp` directing users to record that value if exact replication is needed.

**Test scenarios:**
- `gmx grompp -f mdp/npt.mdp -c build/system_ions.gro -p topology/system.top -o /tmp/check.tpr` exits with no errors or unrecognized-parameter warnings
- `gmx grompp -f mdp/md.mdp ...` exits cleanly
- Energy output from a short NPT test run includes a `Disper. corr.` term (confirmed via `gmx energy`)

**Verification:** `gmx grompp` with each updated MDP file exits cleanly on a valid solvated system; a short NPT test run shows dispersion correction terms in the energy output.

---

## System-Wide Impact

- All script changes are backward-compatible when `SIM_DIR` is unset and `USE_QGMX=0`.
- Renaming `01_build_with_insert_molecules.sh` breaks any external lab notes or scripts referencing the old name. Update all references in `docs/` and `README.md` as part of U1.
- `.gitignore` does not retroactively untrack files already committed. If binary outputs were committed before this change, remove them with `git rm --cached <file>` after adding `.gitignore`.

---

## Risks and Dependencies

| Risk | Likelihood | Mitigation |
|---|---|---|
| `qgmx` does not support `-r` position restraints | Medium | Fall back to grompp+mdrun for NVT/NPT; use `qgmx` for EM and production only; document in OQ1 |
| `qgmx` is asynchronous (fire-and-forget) | Unknown | Test with a short EM run before chaining all four stages; if async, defer full integration to a follow-up |
| `DispCorr` slightly shifts NPT density vs. prior runs | Low, intended | This is the correct physical behavior; document that pre-change and post-change runs are not directly comparable for thermodynamic quantities |

---

## Sources and Research

- `docs/multiple-simulations-management-plan.md` — the `SIM_DIR` pattern and simulation layout described in U2 implement the "near-term script improvement" already documented there
- `docs/gromacs-ligpargen-template-plan.md` — validation checklist and common failure modes informed the test scenarios
- OPLS-AA best practices: `DispCorr = EnerPres` is standard for all non-bonded cutoff OPLS-AA simulations under PBC
- Bussi, Donadio & Parrinello (2007) *J. Chem. Phys.* 126:014101 — V-rescale paper confirming canonical ensemble sampling; Bauer et al. (2018) *J. Chem. Theory Comput.* 14:5038 — confirms V-rescale does not exhibit the flying ice cube artifact
