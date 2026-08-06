nextflow.enable.types = true

include { assemblyPath } from '../functions'

process bwaIndex
{
    label 'builder'

    publishDir { "${assemblyPath(genomeInfo)}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, fastaFile: Path)

    output:
        record(genomeInfo: genomeInfo, indexDir: file(indexDir))

    shell:
        indexDir = "bwa-${params.BWA_VERSION}"

        """
        mkdir "!{indexDir}"
        cd "!{indexDir}"

        bwa index \
            -a bwtsw \
            -p "!{genomeInfo.base}" \
            "../!{fastaFile}"
        """
}

workflow bwaWF
{
    take:
        fastaChannel: Channel<Record>

    main:
        processingChannel = fastaChannel.filter \
        {
            r ->
            def bwaBase = "${assemblyPath(r.genomeInfo)}/bwa-${params.BWA_VERSION}/${r.genomeInfo.base}"
            def requiredFiles = [ file("${bwaBase}.bwt"), file("${bwaBase}.pac"), file("${bwaBase}.sa") ]
            return requiredFiles.any { f -> !f.exists() }
        }

        bwaIndex(processingChannel)
}
