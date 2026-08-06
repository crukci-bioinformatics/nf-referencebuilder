nextflow.enable.types = true

include { assemblyPath } from '../functions'

process starIndexWithGTF
{
    label 'STAR'

    publishDir { "${assemblyPath(genomeInfo)}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, fastaFile: Path, gtfFile: Path)

    output:
        record(genomeInfo: genomeInfo, indexDir: file(indexDir))

    shell:
        indexDir = "star-${params.STAR_VERSION}"
        indexLength = genomeInfo.getOrDefault('star.SAindexLength', 14)

        template 'star/starIndexWithGTF.sh'
}

process starIndexNoGTF
{
    label 'STAR'

    publishDir { "${assemblyPath(genomeInfo)}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, fastaFile: Path, gtfFile: Path?)

    output:
        record(genomeInfo: genomeInfo, indexDir: file(indexDir))

    shell:
        indexDir = "star-${params.STAR_VERSION}"
        indexLength = genomeInfo.getOrDefault('star.SAindexLength', 14)

        template 'star/starIndexNoGTF.sh'
}

def processingCondition(genomeInfo: Properties)
{
    def starDir = "${assemblyPath(genomeInfo)}/star-${params.STAR_VERSION}"
    def requiredFiles = [ file("${starDir}/SA"), file("${starDir}/SAindex"), file("${starDir}/Genome") ]
    return requiredFiles.any { f -> !f.exists() }
}

workflow starWF
{
    take:
        fastaChannel: Channel<Record>
        gtfChannel: Channel<Record>

    main:
        // Combine the channels. Use the genome info 'base' as the key.
        // fastaChannel and gtfChannel now carry records; extract fields for joining.
        info2Channel = fastaChannel.map { r -> record(id: r.genomeInfo.base, genomeInfo: r.genomeInfo) }
        fasta2Channel = fastaChannel.map { r -> record(id: r.genomeInfo.base, fastaFile: r.fastaFile) }
        gtf2Channel = gtfChannel.map { r -> record(id: r.genomeInfo.base, gtfFile: r.gtfFile) }

        combinedChannel = info2Channel
            .join(fasta2Channel, by: 'id')
            .join(gtf2Channel, by: 'id', remainder: true)
            .map { r ->
                record(genomeInfo: r.genomeInfo, fastaFile: r.fastaFile, gtfFile: r.gtfFile)
            }

        withGTFChannel = combinedChannel.filter { r ->
            r.gtfFile != null && processingCondition(r.genomeInfo)
        }

        withoutGTFChannel = combinedChannel.filter { r ->
            r.gtfFile == null && processingCondition(r.genomeInfo)
        }

        starIndexWithGTF(withGTFChannel)
        starIndexNoGTF(withoutGTFChannel)
}
