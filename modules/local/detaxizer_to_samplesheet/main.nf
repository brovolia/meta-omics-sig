// Wraps scripts/converters/detaxizer_to_reads_samplesheet.py: detaxizer's
// --generate_pipeline_samplesheets enum stops at taxprofiler/mag, so metatdenovo, ampliseq
// and viralmetagenome all need this step to pick up detaxizer's filtered reads. See the
// script itself for the seqkit/bbmap filename handling and the paired-mate checks.
//
// ${moduleDir} (this main.nf's own directory) is used rather than ${projectDir}, which
// resolves to the caller's root, not this repo's, when the module runs standalone.

process DETAXIZER_TO_SAMPLESHEET {
    container 'python:3.12-slim'
    // Singularity on this cluster's ccga_cau profile only auto-mounts the task work dir
    // (same gap already documented for PROKKA in AGENTS.md), so the converter script
    // above -- living outside the work dir, under this repo's own checkout -- is
    // otherwise invisible inside the container.
    containerOptions "-B ${moduleDir.resolve('../../../scripts').normalize()}"
    publishDir params.outdir, mode: 'copy'

    input:
    // `path`, not `val`, so Nextflow stages it (resolving a relative value against the
    // launch dir) rather than passing the string straight through to the script.
    // `stageAs:` pins the staged directory name explicitly rather than relying on whatever
    // the real detaxizer outdir happens to be called -- see fetchngs_to_samplesheet/main.nf
    // for why an input/output basename collision is a real, reproduced bug, not a
    // theoretical one.
    path detaxizer_outdir, stageAs: 'input_detaxizer_outdir'

    output:
    path "samplesheet.csv", emit: samplesheet

    script:
    """
    python3 ${moduleDir}/../../../scripts/converters/detaxizer_to_reads_samplesheet.py \\
        '${detaxizer_outdir}' samplesheet.csv
    """
}

workflow {
    DETAXIZER_TO_SAMPLESHEET(file(params.detaxizer_outdir))
}
