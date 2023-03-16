#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include { readGenomeInfo } from './functions/functions'

include { setupWF } from './pipelines/setup'
include { genomeInfoWF } from './pipelines/info'
include { fastaWF } from './pipelines/fasta'
include { annotationWF } from './pipelines/annotation'
include { geneNamesWF } from './pipelines/geneNames'
include { bwaWF } from './pipelines/bwa'
include { bwamem2WF } from './pipelines/bwamem2'
include { bowtie2WF } from './pipelines/bowtie2'
include { starWF } from './pipelines/star'
include { salmonWF } from './pipelines/salmon'
include { effectiveGenomeSizesWF } from './pipelines/effectiveSizes'

workflow
{
    setupWF()

    genomeInfoFileChannel = channel
        .fromPath("${params.genomeInfoDirectory}/*.properties")

    genomeInfoWF(genomeInfoFileChannel)

    genomeInfoChannel = genomeInfoFileChannel
        .map { readGenomeInfo(it) }

    fastaWF(genomeInfoChannel)
    annotationWF(genomeInfoChannel, setupWF.out)
    geneNamesWF(genomeInfoChannel)
    bwaWF(fastaWF.out.fastaChannel)
    bwamem2WF(fastaWF.out.fastaChannel)
    bowtie2WF(fastaWF.out.fastaChannel)
    starWF(fastaWF.out.fastaChannel, annotationWF.out.gtfChannel)
    salmonWF(fastaWF.out.fastaChannel)
    effectiveGenomeSizesWF(fastaWF.out.canonicalChannel)
}
