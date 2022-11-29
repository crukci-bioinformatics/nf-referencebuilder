/*
 * Building salmon indexes isn't a simple case of running a tool on a
 * reference file as most of the others are.
 * See https://redmine-bioinformatics.cruk.cam.ac.uk/issues/7243
 */

include { assemblyPath; javaMemMB } from '../functions/functions'

process fetchTranscripts
{
    label 'tiny'

    when:
        genomeInfo['url.transcripts.fasta'] != null

    input:
        tuple val(genomeInfo), path(genomeFile)

    output:
        tuple val(genomeInfo), path(genomeFile), path(outputFile)

    shell:
        outputFile = "transcripts"

        """
        curl -s -o !{outputFile} "!{genomeInfo['url.transcripts.fasta']}"
        """
}

process installTranscripts
{
    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy'

    input:
        tuple val(genomeInfo), path(genomeFile), path(inputFiles)

    output:
        tuple val(genomeInfo), path(genomeFile), path(outputFile)

    shell:
        javaMem = javaMemMB(task)
        outputFile = "${genomeInfo.base}.transcripts.fa"
        template "ConcatenateFiles.sh"
}

process indexTranscripts
{
    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy', pattern: '*.fai'

    input:
        tuple val(genomeInfo), path(genomeFile), path(transcriptsFile)

    output:
        tuple val(genomeInfo), path(transcriptsFile), path(indexFile)

    shell:
        indexFile = transcriptsFile.name + ".fai"

        """
        !{params.SAMTOOLS} faidx !{transcriptsFile}
        """
}

process createDecoys
{
    label 'tiny'

    input:
        tuple val(genomeInfo), path(genomeFile), path(transcriptsFile)

    output:
        tuple val(genomeInfo), path(decoysFile)

    shell:
        decoysFile = "${genomeInfo.base}.decoys.txt"

        """
        cat "!{transcriptsFile}" | \
        grep '>' | \
        cut -d " " -f 1 | \
        sed 's/>//' > \
        ${decoysFile}
        """
}

process combineGenomeAndTranscripts
{
    input:
        tuple val(genomeInfo), path(inputFiles)

    output:
        tuple val(genomeInfo), path(outputFile)

    shell:
        javaMem = javaMemMB(task)
        outputFile = "${genomeInfo.base}.all.fa"
        template "ConcatenateFiles.sh"
}

process salmonIndex
{
    label 'builder'
    cpus 6

    tag = { "${genomeInfo.base} k${kmer}" }

    publishDir "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}", mode: 'copy'

    input:
        tuple val(genomeInfo), path(fastaFile), path(decoysFile), val(kmer)

    output:
        tuple val(genomeInfo), path(indexDir)

    shell:
        indexDir = "k${kmer}"

        """
        !{params.SALMON} index \
            --transcripts "!{fastaFile}" \
            --decoys "!{decoysFile}" \
            --kmerLen !{kmer} \
            !{genomeInfo.gencode ? '--gencode' : ''} \
            --threads !{task.cpus} \
            --index !{indexDir} \
            --tmpdir temp
        """
}

process transcriptToGene
{
    label 'tiny'
    executor 'local'

    publishDir "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}", mode: 'copy'

    input:
        tuple val(genomeInfo), path(transcriptsFile), path(indexFile)

    output:
        tuple val(genomeInfo), path(mappingFile)

    shell:
        mappingFile = "tx2gene.tsv"

        """
        echo -e "TxID\tGeneID" > !{mappingFile}
        cat !{transcriptsFile} | \
            egrep '^>' | \
            cut -d '|' -f1,2 | \
            sed -e 's/>//' | \
            tr '|' '\t' \
            >> !{mappingFile}
        """
}

workflow salmonWF
{
    take:
        fastaChannel

    main:
        def kmers = [ 17, 23, 31 ]
        kmerChannel = channel.fromList(kmers)

        processingChannel = fastaChannel
            .filter
            {
                genomeInfo, fastaFile ->
                def salmonDir = "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}"
                def requiredFiles = kmers.collect { k -> file("${salmonDir}/k${k}/pos.bin") }
                requiredFiles << file("${salmonDir}/tx2gene.tsv")
                return requiredFiles.any { !it.exists() }
            }

        fetchTranscripts(processingChannel) | installTranscripts | indexTranscripts

        createDecoys(installTranscripts.out)

        combineChannel = installTranscripts.out.map
        {
            genomeInfo, genomeFile, transcriptsFile ->
            tuple genomeInfo, [ genomeFile, transcriptsFile ]
        }

        combineGenomeAndTranscripts(combineChannel)

        fastaById = combineGenomeAndTranscripts.out.map { genomeInfo, fastaFile -> tuple genomeInfo.base, genomeInfo, fastaFile }
        decoysById = createDecoys.out.map { genomeInfo, decoysFile -> tuple genomeInfo.base, decoysFile }

        transcriptAndDecoysChannel = fastaById.combine(decoysById, by: 0).map { id, genomeInfo, fastaFile, decoysFile -> tuple genomeInfo, fastaFile, decoysFile }

        indexingChannel = transcriptAndDecoysChannel
            .combine(kmerChannel)
            .filter
            {
                genomeInfo, fastaFile, decoysFile, kmer ->
                def salmonDir = "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}"
                return !file("${salmonDir}/k${kmer}/pos.bin").exists()
            }

        salmonIndex(indexingChannel)

        transcriptToGeneChannel = installTranscripts.out
            .filter
            {
                genomeInfo, transcriptsFile, indexFile ->
                def salmonDir = "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}"
                return !file("${salmonDir}/tx2gene.tsv").exists()
            }

        transcriptToGene(transcriptToGeneChannel)
}