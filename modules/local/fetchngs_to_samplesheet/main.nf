// Wraps scripts/converters/fetchngs_to_reads_samplesheet.py as a first-class, cacheable
// Nextflow step, so the fetchngs -> {reads,detaxizer,mag} handoff is a DAG node instead of
// a manual "run script by hand" gap between two pipeline launches.
//
// Calls the existing, selftested converter unchanged via its own CLI -- this module adds no
// conversion logic of its own, only the wiring. ${moduleDir} (the directory of *this* main.nf,
// stable regardless of how the module is invoked -- standalone, or as an nf-meta nf-module
// step) is used rather than ${projectDir}, which resolves to the caller's own root, not this
// repo's. See the script itself for the conversion: column rename, mag's group/platform
// columns, and LMO's collection_date-based sample naming.

process FETCHNGS_TO_SAMPLESHEET {
    tag "$target"
    container 'python:3.12-slim'
    // Singularity on this cluster's ccga_cau profile only auto-mounts the task work dir
    // (same gap already documented for PROKKA in AGENTS.md), so the converter script
    // above -- living outside the work dir, under this repo's own checkout -- is
    // otherwise invisible inside the container: `python3: can't open file '.../
    // scripts/converters/fetchngs_to_reads_samplesheet.py': No such file or directory`.
    containerOptions "-B ${moduleDir.resolve('../../../scripts').normalize()}"
    publishDir params.outdir, mode: 'copy'

    input:
    // `path`, not `val`: Nextflow stages it into the task dir (resolving a relative value
    // against the launch dir) rather than passing the string straight through to the
    // script. `stageAs:` pins the staged name explicitly: fetchngs' own output is itself
    // conventionally named samplesheet.csv, same as this process' own output below -- left
    // to its default staged name (its original basename), the input and output would
    // collide on disk, and the script's write-mode open() on that name would follow the
    // staged symlink back and silently overwrite fetchngs' real output. Confirmed by
    // reproducing it: the source file's content and md5 changed after a run.
    path fetchngs_samplesheet, stageAs: 'input_samplesheet.csv'
    val strategy             // ENA library_strategy to keep, e.g. RNA-Seq / WGS / AMPLICON
    val target               // reads | detaxizer | mag
    val prefix               // sample-name prefix
    val group                // --target mag only: co-abundance binning group

    output:
    path "samplesheet.csv", emit: samplesheet

    script:
    """
    python3 ${moduleDir.resolve('../../../scripts/converters/fetchngs_to_reads_samplesheet.py').normalize()} \\
        '${fetchngs_samplesheet}' samplesheet.csv \\
        --strategy '${strategy}' --target '${target}' --prefix '${prefix}' --group '${group}'
    """
}

workflow {
    FETCHNGS_TO_SAMPLESHEET(
        file(params.fetchngs_samplesheet),
        params.strategy,
        params.target,
        params.prefix,
        params.group,
    )
}
