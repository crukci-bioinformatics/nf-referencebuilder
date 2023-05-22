/*
    Pipeline to fetch and prepare gene names files.

    The files can come from BioMart (Ensembl genomes) or from
    UCSC as XRef files.
*/

include { assemblyPath } from '../functions/functions'
include { javaMemMB } from '../modules/nextflow-support/functions'

/*
 * Fetch gene names from BioMart.
 */

process downloadBioMart
{
    label 'fetcher'

    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        val(genomeInfo)

    output:
        tuple val(genomeInfo), path(geneNamesFile)

    shell:
        geneNamesFile = "gene.names.${genomeInfo.base}.txt"
        martName = "${genomeInfo.martname}_gene_ensembl"

        """
        wget -O !{geneNamesFile} \
        http://www.ensembl.org/biomart/martservice?query="<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?><!DOCTYPE Query><Query virtualSchemaName=\\"default\\" formatter=\\"TSV\\" header=\\"0\\" uniqueRows=\\"1\\" count=\\"\\" datasetConfigVersion=\\"0.6\\"><Dataset name=\\"!{martName}\\" interface=\\"default\\"><Attribute name=\\"ensembl_gene_id\\"/><Attribute name=\\"external_gene_name\\"/><Attribute name=\\"description\\"/></Dataset></Query>"
        """
}

/*
 * Fetch gene names from UCSC Xref file.
 */

process fetchXRef
{
    label 'fetcher'

    input:
        val(genomeInfo)

    output:
        tuple val(genomeInfo), path(xrefFile)

    shell:
        xrefFile = "xref.txt.gz"

        """
        wget -O !{xrefFile} "!{genomeInfo['url.xref']}"
        """
}

process expandXRef
{
    input:
        tuple val(genomeInfo), path(inputFiles)

    output:
        tuple val(genomeInfo), path(outputFile)

    shell:
        outputFile = "xref.txt"

        javaMem = javaMemMB(task)
        outputFile = "xref.txt"
        template "ConcatenateFiles.sh"
}

process xrefToGeneNames
{
    label 'tiny'

    publishDir "${assemblyPath(genomeInfo)}/annotation", mode: 'copy'

    input:
        tuple val(genomeInfo), path(xrefFile)

    output:
        tuple val(genomeInfo), path(geneNamesFile)

    shell:
        geneNamesFile = "gene.names.${genomeInfo.base}.txt"

        """
        cut -f 1,5,8 \
        < !{xrefFile} \
        > !{geneNamesFile}
        """
}

/*
 * Work flow for the gene names file.
 */

workflow geneNamesWF
{
    take:
        genomeInfoChannel

    main:
        geneNamesChannel = genomeInfoChannel
            .filter
            {
                genomeInfo ->
                def annotationDir = "${assemblyPath(genomeInfo)}/annotation"
                def requiredFile = file("${annotationDir}/gene.names.${genomeInfo.base}.txt")
                return !requiredFile.exists()
            }

        def whichFormatCondition =
        {
            genomeInfo ->
            if (genomeInfo['martname'])
                return 'biomart'

            if (genomeInfo['url.xref'])
                return 'xref'

            return 'none'
        }

        sourceChoice = geneNamesChannel.branch
        {
            biomart: whichFormatCondition(it) == 'biomart'
            xref: whichFormatCondition(it) == 'xref'
            none: true
        }

        downloadBioMart(sourceChoice.biomart)

        fetchXRef(sourceChoice.xref) | expandXRef | xrefToGeneNames
}
