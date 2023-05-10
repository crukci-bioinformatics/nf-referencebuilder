/*
 * Miscellaneous helper functions used all over the pipeline.
 */

@Grab('org.apache.commons:commons-lang3:3.12.0')

import static org.apache.commons.lang3.StringUtils.isNotEmpty

/*
 * Read the properties from a properties file (i.e. the genome info file).
 */
def readGenomeInfo(propsFile)
{
    def genomeInfo = new Properties()
    propsFile.withReader { genomeInfo.load(it) }

    // Add some derived information for convenience.

    genomeInfo['species'] = genomeInfo['name.scientific'].toLowerCase().replace(' ', '_')
    genomeInfo['base'] = genomeInfo['abbreviation'] + '.' + genomeInfo['version']

    def transcriptUrl = genomeInfo['url.transcripts.fasta']
    genomeInfo['gencode'] = isNotEmpty(transcriptUrl) && transcriptUrl.contains("ftp.ebi.ac.uk/pub/databases/gencode");

    return genomeInfo
}

def speciesPath(genomeInfo)
{
    return "${params.referenceTop}/${genomeInfo.species}"
}

def assemblyPath(genomeInfo)
{
    return "${speciesPath(genomeInfo)}/${genomeInfo.version}"
}

/*
 * Get the size of a collection of things. It might be that the thing
 * passed in isn't a collection or map, in which case the size is 1.
 *
 * See https://github.com/nextflow-io/nextflow/issues/2425
 */
def sizeOf(thing)
{
    return (thing instanceof Collection || thing instanceof Map) ? thing.size() : 1
}

/**
 * Give a number for the Java heap size based on the task memory, allowing for
 * some overhead for the JVM itself from the total allowed.
 */
def javaMemMB(task)
{
    return task.memory.toMega() - 128
}
