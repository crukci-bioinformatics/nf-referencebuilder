nextflow.enable.types = true

include { assemblyPath } from '../functions'

/*
 * Function to test whether the Bowtie2 indexes exist. This is complicated
 * by the possibility that the suffix can be "bt2" or "bt2l".
 */
def bowtie2Exists(bowtieBase: String)
{
    def suffixes = [ 'bt2', 'bt2l' ]

    def forwardRequires = suffixes.collect { s -> file("${bowtieBase}.1.${s}") }
    def forwardExists = forwardRequires.any { f -> f.exists() }

    def reverseRequires = suffixes.collect { s -> file("${bowtieBase}.rev.1.${s}") }
    def reverseExists = reverseRequires.any { f -> f.exists() }

    return forwardExists && reverseExists
}

process bowtie2Index
{
    label 'builder'

    publishDir { "${assemblyPath(genomeInfo)}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, fastaFile: Path)

    output:
        record(genomeInfo: genomeInfo, indexDir: file(indexDir))

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
        fastaChannel: Channel<Record>

    main:
        processingChannel = fastaChannel.filter \
        {
            r ->
            return !bowtie2Exists("${assemblyPath(r.genomeInfo)}/bowtie2-${params.BOWTIE2_VERSION}/${r.genomeInfo.base}")
        }

        bowtie2Index(processingChannel)
}
