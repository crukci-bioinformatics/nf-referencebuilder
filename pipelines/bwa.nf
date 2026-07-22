process bwaIndex
{
    label 'builder'

    publishDir "${assemblyPath(genomeInfo)}", mode: 'copy'

    input:
        record(genomeInfo: Map, fastaFile: Path)

    output:
        tuple val(genomeInfo), path(indexDir)

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
        fastaChannel

    main:
        processingChannel = fastaChannel
            .filter \
            {
                r ->
                def bwaBase = "${assemblyPath(r.genomeInfo)}/bwa-${params.BWA_VERSION}/${r.genomeInfo.base}"
                def requiredFiles = [ file("${bwaBase}.bwt"), file("${bwaBase}.pac"), file("${bwaBase}.sa") ]
                return requiredFiles.any { !it.exists() }
            }

        bwaIndex(processingChannel)
}
