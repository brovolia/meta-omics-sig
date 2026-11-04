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
  launches — wrapped as Nextflow modules and referenced as **`nf-pipeline`** steps pointed at
  this repo with `main_script:` set, **not** as nf-meta's `nf-module` type. See "a wrong turn,
  corrected" below for why: `nf-module` only resolves modules published to Seqera's own
  module registry, not an arbitrary repo.

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
RUNS.md run 07}. Each glue step is `nf-pipeline` + `main_script:`, pointed at
`https://github.com/brovolia/meta-omics-sig` (this branch's fork) — see "a wrong turn,
corrected" below for why not `nf-module`. It passes `nf-meta validate`, and two of the four
glue steps (the simplest and the trickiest) have been run for real against that fork, not
just validated — see "confirmed" below. The chain as a whole has not been run end to end.

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

## A reproduced, fixed bug: input and output can silently collide on disk

Every module declares its path-like inputs as `path`, not `val` (see the comments in each
`main.nf`) — necessary so Nextflow resolves a relative param value (what nf-meta actually
produces, e.g. `out/01_fetchngs/samplesheet/samplesheet.csv`) against the launch directory
and stages it into the task sandbox, rather than handing the literal string to the script,
which would resolve it against the task's own work dir instead and fail with
`FileNotFoundError`. That part is necessary and correct.

The trap it opens: `fetchngs_to_samplesheet`'s output is named `samplesheet.csv`, and its
input — a real nf-core/fetchngs samplesheet — is *conventionally also* named
`samplesheet.csv` on disk. Left to Nextflow's default staging, the input is symlinked into
the task dir under that same original basename, so input and output collide on the exact
same filename. The script reads the input (fully, into memory) and only then opens the
output path to write — same sequence, but now the "output path" and the "staged input
symlink" are literally the same path. Writing through that symlink in `'w'` mode follows it
back to the **original fetchngs output file on disk** and truncates it.

Reproduced, not theorized: ran the module against a real relative-path setup (the same shape
nf-meta produces), the source file's md5 changed after the run, and its content became the
*converted* sheet instead of the original. Fixed with Nextflow's `stageAs:` on every
module's path input, pinning the staged name explicitly (`input_samplesheet.csv`,
`input_mag_outdir`, etc.) so it can never collide with whatever the process declares as its
own output, regardless of what the real upstream pipeline happens to name its output.
Re-ran the same reproduction after the fix: source md5 unchanged, converted output landed in
its own separate file. If you add a converter module, give its `path` input a `stageAs:`
too — don't rely on the input and output filenames happening not to collide.

## A wrong turn, corrected: `nf-module` doesn't do what it sounds like

The first version of this file used nf-meta's `type: nf-module` for the glue steps,
addressed as `<org>/<repo>/<path-to-module-dir>` — e.g.
`vagkaratzas/meta-omics-sig/modules/local/fetchngs_to_samplesheet`. That was wrong, caught
only by actually testing it against a real pushed commit rather than trusting
`nf-meta validate`'s "✓ Config is valid":

- `nf-meta validate` only ever reported a 404 fetching each module's `meta.yml`, both before
  and after the real push. Reading `get_module_schema()` in the installed `nf-meta` 0.5.0
  shows why: it is **hardcoded** to `https://raw.githubusercontent.com/nf-core/modules/<ref>/
  modules/<name>/meta.yml` — it always looks inside the canonical `nf-core/modules` registry
  repo, using `name` as a subpath under `modules/`, regardless of what `name` actually is.
  For a non-nf-core name this 404s by construction; the 404 said nothing about whether our
  own repo/path was reachable, which is why it looked identical before and after pushing.
- The real mechanism `type: nf-module` drives, `nextflow module run <name>@<version>`,
  describes itself as "**Run a module directly from the registry**" in its own `--help` —
  Seqera's `registry.nextflow.io`, a module *publishing* system (`nextflow module publish`),
  unrelated to pulling an arbitrary git repo. Tried directly against the real pushed commit:

  ```
  $ nextflow module run brovolia/meta-omics-sig/modules/local/fetchngs_to_samplesheet@<sha> ...
  Invalid module reference: brovolia/meta-omics-sig/modules/local/fetchngs_to_samplesheet@<sha>
  ```

  Nextflow rejects the reference outright. There is no way, in nf-meta 0.5.0, to address an
  unpublished module in an arbitrary repo via `type: nf-module`.

**The fix:** every glue step here is a plain `nf-pipeline` entry (the default `type`) with
`url: https://github.com/brovolia/meta-omics-sig` and `main_script:` pointed at the module's
`main.nf` — the same `nextflow run <url> -r <ref> -main-script <path>` mechanism every
nf-core pipeline step in this file already uses, just pointed at a non-default entry script
in a non-nf-core repo. `NfPipeline.main_script` exists in nf-meta's model precisely for this
("Alternate entry script within the pipeline repo") and this path is confirmed working, not
just structurally valid — see below. Bonus: `nf-pipeline` steps *do* get `-profile` wired
from `globals.profile`, so this also fixes the "`nf-module` gets no executor wiring" gap the
first version of this file warned about — that warning no longer applies to anything here.

## Confirmed by actually running real commands against the real pushed fork

Not nf-meta's own validation (see above for why that wasn't enough) — these commands were
run directly:

```bash
nextflow run https://github.com/brovolia/meta-omics-sig \
  -r <sha> -main-script modules/local/fetchngs_to_samplesheet/main.nf \
  -params-file p.yaml
```

- `nextflow run <this fork> -r <sha> -main-script modules/local/<name>/main.nf` pulls the
  real repo over git and executes the module — tried for `fetchngs_to_samplesheet` (simplest)
  and `mag_to_proteinfamilies` (the one with the path-rewrite, see below): both `SUCCESS`,
  both produced byte-identical output to running the module from a local checkout.
- `nf-meta validate orchestration/lmo-chain.metapipeline.yaml` now reports "✓ Config is
  valid" with a different, *honest* warning per glue step: `nextflow_schema.json not found
  for https://github.com/brovolia/meta-omics-sig@<sha>`. That's correct and expected — this
  repo has no root-level `nextflow_schema.json` (it isn't a full nf-core pipeline) — so
  nf-meta's tier-2 param-schema check has nothing to check against. It is not a resolution
  failure the way the `nf-module` 404 was.

## Not done yet / don't oversell this

- **The full chain has not been run end to end.** Two of the four glue steps are confirmed
  against the real pushed fork (above); all four are confirmed against fixtures
  (`modules/local/*` table above); `lmo-chain.metapipeline.yaml` is confirmed to parse,
  validate, and (for the two tested glue steps) pull-and-execute — not to run start to
  finish. Running `nf-meta run orchestration/lmo-chain.metapipeline.yaml --stub` next (no
  containers, no real compute, just structure + param wiring through every node, including
  the five real nf-core pipeline steps) is the natural next step.
- This does not replace a Seqera Platform launch for validating a *new* edge — do that by
  hand first, exactly as runs 01–08 did, so a human inspects what the edge actually produces.
  Wrap it as a module and add it here once it's proven, the way `PLAN.md`'s validation table
  already distinguishes NATIVE/CONVERSION REQUIRED from UNVALIDATED.
- "Open to everybody" compute (a public AWS/GCP sandbox, so others can re-run this without
  cluster access) is a separate, unresolved question — de.NBI Cloud, nf-core's own
  AWS-sponsored compute, and Seqera's Community Showcase are the leads worth chasing, not
  something this orchestration layer itself provides.
