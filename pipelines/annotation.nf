nextflow.enable.types = true

include { javaMemoryOptions } from 'plugin/nf-crukci-support'
include { assemblyPath } from '../functions'

/*
    Pipeline to fetch and prepare annotation files.

    Fetches the file from one of three source formats (GTF, KnownGene or EnsGene)
    and produces both a GTF file and a RefFlat file for annotation regardless of
    the source format.
*/

/*
 * Processes where the annotation source is GTF.
 */

process fetchGtf
{
    label 'fetcher'

    input:
        genomeInfo: Properties

    output:
        record(genomeInfo: genomeInfo, gtfFile: file(gtfFile))

    shell:
        gtfFile = "downloaded.gtf"

        """
        wget !{params.wgetOptions} -O !{gtfFile} "!{genomeInfo['url.gtf']}"
        """
}

process expandGtf
{
    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, gtfFile: Path)

    output:
        record(genomeInfo: genomeInfo, gtfFile: file(outputFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        inputFiles = [ gtfFile ]
        outputFile = "${genomeInfo.base}.gtf"
        template "ConcatenateFiles.sh"
}

process refFlatFromGTF
{
    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, gtfFile: Path)

    output:
        record(genomeInfo: genomeInfo, refFlatFile: file(refFlatFile))

    shell:
        refFlatFile = "${genomeInfo.base}.txt"
        template "annotation/gtfToGenePred.sh"
}

/*
 * Processes where the annotation source is KnownGene.
 */

process fetchKnownGene
{
    label 'fetcher'

    input:
        genomeInfo: Properties

    output:
        record(genomeInfo: genomeInfo, knownGeneFile: file(knownGeneFile))

    shell:
        knownGeneFile = "downloaded.knowngene.txt"

        """
        wget !{params.wgetOptions} -O !{knownGeneFile} "!{genomeInfo['url.knowngene']}"
        """
}

process expandKnownGene
{
    input:
        record(genomeInfo: Properties, knownGeneFile: Path)

    output:
        record(genomeInfo: genomeInfo, knownGeneFile: file(outputFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        inputFiles = [ knownGeneFile ]
        outputFile = "knowngene.txt"
        template "ConcatenateFiles.sh"
}

process gtfFromKnownGene
{
    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, knownGeneFile: Path)
        hgConf: Path

    output:
        record(genomeInfo: genomeInfo, gtfFile: file(gtfFile))

    shell:
        gtfFile = "${genomeInfo.base}.gtf"

        urlPath = file(new java.net.URL(genomeInfo['url.knowngene']).path)
        database = urlPath.parent.parent.name
        table = urlPath.name.replaceAll(/\.txt(\.gz)?$/, '')

        template "annotation/genePredToGTF.sh"
}

process refFlatFromKnownGene
{
    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, knownGeneFile: Path)

    output:
        record(genomeInfo: genomeInfo, refFlatFile: file(refFlatFile))

    shell:
        refFlatFile = "${genomeInfo.base}.txt"

        """
        python3 \
            "!{projectDir}/python/knownGeneToRefFlat.py" \
            < "!{knownGeneFile}" \
            > "!{refFlatFile}"
        """
}

/*
 * Processes where the annotation source is EnsGene.
 */

process fetchEnsGene
{
    label 'fetcher'

    input:
        genomeInfo: Properties

    output:
        record(genomeInfo: genomeInfo, ensGeneFile: file(ensGeneFile))

    shell:
        ensGeneFile = "downloaded.ensgene.txt"

        """
        wget !{params.wgetOptions} -O !{ensGeneFile} "!{genomeInfo['url.ensgene']}"
        """
}

