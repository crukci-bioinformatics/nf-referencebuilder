#!/usr/bin/env nextflow

nextflow.enable.types = true

include { readGenomeInfo } from './functions'

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
