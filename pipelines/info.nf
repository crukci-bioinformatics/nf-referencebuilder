nextflow.enable.types = true

include { readGenomeInfo; assemblyPath } from '../functions'

/*
 * Pipeline to put a copy of the genome info properties into the
 * assembly directory.
 */

process copyGenomeInfoFile
{
    label 'tiny'

    publishDir { "${assemblyPath(genomeInfo)}" }, mode: 'copy'

    input:
        record(genomeInfo: Properties, genomeInfoFile: Path)

    output:
        record(genomeInfo: genomeInfo, infoFile: file(infoFileName))

    shell:
        infoFileName = 'AssemblyInfo.properties'
        """
        cp "!{genomeInfoFile}" "!{infoFileName}"
        """
}

workflow genomeInfoWF
{
    take:
        genomeInfoFileChannel: Channel<Path>

    main:
        genomeInfoChannel = genomeInfoFileChannel
            .map { f ->
                record(genomeInfo: readGenomeInfo(f), genomeInfoFile: f)
            }
            .filter { r ->
                !file("${assemblyPath(r.genomeInfo)}/AssemblyInfo.properties").exists()
            }

        copyGenomeInfoFile(genomeInfoChannel)
}
