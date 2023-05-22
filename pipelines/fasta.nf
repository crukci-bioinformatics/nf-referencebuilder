/*
    Pipeline to fetch and process FASTA reference sequence.

    Downloads the FASTA file, processes it, then creates a Samtools index,
    a Picard sequence dictionary, a sizes file and a canonical chromosomes file.

    Processing the FASTA file involves handling whether it is a TAR or a
    flat FASTA file, then possibly reordering its chromosomes. See the
    "recreateFasta" task descriptor for more information.
*/

include { assemblyPath } from '../functions/functions'
include { maxReadsInRam } from '../functions/picard'
include { javaMemMB } from '../modules/nextflow-support/functions'

process fetchFasta
{
    label 'fetcher'

    input:
        val(genomeInfo)

    output:
        tuple val(genomeInfo), path(fastaFile)

    shell:
        fastaFile = "downloaded.fa.gz"

        """
        wget -O !{fastaFile} "!{genomeInfo['url.fasta']}"
        """
}

/*
    Processes a downloaded FASTA file or TAR of FASTA files and rebuilds them
    into a single FASTA file, optionally with some of the chromosomes/contigs
    ordered as given in the assembly's genome info file.

    Any contigs in the reference not present in the chromosome order argument,
    or if that argument is not given, will be ordered alpha-numerically
    (i.e. 2 comes before 10).
 */
process recreateFasta
{
    label 'assembler'

    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy'

    input:
        tuple val(genomeInfo), path(fastaFile)

    output:
        tuple val(genomeInfo), path(correctedFile)

    shell:
        javaMem = javaMemMB(task)
        correctedFile = "${genomeInfo.base}.fa"

        template "fasta/RecreateFasta.sh"
}

process indexFasta
{
    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy', pattern: '*.fai'

    input:
        tuple val(genomeInfo), path(fastaFile)

    output:
        tuple val(genomeInfo), path(fastaFile), path(indexFile)

    shell:
        indexFile = fastaFile.name + ".fai"

        """
        samtools faidx !{fastaFile}
        """
}


/*
 * Run Picard's 'CreateSequenceDictionary'.
 */
process sequenceDictionary
{
    label 'picard'

    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy', pattern: '*.dict'

    input:
        tuple val(genomeInfo), path(fastaFile)

    output:
        tuple val(genomeInfo), path(fastaFile), path(sequenceDictionary)

    shell:
        javaMem = javaMemMB(task)
        sequenceDictionary = "${genomeInfo.base}.dict"

        template "picard/CreateSequenceDictionary.sh"
}

/*
    Create a sequence/chromosome sizes file (used by UCSC bedToBigBed utility).
 */
process sizesFile
{
    label 'tiny'

    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy', pattern: '*.sizes'

    input:
        tuple val(genomeInfo), path(fastaFile), path(sequenceDictionary)

    output:
        tuple val(genomeInfo), path(fastaFile), path(sizesFile)

    shell:
        sizesFile = "${genomeInfo.base}.sizes"

        """
            set -euo pipefail
            grep "^@SQ" !{sequenceDictionary} | \
                cut -f2,3 | \
                sed 's/^SN://;s/\tLN:/\t/' \
                > !{sizesFile}
        """
}

/*
    Create 'canonical' chromosomes file, that is, the normal chromosomes, not
    including, for example, "alt" or "unplaced" chromosomes.  The simple rule
    of removing chromosomes/contigs with an underscore or period works fine for
    most of the species currently in use, but produces silly results for others.
    Unfortunately, short of manual curation, there doesn't appear to be a simple
    rule that works for all.  Possibly we could provide a regular expression
    in the genome metadata file if that seems useful.
 */
process canonicalChromosomes
{
    label 'tiny'

    publishDir "${assemblyPath(genomeInfo)}/fasta", mode: 'copy', pattern: '*.canonical'

    input:
        tuple val(genomeInfo), path(fastaFile), path(sizesFile)

    output:
        tuple val(genomeInfo), path(fastaFile), path(canonicalFile)

    shell:
        canonicalFile = "${genomeInfo.base}.canonical"

        """
            set -euo pipefail
            sed -n -e '/[_.]/ !p' \
                < !{sizesFile} \
                | cut -f 1 \
                > !{canonicalFile}
        """
}

workflow fastaWF
{
    take:
        genomeInfoChannel

    main:

        def processingCondition =
        {
            genomeInfo ->
            def fastaBase = "${assemblyPath(genomeInfo)}/fasta/${genomeInfo.base}"
            def requiredFiles = [
                file("${fastaBase}.fa"),
                file("${fastaBase}.fa.fai"),
                file("${fastaBase}.dict"),
                file("${fastaBase}.sizes"),
                file("${fastaBase}.canonical")
            ]
            return requiredFiles.any { !it.exists() }
        }

        processingChoice = genomeInfoChannel.branch
        {
            doIt: processingCondition(it)
            done: true
        }

        fetchFasta(processingChoice.doIt) | recreateFasta

        indexFasta(recreateFasta.out)

        sequenceDictionary(recreateFasta.out) | sizesFile | canonicalChromosomes

        fastaPresentChannel = processingChoice.done.map
        {
            genomeInfo ->
            tuple genomeInfo, file("${assemblyPath(genomeInfo)}/fasta/${genomeInfo.base}.fa")
        }

        fastaChannel = fastaPresentChannel.mix(recreateFasta.out)

        canonicalPresentChannel = processingChoice.done.map
        {
            genomeInfo ->
            def fastaBase = "${assemblyPath(genomeInfo)}/fasta/${genomeInfo.base}"
            tuple genomeInfo, file("${fastaBase}.fa"), file("${fastaBase}.canonical")
        }

        canonicalChannel = canonicalPresentChannel.mix(canonicalChromosomes.out)

    emit:
        fastaChannel
        canonicalChannel
}
