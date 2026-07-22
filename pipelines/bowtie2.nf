/*
 * Function to test whether the Bowtie2 indexes exist. This is complicated
 * by the possibility that the suffix can be "bt2" or "bt2l".
 */
def bowtie2Exists(bowtieBase)
{
    def suffixes = [ 'bt2', 'bt2l' ]

    def forwardRequires = suffixes.collect { file("${bowtieBase}.1.${it}") }
    def forwardExists = forwardRequires.any { it.exists() }

    def reverseRequires = suffixes.collect { file("${bowtieBase}.rev.1.${it}") }
    def reverseExists = reverseRequires.any { it.exists() }

    return forwardExists && reverseExists
}

process bowtie2Index
{
    label 'builder'

    publishDir "${assemblyPath(genomeInfo)}", mode: 'copy'

    input:
        record(genomeInfo: Map, fastaFile: Path)

    output:
        tuple val(genomeInfo), path(indexDir)

    shell:
        indexDir = "bowtie2-${params.BOWTIE2_VERSION}"

        """
        mkdir "!{indexDir}"

        bowtie2-build \
            "!{fastaFile}" \
            "!{indexDir}/!{genomeInfo.base}"
        """
}

workflow bowtie2WF
{
    take:
        fastaChannel

    main:
        processingChannel = fastaChannel
            .filter \
            {
                r ->
                return !bowtie2Exists("${assemblyPath(r.genomeInfo)}/bowtie2-${params.BOWTIE2_VERSION}/${r.genomeInfo.base}")
            }

        bowtie2Index(processingChannel)
}
