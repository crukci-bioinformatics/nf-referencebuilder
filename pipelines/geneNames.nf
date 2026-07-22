nextflow.enable.types = true

include { javaMemoryOptions } from 'plugin/nf-crukci-support'
include { assemblyPath } from '../functions'

/*
    Pipeline to fetch and prepare gene names files.

    The files can come from BioMart (Ensembl genomes) or from
    UCSC as XRef files.
*/

/*
 * Fetch gene names from BioMart.
 */

process downloadBioMart
{
    label 'fetcher'

    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        genomeInfo: Properties

    output:
        record(genomeInfo: genomeInfo, geneNamesFile: file(geneNamesFile))

    shell:
        geneNamesFile = "gene.names.${genomeInfo.base}.txt"
        martName = "${genomeInfo.martname}_gene_ensembl"

        """
        wget !{params.wgetOptions} -O "!{geneNamesFile}" \
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
        genomeInfo: Properties

    output:
        record(genomeInfo: genomeInfo, xrefFile: file(xrefFile))

    shell:
        xrefFile = "xref.txt.gz"

        """
        wget !{params.wgetOptions} -O "!{xrefFile}" "!{genomeInfo['url.xref']}"
        """
}

process expandXRef
{
    input:
        record(genomeInfo: Properties, xrefFile: Path)

    output:
        record(genomeInfo: genomeInfo, xrefFile: file(outputFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        inputFiles = [ xrefFile ]
        outputFile = "xref.txt"
        template "ConcatenateFiles.sh"
}

process xrefToGeneNames
{
    label 'tiny'

    publishDir { "${assemblyPath(genomeInfo)}/annotation" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, xrefFile: Path)

    output:
        record(genomeInfo: genomeInfo, geneNamesFile: file(geneNamesFile))

    shell:
        geneNamesFile = "gene.names.${genomeInfo.base}.txt"

        """
        cut -f 1,5,8 \
        < "!{xrefFile}" \
        > "!{geneNamesFile}"
        """
}

/*
 * Work flow and functions for the gene names file.
 */

def whichFormatCondition(genomeInfo: Properties)
{
    if (genomeInfo['martname'])
        return 'biomart'

    if (genomeInfo['url.xref'])
        return 'xref'

    return 'none'
}

workflow geneNamesWF
{
    take:
        genomeInfoChannel: Channel<Properties>

    main:
        geneNamesChannel = genomeInfoChannel.filter \
        {
            genomeInfo ->
            def annotationDir = "${assemblyPath(genomeInfo)}/annotation"
            def requiredFile = file("${annotationDir}/gene.names.${genomeInfo.base}.txt")
            return !requiredFile.exists()
        }

        sourceChoice = geneNamesChannel.branch \
        {
            genomeInfo ->
            biomart: whichFormatCondition(genomeInfo) == 'biomart'
            xref: whichFormatCondition(genomeInfo) == 'xref'
            none: true
        }

        downloadBioMart(sourceChoice.biomart)

        sourceXRef = fetchXRef(sourceChoice.xref)
        expandedXRef = expandXRef(sourceXRef)
        geneNamesXRef = xrefToGeneNames(expandedXRef)
}
