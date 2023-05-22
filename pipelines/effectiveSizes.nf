include { assemblyPath } from '../functions/functions'
include { javaMemMB } from '../modules/nextflow-support/functions'

def calculateEffectiveGenomeSize(genomeInfo, jellyfishStatsFile, readLength, genomeLength)
{
    def uniqueMerCount = 0L
    def effectiveRatio = 0.0

    def lines = jellyfishStatsFile.readLines()
    if (!lines.empty)
    {
        uniqueMerCount = lines.first().split(/\s+/)[1] as long
        effectiveRatio = uniqueMerCount.doubleValue() / genomeLength.doubleValue()
    }
    return [
        readLength: readLength,
        genomeLength: genomeLength,
        size: uniqueMerCount,
        ratio: effectiveRatio
    ]
}

process createCanonicalFasta
{
    input:
        tuple val(genomeInfo), path(fastaFile), val(canonicalContigs)

    output:
        tuple val(genomeInfo), path(canonicalFasta), path(canonicalIndex)

    shell:
        canonicalFasta = "canonical.fa"
        canonicalIndex = "${canonicalFasta}.fai"

        """
        samtools faidx \
            "!{fastaFile}" \
            !{canonicalContigs.join(' ')} \
            > !{canonicalFasta}

        samtools faidx !{canonicalFasta}
        """
}

process jellyfishCount
{
    cpus = 4
    time = { 6.h * task.attempt }
    memory = { 64.GB * task.attempt }
    maxRetries = 3

    input:
        tuple val(genomeInfo), path(canonicalFasta), val(genomeLength), val(readLength)

    output:
        tuple val(genomeInfo), path(dataFile), val(readLength), val(genomeLength)

    shell:
        dataFile = 'jellyfish.data'

        """
        jellyfish count \
            -t !{task.cpus} \
            -m !{readLength} \
            -s !{genomeLength} \
            -L 1 -U 1 --out-counter-len 1 --counter-len 1 \
            -o !{dataFile} \
            !{canonicalFasta}
        """
}

process jellyfishStats
{
    label 'builder'

    input:
        tuple val(genomeInfo), path(dataFile), val(readLength), val(genomeLength)

    output:
        tuple val(genomeInfo), path(statsFile), val(readLength), val(genomeLength)

    shell:
        statsFile = 'jellyfish.stats'

        """
        jellyfish stats \
            -o !{statsFile} \
            !{dataFile}
        """
}

process effectiveGenomeSize
{
    label 'tiny'

    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), val(props)

    output:
        tuple val(genomeInfo), path(effectiveGenomeSizeFile)

    shell:
        effectiveGenomeSizeFile = "${genomeInfo.base}.effectivegenome.${props.readLength}.txt"
        """
        echo "genome=!{genomeInfo.base}\nread.length=!{props.readLength}\ngenome.length=!{props.genomeLength}\neffectivegenome.size=!{props.size}\neffectivegenome.ratio=!{props.ratio}" \
            > "!{effectiveGenomeSizeFile}"
        """
}

workflow effectiveGenomeSizesWF
{
    take:
        canonicalChannel

    main:
        def readLengths = [ 36, 50, 75, 100, 125, 150 ]
        readLengthsChannel = channel.fromList(readLengths)

        def contigChannel = canonicalChannel
            .map
            {
                genomeInfo, fastaFile, canonicalFile ->
                tuple genomeInfo, fastaFile, canonicalFile.readLines()
            }

        def processingCondition1 =
        {
            genomeInfo, fastaFile, canonicalContigs ->
            def annotationBase = "${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}"
            def requiredFiles = readLengths.collect { readLength -> file("${annotationBase}.effectivegenome.${readLength}.txt") }
            return requiredFiles.any { !it.exists() }
        }

        processingChoice1 = contigChannel.branch
        {
            doIt: processingCondition1(it)
            done: true
        }

        createCanonicalFasta(processingChoice1.doIt)

        jellyfishChannel = createCanonicalFasta.out
            .map
            {
                genomeInfo, canonicalFasta, canonicalIndex ->
                // Take the second column from the index and sum the size of the contigs.
                tuple genomeInfo, canonicalFasta, canonicalIndex.readLines().collect { it.split(/\s+/)[1] as long }.sum()
            }
            .combine(readLengthsChannel)

        def processingCondition2 =
        {
            genomeInfo, fastaFile, indexFile, readLength ->
            def annotationBase = "${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}"
            return !file("${annotationBase}.effectivegenome.${readLength}.txt").exists()
        }

        processingChoice2 = jellyfishChannel.branch
        {
            doIt: processingCondition2(it)
            done: true
        }

        jellyfishCount(processingChoice2.doIt) | jellyfishStats

        jellyfishNumberChannel = jellyfishStats.out
            .map
            {
                genomeInfo, statsFile, readLength, genomeLength ->
                tuple genomeInfo, calculateEffectiveGenomeSize(genomeInfo, statsFile, readLength, genomeLength)
            }

         effectiveGenomeSize(jellyfishNumberChannel)
}
