process bwamem2Index
{
    label 'builder'

    publishDir "${assemblyPath(genomeInfo)}", mode: 'copy'

    input:
        record(genomeInfo: Map, fastaFile: Path)

    output:
        tuple val(genomeInfo), path(indexDir)

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
        fastaChannel

    main:
        processingChannel = fastaChannel
            .filter \
            {
                r ->
                def bwamemBase = "${assemblyPath(r.genomeInfo)}/bwamem2-${params.BWAMEM2_VERSION}/${r.genomeInfo.base}"
                def requiredFiles = [ file("${bwamemBase}.0123"), file("${bwamemBase}.bwt.2bit.64"), file("${bwamemBase}.pac") ]
                return requiredFiles.any { !it.exists() }
            }

        bwamem2Index(processingChannel)
}
