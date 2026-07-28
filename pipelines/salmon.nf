nextflow.enable.types = true

include { javaMemoryOptions } from 'plugin/nf-crukci-support'
include { assemblyPath } from '../functions'

/*
 * Building salmon indexes isn't a simple case of running a tool on a
 * reference file as most of the others are.
 * See https://redmine-bioinformatics.cruk.cam.ac.uk/issues/7243
 */

process fetchTranscripts
{
    label 'fetcher'

    input:
        record(genomeInfo: Properties, genomeFile: Path)

    output:
        record(genomeInfo: genomeInfo, genomeFile: genomeFile, transcriptsFile: file(outputFile))

    shell:
        outputFile = "transcripts"

        """
        wget !{params.wgetOptions} -O "!{outputFile}" "!{genomeInfo['url.transcripts.fasta']}"
        """
}

process installTranscripts
{
    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, genomeFile: Path, transcriptsFile: Path)

    output:
        record(genomeInfo: genomeInfo, genomeFile: genomeFile, transcriptsFile: file(outputFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        inputFiles = [ transcriptsFile ]
        outputFile = "${genomeInfo.base}.transcripts.fa"
        template "ConcatenateFiles.sh"
}

process indexTranscripts
{
    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy', pattern: '*.fai'

    input:
        record(genomeInfo: Properties, genomeFile: Path, transcriptsFile: Path)

    output:
        record(genomeInfo: genomeInfo, transcriptsFile: transcriptsFile, indexFile: file(indexFile))

    shell:
        indexFile = transcriptsFile.name + ".fai"

        """
        samtools faidx "!{transcriptsFile}"
        """
}

process createDecoys
{
    memory 64.M

    input:
        record(genomeInfo: Properties, genomeFile: Path, transcriptsFile: Path?)

    output:
        record(genomeInfo: genomeInfo, decoysFile: file(decoysFile))

    shell:
        decoysFile = "${genomeInfo.base}.decoys.txt"

        """
        cat "!{genomeFile}" | \
        egrep '^>' | \
        cut -d " " -f 1 | \
        sed 's/>//' > \
        "${decoysFile}"
        """
}

process combineGenomeAndTranscripts
{
    input:
        record(genomeInfo: Properties, inputFiles: Collection<Path>)

    output:
        record(genomeInfo: genomeInfo, outputFile: file(outputFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        outputFile = "${genomeInfo.base}.all.fa"
        template "ConcatenateFiles.sh"
}

process salmonIndex
{
    label 'builder'

    publishDir { "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, fastaFile: Path, decoysFile: Path, kmer: Integer)

    output:
        record(genomeInfo: genomeInfo, indexDir: file(indexDir))

    shell:
        indexDir = "k${kmer}"

        """
        salmon index \
            --transcripts "!{fastaFile}" \
            --decoys "!{decoysFile}" \
            --kmerLen !{kmer} \
            !{genomeInfo.gencode ? '--gencode' : ''} \
            --threads !{task.cpus} \
            --index "!{indexDir}" \
            --tmpdir temp
        """
}

process transcriptToGene
{
    label 'tiny'
    executor 'local'

    publishDir { "${assemblyPath(genomeInfo)}/salmon-${params.SALMON_VERSION}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, genomeFile: Path, transcriptsFile: Path)

    output:
        record(genomeInfo: genomeInfo, mappingFile: file(mappingFile))

    shell:
        mappingFile = "tx2gene.tsv"

        """
        echo -e "TxID\tGeneID" > "!{mappingFile}"
        zcat "!{transcriptsFile}" | \
            egrep '^>' | \
            cut -d '|' -f 1,2 | \
            sed -e 's/>//' -e 's/\\.[0-9]*\$//' | \
            tr '|' '\t' \
            >> "!{mappingFile}"
        """
}

workflow salmonWF
{
    take:
        fastaChannel: Channel<Record>

    main:
        def kmers = [ 17, 23, 31 ]
        kmerChannel = channel.fromList(kmers)

        processingChannel = fastaChannel
            .map { r ->
                record(genomeInfo: r.genomeInfo, genomeFile: r.fastaFile)
            }
            .filter { r ->
                r.genomeInfo['url.transcripts.fasta'] != null
            }
            .filter { r ->
                def salmonDir = "${assemblyPath(r.genomeInfo)}/salmon-${params.SALMON_VERSION}"
                def requiredFiles = kmers.collect { k -> file("${salmonDir}/k${k}/pos.bin") }
                requiredFiles << file("${salmonDir}/tx2gene.tsv")
                return requiredFiles.any { f -> !f.exists() }
            }

        sourceTranscripts = fetchTranscripts(processingChannel)
        installedTranscripts = installTranscripts(sourceTranscripts)
        indexTranscripts(installedTranscripts)

        decoys = createDecoys(sourceTranscripts)

        combineChannel = installedTranscripts.map { r ->
            record(genomeInfo: r.genomeInfo, inputFiles: [ r.transcriptsFile, r.genomeFile ])
        }

        combined = combineGenomeAndTranscripts(combineChannel)

        fastaById = combined.map { r ->
            record(id: r.genomeInfo.base, fasta: record(genomeInfo: r.genomeInfo, fastaFile: r.outputFile))
        }

        decoysById = decoys.map { r ->
            record(id: r.genomeInfo.base, decoys: r.decoysFile)
        }

        indexingChannel = fastaById
            .join(decoysById, by: 'id')
            .combine(kmerChannel)
            .map { r, k ->
                record(genomeInfo: r.fasta.genomeInfo, fastaFile: r.fasta.fastaFile, decoysFile: r.decoys, kmer: k)
            }
            .filter { r ->
                def salmonDir = "${assemblyPath(r.genomeInfo)}/salmon-${params.SALMON_VERSION}"
                return !file("${salmonDir}/k${r.kmer}/pos.bin").exists()
            }

        salmonIndex(indexingChannel)

        transcriptToGeneChannel = sourceTranscripts
            .filter { r ->
                def salmonDir = "${assemblyPath(r.genomeInfo)}/salmon-${params.SALMON_VERSION}"
                return !file("${salmonDir}/tx2gene.tsv").exists()
            }

        transcriptToGene(transcriptToGeneChannel)
}
