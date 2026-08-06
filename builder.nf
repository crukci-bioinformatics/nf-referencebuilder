#!/usr/bin/env nextflow

nextflow.enable.types = true

include { readGenomeInfo } from './functions'

include { setupWF } from './workflows/setup'
include { genomeInfoWF } from './workflows/info'
include { fastaWF } from './workflows/fasta'
include { annotationWF } from './workflows/annotation'
include { geneNamesWF } from './workflows/geneNames'
include { bwaWF } from './workflows/bwa'
include { bwamem2WF } from './workflows/bwamem2'
include { bowtie2WF } from './workflows/bowtie2'
include { starWF } from './workflows/star'
include { salmonWF } from './workflows/salmon'
include { effectiveGenomeSizesWF } from './workflows/effectiveSizes'

workflow
{
    log.info("Top level reference directory (params.referenceTop) is ${params.referenceTop}")

    hgConfChannel = setupWF()

    genomeInfoFileChannel = channel.fromPath("${params.genomeInfoDirectory}/*.properties")
    genomeInfoChannel = genomeInfoFileChannel.map { f -> readGenomeInfo(f) }

    genomeInfoWF(genomeInfoFileChannel)

    fastaOut = fastaWF(genomeInfoChannel)
    annotationOut = annotationWF(genomeInfoChannel, hgConfChannel)

    geneNamesWF(genomeInfoChannel)
    bwaWF(fastaOut.fastaChannel)
    bwamem2WF(fastaOut.fastaChannel)
    bowtie2WF(fastaOut.fastaChannel)
    starWF(fastaOut.fastaChannel, annotationOut.gtfChannel)
    salmonWF(fastaOut.fastaChannel)
    effectiveGenomeSizesWF(fastaOut.canonicalChannel)
}
