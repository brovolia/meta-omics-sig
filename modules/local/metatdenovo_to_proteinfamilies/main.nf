// Wraps scripts/converters/metatdenovo_to_proteinfamilies.py: locates metatdenovo's
// protein FASTA (its location and extension depend on which ORF caller ran) and builds the
// one-row samplesheet nf-core/proteinfamilies requires. See the script for why
// transdecoder's .pep.gz is refused rather than silently passed through.
//
// ${moduleDir} (this main.nf's own directory) is used rather than ${projectDir}, which
// resolves to the caller's root, not this repo's, when the module runs standalone. Unlike
// mag_to_proteinfamilies, this converter only points at a FASTA metatdenovo already
// published -- it creates nothing new -- so no path rewrite is needed after the fact.

process METATDENOVO_TO_PROTEINFAMILIES {
    tag "$sample"
    container 'python:3.12-slim'
    // Singularity on this cluster's ccga_cau profile only auto-mounts the task work dir
    // (same gap already documented for PROKKA in AGENTS.md), so the converter script
    // above -- living outside the work dir, under this repo's own checkout -- is
    // otherwise invisible inside the container.
    containerOptions "-B ${moduleDir.resolve('../../../scripts').normalize()}"
    publishDir params.outdir, mode: 'copy'

    input:
    // `path`, not `val`, so Nextflow stages it (resolving a relative value against the
    // launch dir) rather than passing the string straight through. `stageAs:` pins the
    // staged directory name explicitly -- see fetchngs_to_samplesheet/main.nf for why an
    // input/output basename collision is a real, reproduced bug, not a theoretical one.
    path metatdenovo_outdir, stageAs: 'input_metatdenovo_outdir'
    val sample             // sample name for the single row

    output:
    path "samplesheet.csv", emit: samplesheet

    script:
    """
    python3 ${moduleDir}/../../../scripts/converters/metatdenovo_to_proteinfamilies.py \\
        '${metatdenovo_outdir}' samplesheet.csv --sample '${sample}'
    """
}

workflow {
    METATDENOVO_TO_PROTEINFAMILIES(
        file(params.metatdenovo_outdir),
        params.sample,
    )
}
