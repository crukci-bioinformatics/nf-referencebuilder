nextflow.enable.types = true

include { assemblyPath } from '../functions'

process createCanonicalFasta
{
    input:
        record(genomeInfo: Properties, fastaFile: Path, canonicalContigs: List<String>)

    output:
        record(genomeInfo: genomeInfo, canonicalFasta: file(canonicalFasta), canonicalIndex: file(canonicalIndex))

    shell:
        canonicalFasta = "canonical.fa"
        canonicalIndex = "${canonicalFasta}.fai"

        """
        samtools faidx \
            "!{fastaFile}" \
            "!{canonicalContigs.join('" "')}" \
            > "!{canonicalFasta}"

        samtools faidx "!{canonicalFasta}"
        """
}

process jellyfishCount
{
    input:
        record(genomeInfo: Properties, canonicalFasta: Path, genomeLength: Long, readLength: Integer)

    output:
        record(genomeInfo: genomeInfo, jellyfishDataFile: file(dataFile), genomeLength: genomeLength, readLength: readLength)

    shell:
        dataFile = 'jellyfish.data'

        """
        jellyfish count \
            -t !{task.cpus} \
            -m !{readLength} \
            -s !{genomeLength} \
            -L 1 -U 1 --out-counter-len 1 --counter-len 1 \
            -o "!{dataFile}" \
            "!{canonicalFasta}"
        """
}

process jellyfishStats
{
    label 'builder'

    input:
        record(genomeInfo: Properties, jellyfishDataFile: Path, genomeLength: Long, readLength: Integer)

    output:
        record(genomeInfo: genomeInfo, jellyfishStatsFile: file(statsFile), genomeLength: genomeLength, readLength: readLength)

    shell:
        statsFile = 'jellyfish.stats'

        """
        jellyfish stats \
            -o "!{statsFile}" \
            "!{jellyfishDataFile}"
        """
}

process effectiveGenomeSize
{
    label 'tiny'

    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, props: Map)

    output:
        record(genomeInfo: genomeInfo, effectiveGenomeSizeFile: file(effectiveGenomeSizeFile))

    shell:
        effectiveGenomeSizeFile = "${genomeInfo.base}.effectivegenome.${props.readLength}.txt"
        """
        echo "genome=!{genomeInfo.base}\nread.length=!{props.readLength}\ngenome.length=!{props.genomeLength}\neffectivegenome.size=!{props.size}\neffectivegenome.ratio=!{props.ratio}" \
            > "!{effectiveGenomeSizeFile}"
        """
}

/*
 * Functions and work flow.
 */

def calculateEffectiveGenomeSize(genomeInfo: Properties, jellyfishStatsFile: Path, genomeLength: Long, readLength: Integer)
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

def processingCondition1(genomeInfo: Properties, readLengths: List<Integer>)
{
    def annotationBase = "${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}"
    def requiredFiles = readLengths.collect { readLength -> file("${annotationBase}.effectivegenome.${readLength}.txt") }
    return requiredFiles.any { f -> !f.exists() }
}

def processingCondition2(genomeInfo: Properties, readLength: Integer)
{
    def annotationBase = "${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}"
    return !file("${annotationBase}.effectivegenome.${readLength}.txt").exists()
}

workflow effectiveGenomeSizesWF
{
    take:
        canonicalChannel: Channel<Record>

    main:
        def readLengths = [ 36, 50, 75, 100, 125, 150 ]
        readLengthsChannel = channel.fromList(readLengths)

        def contigChannel = canonicalChannel
            .map { r ->
                record(genomeInfo: r.genomeInfo, fastaFile: r.fastaFile, canonicalContigs: r.canonicalFile.readLines())
            }
            .filter { r ->
                processingCondition1(r.genomeInfo, readLengths)
            }

        canonicalFasta = createCanonicalFasta(contigChannel)

        jellyfishChannel = canonicalFasta
            .combine(readLengthsChannel)
            .map { r, readLength ->
                // Take the second column from the index and sum the size of the contigs.
                record(genomeInfo: r.genomeInfo,
                       canonicalFasta: r.canonicalFasta,
                       genomeLength: r.canonicalIndex.readLines().collect { line -> line.split(/\s+/)[1] as long }.sum(),
                       readLength: readLength)
            }
            .filter { r ->
                processingCondition2(r.genomeInfo, r.readLength)
            }

        counts = jellyfishCount(jellyfishChannel)
        stats = jellyfishStats(counts)

        jellyfishNumberChannel = stats
            .map { r ->
                record(genomeInfo: r.genomeInfo, props: calculateEffectiveGenomeSize(r.genomeInfo, r.jellyfishStatsFile, r.genomeLength, r.readLength))
            }

        effectiveGenomeSize(jellyfishNumberChannel)
}
