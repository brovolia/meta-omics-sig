// Wraps scripts/converters/detaxizer_to_reads_samplesheet.py: detaxizer's
// --generate_pipeline_samplesheets enum stops at taxprofiler/mag, so metatdenovo, ampliseq
// and viralmetagenome all need this step to pick up detaxizer's filtered reads. See the
// script itself for the seqkit/bbmap filename handling and the paired-mate checks.
//
// ${moduleDir} (this main.nf's own directory) is used rather than ${projectDir}, which
// resolves to the caller's root, not this repo's, when the module runs standalone.

process DETAXIZER_TO_SAMPLESHEET {
    container 'python:3.12-slim'
    publishDir params.outdir, mode: 'copy'

    input:
    val detaxizer_outdir // detaxizer's --outdir

    output:
    path "samplesheet.csv", emit: samplesheet

    script:
    """
    python3 ${moduleDir}/../../../scripts/converters/detaxizer_to_reads_samplesheet.py \\
        '${detaxizer_outdir}' samplesheet.csv
    """
}

workflow {
    DETAXIZER_TO_SAMPLESHEET(params.detaxizer_outdir)
}
