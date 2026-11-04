// Wraps scripts/converters/mag_to_proteinfamilies.py: pools mag's per-sample Prodigal
// proteins into the single pooled FASTA + one-row samplesheet proteinfamilies expects.
// See the script for the header-prefixing that keeps protein IDs unique across samples and
// the --expect guard against a silently-missing assembly.
//
// ${moduleDir} (this main.nf's own directory) is used rather than ${projectDir}, which
// resolves to the caller's root, not this repo's, when the module runs standalone.
//
// Unlike the other converters, this one *creates* a new file (the pooled FASTA) rather than
// only pointing at files a pipeline already published. The script embeds that file's
// resolved path in the samplesheet it writes; left alone, that would be this task's
// work-dir path, which Nextflow can prune later. The sed rewrite below points the
// samplesheet at publishDir's final location instead, before the task is considered done.

process MAG_TO_PROTEINFAMILIES {
    tag "$sample"
    container 'python:3.12-slim'
    publishDir params.outdir, mode: 'copy'

    input:
    val mag_outdir // mag's --outdir
    val sample     // sample name for the single pooled row
    val assembler  // mag assembler directory, e.g. MEGAHIT
    val expect     // '' (default) skips the guard; an int fails unless exactly that many
                    // Prodigal FASTAs are found, e.g. one failed assembly going unnoticed

    output:
    path "samplesheet.csv",  emit: samplesheet
    path "${sample}.faa.gz", emit: pooled_fasta

    script:
    def expect_arg = expect ? "--expect ${expect}" : ''
    """
    python3 ${moduleDir}/../../../scripts/converters/mag_to_proteinfamilies.py \\
        '${mag_outdir}' samplesheet.csv '${sample}.faa.gz' \\
        --sample '${sample}' --assembler '${assembler}' ${expect_arg}

    sed -i "s|\$(pwd)|${params.outdir}|" samplesheet.csv
    """
}

workflow {
    MAG_TO_PROTEINFAMILIES(
        params.mag_outdir,
        params.sample,
        params.assembler,
        params.expect,
    )
}
