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
    publishDir params.outdir, mode: 'copy'

    input:
    val fetchngs_samplesheet // path to an existing nf-core/fetchngs samplesheet.csv
    val strategy             // ENA library_strategy to keep, e.g. RNA-Seq / WGS / AMPLICON
    val target               // reads | detaxizer | mag
    val prefix               // sample-name prefix
    val group                // --target mag only: co-abundance binning group

    output:
    path "samplesheet.csv", emit: samplesheet

    script:
    """
    python3 ${moduleDir}/../../../scripts/converters/fetchngs_to_reads_samplesheet.py \\
        '${fetchngs_samplesheet}' samplesheet.csv \\
        --strategy '${strategy}' --target '${target}' --prefix '${prefix}' --group '${group}'
    """
}

workflow {
    FETCHNGS_TO_SAMPLESHEET(
        params.fetchngs_samplesheet,
        params.strategy,
        params.target,
        params.prefix,
        params.group,
    )
}
