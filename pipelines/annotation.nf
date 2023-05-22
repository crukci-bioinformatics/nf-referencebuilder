/*
    Pipeline to fetch and prepare annotation files.

    Fetches the file from one of three source formats (GTF, KnownGene or EnsGene)
    and produces both a GTF file and a RefFlat file for annotation regardless of
    the source format.
*/

include { assemblyPath } from '../functions/functions'
include { javaMemMB } from '../modules/nextflow-support/functions'

/*
 * Processes where the annotation source is GTF.
 */

process fetchGtf
{
    label 'fetcher'

    input:
        val(genomeInfo)

    output:
        tuple val(genomeInfo), path(gtfFile)

    shell:
        gtfFile = "downloaded.gtf"

        """
        wget -O !{gtfFile} "!{genomeInfo['url.gtf']}"
        """
}

process expandGtf
{
    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(inputFiles)

    output:
        tuple val(genomeInfo), path(outputFile)

    shell:
        javaMem = javaMemMB(task)
        outputFile = "${genomeInfo.base}.gtf"
        template "ConcatenateFiles.sh"
}

process refFlatFromGTF
{
    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(gtfFile)

    output:
        tuple val(genomeInfo), path(refFlatFile)

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
        val(genomeInfo)

    output:
        tuple val(genomeInfo), path(knownGeneFile)

    shell:
        knownGeneFile = "downloaded.knowngene.txt"

        """
        wget -O !{knownGeneFile} "!{genomeInfo['url.knowngene']}"
        """
}

process expandKnownGene
{
    input:
        tuple val(genomeInfo), path(inputFiles)

    output:
        tuple val(genomeInfo), path(outputFile)

    shell:
        javaMem = javaMemMB(task)
        outputFile = "knowngene.txt"
        template "ConcatenateFiles.sh"
}

process gtfFromKnownGene
{
    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(knownGeneFile)
        each path(hgConfChannel)

    output:
        tuple val(genomeInfo), path(gtfFile)

    shell:
        gtfFile = "${genomeInfo.base}.gtf"

        urlPath = file(new java.net.URL(genomeInfo['url.knowngene']).path)
        database = urlPath.parent.parent.name
        table = urlPath.name.replaceAll(/\.txt(\.gz)?$/, '')

        template "annotation/genePredToGTF.sh"
}

process refFlatFromKnownGene
{
    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(knownGeneFile)

    output:
        tuple val(genomeInfo), path(refFlatFile)

    shell:
        refFlatFile = "${genomeInfo.base}.txt"

        """
        python \
            "!{projectDir}/python/knownGeneToRefFlat.py" \
            < !{knownGeneFile} \
            > !{refFlatFile}
        """
}

/*
 * Processes where the annotation source is EnsGene.
 */

process fetchEnsGene
{
    label 'fetcher'

    input:
        val(genomeInfo)

    output:
        tuple val(genomeInfo), path(ensGeneFile)

    shell:
        ensGeneFile = "downloaded.ensgene.txt"

        """
        wget -O !{ensGeneFile} "!{genomeInfo['url.ensgene']}"
        """
}

process expandEnsGene
{
    input:
        tuple val(genomeInfo), path(inputFiles)

    output:
        tuple val(genomeInfo), path(outputFile)

    shell:
        javaMem = javaMemMB(task)
        outputFile = "ensgene.txt"
        template "ConcatenateFiles.sh"
}

process gtfFromEnsGene
{
    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(ensGeneFile)
        each path(hgConfChannel)

    output:
        tuple val(genomeInfo), path(gtfFile)

    shell:
        gtfFile = "${genomeInfo.base}.gtf"

        urlPath = file(new java.net.URL(genomeInfo['url.ensgene']).path)
        database = urlPath.parent.parent.name
        table = urlPath.name.replaceAll(/\.txt(\.gz)?$/, '')

        template "annotation/genePredToGTF.sh"
}

process refFlatFromEnsGene
{
    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(ensGeneFile)

    output:
        tuple val(genomeInfo), path(refFlatFile)

    shell:
        refFlatFile = "${genomeInfo.base}.txt"

        """
        python \
            "!{projectDir}/python/ensGeneToRefFlat.py" \
            < !{ensGeneFile} \
            > !{refFlatFile}
        """
}


workflow annotationWF
{
    take:
        genomeInfoChannel
        hgConfChannel

    main:
        def processingCondition =
        {
            genomeInfo ->
            def annotationBase = "${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}"
            def requiredFiles = [ file("${annotationBase}.gtf"), file("${annotationBase}.txt") ]
            return requiredFiles.any { !it.exists() }
        }

        processingChoice = genomeInfoChannel.branch
        {
            doIt: processingCondition(it)
            done: true
        }

        def whichFormatCondition =
        {
            genomeInfo ->
            if (genomeInfo['url.gtf'])
                return 'gtf'

            if (genomeInfo['url.knowngene'])
                return 'knowngene'

            if (genomeInfo['url.ensgene'])
                return 'ensgene'

            return 'none'
        }

        sourceChoice = processingChoice.doIt.branch
        {
            gtf: whichFormatCondition(it) == 'gtf'
            knowngene: whichFormatCondition(it) == 'knowngene'
            ensgene: whichFormatCondition(it) == 'ensgene'
            none: true
        }

        fetchGtf(sourceChoice.gtf) | expandGtf | refFlatFromGTF

        fetchKnownGene(sourceChoice.knowngene) | expandKnownGene
        gtfFromKnownGene(expandKnownGene.out, hgConfChannel)
        refFlatFromKnownGene(expandKnownGene.out)

        fetchEnsGene(sourceChoice.ensgene) | expandEnsGene
        gtfFromEnsGene(expandEnsGene.out, hgConfChannel)
        refFlatFromEnsGene(expandEnsGene.out)

        gtfAlreadyHere = processingChoice.done.map
        {
            genomeInfo ->
            tuple genomeInfo, file("${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}.gtf")
        }

        refFlatAlreadyHere = processingChoice.done.map
        {
            genomeInfo ->
            tuple genomeInfo, file("${assemblyPath(genomeInfo)}/annotation/${genomeInfo.base}.txt")
        }

        gtfChannel = gtfAlreadyHere.mix(expandGtf.out).mix(gtfFromKnownGene.out).mix(gtfFromEnsGene.out)
        refFlatChannel = refFlatAlreadyHere.mix(refFlatFromGTF.out).mix(refFlatFromKnownGene.out).mix(refFlatFromEnsGene.out)

    emit:
        gtfChannel = gtfChannel
        refFlatChannel = refFlatChannel
}
