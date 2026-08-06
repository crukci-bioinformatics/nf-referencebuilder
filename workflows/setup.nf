nextflow.enable.types = true

/*
    Need a .hg.conf file in the home directory to access UCSC databases.
    This file must be private to the user.

    See http://genomewiki.ucsc.edu/index.php/Genes_in_gtf_or_gff_format
*/
process createHgConf
{
    label 'tiny'
    tag 'home'

    publishDir { file(homeConfFile.parent.toString()) }, mode: 'copy'

    input:
        homeConfFile: Path

    output:
        hgConfFile: Path = file(confFileName)

    shell:
        confFileName = homeConfFile.name

        """
            echo "db.host=genome-mysql.cse.ucsc.edu" > !{confFileName}
            echo "db.user=genomep" >> !{confFileName}
            echo "db.password=password" >> !{confFileName}
            echo "central.db=hgcentral" >> !{confFileName}
            chmod 600 !{confFileName}
        """
}

workflow setupWF
{
    main:
        presentChoice = channel.fromPath("${System.getProperty('user.home')}/.hg.conf").branch \
        {
            confFile ->
            present: confFile.exists()
            needed: true
        }

        newlyCreated = createHgConf(presentChoice.needed)

        newOrNot = presentChoice.present.mix(newlyCreated)

    emit:
        hgConfChannel: Channel<Path> = newOrNot
}
