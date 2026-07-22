/*
 * Miscellaneous helper functions used all over the pipeline.
 */

/*
 * Read the properties from a properties file (i.e. the genome info file).
 */
def readGenomeInfo(propsFile: Path)
{
    def genomeInfo = new Properties()
    propsFile.withReader { reader -> genomeInfo.load(reader) }

    // Add some derived information for convenience.

    genomeInfo['species'] = genomeInfo['name.scientific'].toLowerCase().replace(' ', '_')
    genomeInfo['base'] = genomeInfo['abbreviation'] + '.' + genomeInfo['version']

    def transcriptUrl = genomeInfo['url.transcripts.fasta']
    genomeInfo['gencode'] = org.apache.commons.lang3.StringUtils.isNotEmpty(transcriptUrl) &&
                            transcriptUrl.contains("ftp.ebi.ac.uk/pub/databases/gencode");

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
