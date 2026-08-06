nextflow.enable.types = true

include { javaMemoryOptions } from 'plugin/nf-crukci-support'
include { assemblyPath } from '../functions'

/*
    Pipeline to fetch and process FASTA reference sequence.

    Downloads the FASTA file, processes it, then creates a Samtools index,
    a Picard sequence dictionary, a sizes file and a canonical chromosomes file.

    Processing the FASTA file involves handling whether it is a TAR or a
    flat FASTA file, then possibly reordering its chromosomes. See the
    "recreateFasta" task descriptor for more information.
*/

process fetchFasta
{
    label 'fetcher'

    input:
        genomeInfo: Properties

    output:
        record(genomeInfo: genomeInfo, fastaFile: file(fastaFile))

    shell:
        fastaFile = "downloaded.fa.gz"

        """
        wget !{params.wgetOptions} -O !{fastaFile} "!{genomeInfo['url.fasta']}"
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

    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, fastaFile: Path)

    output:
        record(genomeInfo: genomeInfo, fastaFile: file(correctedFile))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        correctedFile = "${genomeInfo.base}.fa"

        template "fasta/RecreateFasta.sh"
}

process indexFasta
{
    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy', pattern: '*.fai'

    input:
        record(genomeInfo: Properties, fastaFile: Path)

    output:
        record(genomeInfo: genomeInfo, fastaFile: fastaFile, indexFile: file(indexFile))

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

    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy', pattern: '*.dict'

    input:
        record(genomeInfo: Properties, fastaFile: Path)

    output:
        record(genomeInfo: genomeInfo, fastaFile: fastaFile, sequenceDictionary: file(sequenceDictionary))

    shell:
        javaMem = javaMemoryOptions(task).jvmOpts
        sequenceDictionary = "${genomeInfo.base}.dict"

        template "picard/CreateSequenceDictionary.sh"
}

/*
    Create a sequence/chromosome sizes file (used by UCSC bedToBigBed utility).
 */
process sizesFile
{
    label 'tiny'

    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy', pattern: '*.sizes'

    input:
        record(genomeInfo: Properties, fastaFile: Path, sequenceDictionary: Path)

    output:
        record(genomeInfo: genomeInfo, fastaFile: fastaFile, sizesFile: file(sizesFile))

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

    publishDir { "${assemblyPath(genomeInfo)}/fasta" }, mode: 'copy', pattern: '*.canonical'

    input:
        record(genomeInfo: Properties, fastaFile: Path, sizesFile: Path)

    output:
        record(genomeInfo: genomeInfo, fastaFile: fastaFile, canonicalFile: file(canonicalFile))

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

/*
 * Work flow and supporting functions.
 */

def processingCondition(genomeInfo: Properties)
{
    def fastaBase = "${assemblyPath(genomeInfo)}/fasta/${genomeInfo.base}"
    def requiredFiles = [
        file("${fastaBase}.fa"),
        file("${fastaBase}.fa.fai"),
        file("${fastaBase}.dict"),
        file("${fastaBase}.sizes"),
        file("${fastaBase}.canonical")
    ]
    return requiredFiles.any { f -> !f.exists() }
}

workflow fastaWF
{
    take:
        genomeInfoChannel: Channel<Properties>

    main:
        processingChoice = genomeInfoChannel.branch \
        {
            genomeInfo ->
            doIt: processingCondition(genomeInfo)
            done: true
        }

        sourceFasta = fetchFasta(processingChoice.doIt)

        recreatedFasta = recreateFasta(sourceFasta)

        indexFasta(recreatedFasta)

        withSD = sequenceDictionary(recreatedFasta)
        withSizes = sizesFile(withSD)
        withCanonical = canonicalChromosomes(withSizes)

        fastaAlreadyPresent = processingChoice.done.map \
        {
            genomeInfo ->
            record(genomeInfo: genomeInfo, fastaFile: file("${assemblyPath(genomeInfo)}/fasta/${genomeInfo.base}.fa"))
        }

        fastaChannel = fastaAlreadyPresent.mix(recreatedFasta)

        canonicalAlreadyPresent = processingChoice.done.map \
        {
            genomeInfo ->
            def fastaBase = "${assemblyPath(genomeInfo)}/fasta/${genomeInfo.base}"
            record(genomeInfo: genomeInfo, fastaFile: file("${fastaBase}.fa"), canonicalFile: file("${fastaBase}.canonical"))
        }

        canonicalChannel = canonicalAlreadyPresent.mix(withCanonical)

    emit:
        fastaChannel: Channel<Record> = fastaChannel
        canonicalChannel: Channel<Record> = canonicalChannel
}