process expandEnsGene
{
    input:
        record(genomeInfo: Properties, ensGeneFile: Path)

    output:
        record(genomeInfo: genomeInfo, ensGeneFile: file(outputFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        inputFiles = [ ensGeneFile ]
        outputFile = "ensgene.txt"
        template "ConcatenateFiles.sh"
}

process gtfFromEnsGene
{
    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, ensGeneFile: Path)
        hgConf: Path

    output:
        record(genomeInfo: genomeInfo, gtfFile: file(gtfFile))

    shell:
        gtfFile = "${genomeInfo.base}.gtf"

        urlPath = file(new java.net.URL(genomeInfo['url.ensgene']).path)
        database = urlPath.parent.parent.name
        table = urlPath.name.replaceAll(/\.txt(\.gz)?$/, '')

        template "annotation/genePredToGTF.sh"
}

process refFlatFromEnsGene
{
    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, ensGeneFile: Path)

    output:
        record(genomeInfo: genomeInfo, refFlatFile: file(refFlatFile))

    shell:
        refFlatFile = "${genomeInfo.base}.txt"

        """
        python3 \
            "!{projectDir}/python/ensGeneToRefFlat.py" \
            < "!{ensGeneFile}" \
            > "!{refFlatFile}"
        """
}

/*
 * Work flow and supporting functions.
 */

def processingCondition(genomeInfo: Properties)
{
    def annotationBase = "${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}"
    def requiredFiles = [ file("${annotationBase}.gtf"), file("${annotationBase}.txt") ]
    return requiredFiles.any { f -> !f.exists() }
}

def whichFormatCondition(genomeInfo: Properties)
{
    if (genomeInfo['url.gtf'])
        return 'gtf'

    if (genomeInfo['url.knowngene'])
        return 'knowngene'

    if (genomeInfo['url.ensgene'])
        return 'ensgene'

    return 'none'
}

workflow annotationWF
{
    take:
        genomeInfoChannel: Channel<Properties>
        hgConfChannel: Channel<Path>

    main:
        processingChoice = genomeInfoChannel.branch \
        {
            genomeInfo ->
            doIt: processingCondition(genomeInfo)
            done: true
        }

        sourceChoice = processingChoice.doIt.branch \
        {
            genomeInfo ->
            gtf: whichFormatCondition(genomeInfo) == 'gtf'
            knowngene: whichFormatCondition(genomeInfo) == 'knowngene'
            ensgene: whichFormatCondition(genomeInfo) == 'ensgene'
            none: true
        }

        sourceGtf = fetchGtf(sourceChoice.gtf)
        expandedGtf = expandGtf(sourceGtf)
        refFlatGtf = refFlatFromGTF(expandedGtf)

        sourceKnownGene = fetchKnownGene(sourceChoice.knowngene)
        expandedKnownGene = expandKnownGene(sourceKnownGene)
        gtfKnownGene = gtfFromKnownGene(expandedKnownGene, hgConfChannel)
        refFlatKnownGene = refFlatFromKnownGene(expandedKnownGene)

        sourceEnsGene = fetchEnsGene(sourceChoice.ensgene)
        expandedEnsGene = expandEnsGene(sourceEnsGene)
        gtfEnsGene = gtfFromEnsGene(expandedEnsGene, hgConfChannel)
        refFlatEnsGene = refFlatFromEnsGene(expandedEnsGene)

        gtfAlreadyHere = processingChoice.done.map \
        {
            genomeInfo ->
            record(genomeInfo: genomeInfo, gtfFile: file("${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}.gtf"))
        }

        refFlatAlreadyHere = processingChoice.done.map \
        {
            genomeInfo ->
            record(genomeInfo: genomeInfo, refFlatFile: file("${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}.txt"))
        }

        gtfChannel = gtfAlreadyHere.mix(expandedGtf).mix(gtfKnownGene).mix(gtfEnsGene)

        refFlatChannel = refFlatAlreadyHere.mix(refFlatGtf).mix(refFlatKnownGene).mix(refFlatEnsGene)

    emit:
        gtfChannel: Channel<Record> = gtfChannel
        refFlatChannel: Channel<Record> = refFlatChannel
}
