nextflow.enable.types = true

include { assemblyPath } from '../functions'

process bwamem2Index
{
    label 'builder'

    publishDir { "${assemblyPath(genomeInfo)}" }, mode: 'copy'

    input:
        record(genomeInfo: Map, fastaFile: Path)

    output:
        record(genomeInfo: genomeInfo, indexDir: file(indexDir))

    shell:
        indexDir = "bwamem2-${params.BWAMEM2_VERSION}"

        """
        mkdir "!{indexDir}"
        cd "!{indexDir}"

        bwa-mem2 index \
            -p "!{genomeInfo.base}" \
            "../!{fastaFile}"
        """
}

workflow bwamem2WF
{
    take:
        fastaChannel: Channel<Record>

    main:
        processingChannel = fastaChannel.filter \
        {
            r ->
            def bwamemBase = "${assemblyPath(r.genomeInfo)}/bwamem2-${params.BWAMEM2_VERSION}/${r.genomeInfo.base}"
            def requiredFiles = [ file("${bwamemBase}.0123"), file("${bwamemBase}.bwt.2bit.64"), file("${bwamemBase}.pac") ]
            return requiredFiles.any { f -> !f.exists() }
        }

        bwamem2Index(processingChannel)
}
