# Orchestration — converters as nf-meta DAG steps

Where this project's pipeline chain gets *run*, as opposed to [PLAN.md](../PLAN.md) (what
the chain *is*) or [RUNS.md](../RUNS.md) (what has *already* been run, with Seqera Platform
provenance). This directory and [`modules/local/`](../modules/local/) are additive: nothing
here changes how runs already recorded in RUNS.md were executed, and Seqera Platform stays
exactly as useful as it already is for provenance — it's just no longer the only way to run
a chain end to end.

## Why

Every edge validated so far (RUNS.md 01–08) was run as an individual Seqera Platform launch,
bridged by hand: run pipeline A, wait, run a `scripts/converters/` script by hand, launch
pipeline B as a separate run. That's the right way to *validate* a new edge — each step
needs to be inspected — but it doesn't scale to re-running a whole proven chain, and it
gives no single artifact describing the chain's shape.

[nf-meta](https://github.com/bmds-tue/nf-meta) represents a chain of pipeline runs as one
`.yaml` file (`workflows:`, each with a `from:` declaring what must finish first) and
executes it in DAG order. Its default runner just wraps local `nextflow run`/`nextflow
module run` commands, which means:

- Seqera Platform becomes optional, not structural. Point a workflow's `config_file:` at a
  `.config` with `tower { enabled = true }` and that step still gets a Platform run-watch
  link; leave it out and the step just runs.
- Converters can become first-class DAG nodes instead of the manual gap between two
  launches — **if** they're wrapped as Nextflow modules, since nf-meta's YAML only knows two
  step shapes: `nf-pipeline` (`nextflow run`) and `nf-module` (`nextflow module run`), not
  "run this script."

## What's here

`modules/local/<name>/main.nf` wraps each `scripts/converters/*.py` script as a DSL2
Nextflow process + a standalone `workflow {}` entry, calling the script via its own existing
CLI — **no conversion logic is reimplemented**; `${moduleDir}/../../../scripts/converters/`
always points back at the one script that is actually selftested. A `nextflow.config` next
to each sits alongside it only to set default param values (see "warts" below).

All four are runnable, resumable, Nextflow-cached DAG steps **today**, standalone:

```bash
nextflow run modules/local/fetchngs_to_samplesheet -params-file p.yaml
# -resume works exactly like it does for any other Nextflow run
```

Verified against this repo's own data shapes (tiny fixtures mirroring RUNS.md run 01/04/05/02
inputs, no mocking — real script execution, real file I/O):

| Module | Wraps | Verified |
|---|---|---|
| `fetchngs_to_samplesheet` | `fetchngs_to_reads_samplesheet.py` | fetchngs sheet → `reads` target |
| `detaxizer_to_samplesheet` | `detaxizer_to_reads_samplesheet.py` | seqkit-style filtered FASTQ pair |
| `mag_to_proteinfamilies` | `mag_to_proteinfamilies.py` | 2-sample pool, including the path-rewrite below |
| `metatdenovo_to_proteinfamilies` | `metatdenovo_to_proteinfamilies.py` | prodigal-style protein FASTA |

[`lmo-chain.metapipeline.yaml`](lmo-chain.metapipeline.yaml) is the full chain written as one
nf-meta config: fetchngs → {glue → mag → glue → proteinfamilies} / {glue → metatdenovo →
glue → proteinfamilies → proteinannotator, the one edge with **no** glue step at all — see
RUNS.md run 07}. **It passes `nf-meta validate`** (see "confirmed" below) but has not been
run end to end — see "not done yet."

## A wart worth knowing about: paths a converter creates vs. paths it only points at

Three of the four converters only ever *point at* files a pipeline already published
(fastq/fasta paths that are stable regardless of which Nextflow task directory ran the
conversion). `mag_to_proteinfamilies` is different: it *creates* the pooled FASTA. Left
alone, the script would embed that new file's path as wherever it happened to be written —
inside this task's Nextflow work directory, which Nextflow can prune later. The module
works around this with one `sed` line that rewrites the embedded path to where `publishDir`
actually puts the file, *before* Nextflow considers the task done. If you add a converter
that creates a new file nf-meta should chain on, check whether it needs the same rewrite —
the tell is whether the script's own `--selftest` resolves a path under a `tempfile`
directory it created, the way `mag_to_proteinfamilies.py`'s does.

## Confirmed by actually running `nf-meta validate` against this repo

Not assumed — `nf-meta validate orchestration/lmo-chain.metapipeline.yaml` was run against
the real, installed `nf-meta` 0.5.0 while writing this:

- An `nf-module` step's `name:` is addressed exactly like an `nf-pipeline`'s:
  `<org>/<repo>/<path-to-the-module-directory>`, e.g.
  `vagkaratzas/meta-omics-sig/modules/local/fetchngs_to_samplesheet`. `version:` must be a
  pinned tag or commit SHA — a branch name is rejected, same as for a pipeline step.
- `nf-meta validate` fetches that module's `meta.yml` from GitHub at the pinned ref for
  tier-2 param validation (hence a `meta.yml` next to every `main.nf` here) — it logs a
  warning and skips that one check if the fetch 404s, which is what happens with this file's
  placeholder `version: "0000000"` (no such commit exists yet). It does **not** fail the
  whole validation.
- **nf-module steps get no `-profile`/executor wiring from nf-meta.** `nf-pipeline` steps do
  (`globals.profile`, per-workflow `profile:`); `nf-module` steps only get whatever
  `container_engine:` or `config_file:` you set on that step directly (see
  `src/nf_meta/runner/workflow_run.py` — `NfModuleRun.get_cmd` never emits `-profile`). nf-meta
  prints exactly this warning when a module step has neither. **Every `nf-module` step in a
  real (non-`--stub`) run on this cluster needs its own `container_engine: singularity` or
  `config_file:`**, or it runs bare on whatever's on `$PATH`.

## Not done yet / don't oversell this

- **The chain has not been run end to end**, with or without `--stub`. The four modules are
  verified individually against fixtures; `lmo-chain.metapipeline.yaml` is verified to parse
  and validate, not to execute. Running `nf-meta run orchestration/lmo-chain.metapipeline.yaml
  --stub` first (no containers, no real compute, just structure + param wiring) is the
  natural next step, same as the nf-meta quickstart recommends for any new config.
- `version: "0000000"` on every glue step is a literal placeholder. It must become this
  branch's actual merge commit SHA (or a release tag, if these modules ever get tagged)
  before any real run — nf-meta's own version-pinning rule, applied to itself.
- This does not replace a Seqera Platform launch for validating a *new* edge — do that by
  hand first, exactly as runs 01–08 did, so a human inspects what the edge actually produces.
  Wrap it as a module and add it here once it's proven, the way `PLAN.md`'s validation table
  already distinguishes NATIVE/CONVERSION REQUIRED from UNVALIDATED.
- "Open to everybody" compute (a public AWS/GCP sandbox, so others can re-run this without
  cluster access) is a separate, unresolved question — de.NBI Cloud, nf-core's own
  AWS-sponsored compute, and Seqera's Community Showcase are the leads worth chasing, not
  something this orchestration layer itself provides.
