import sys
import requests

# this file isn't actually used in the pipeline, because it requires
# the "requests" package to be installed, which it isn't by default.
# But I'm leaving it in the repository because it's a lot easier to
# read and understand than the horrific wget command that's used in
# prepare_genome.sh

def main(martname):

    urlTemplate = \
        '''http://www.ensembl.org/biomart/martservice?query=''' \
        '''<?xml version="1.0" encoding="UTF-8"?>''' \
        '''<!DOCTYPE Query>''' \
        '''<Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="1" count="" datasetConfigVersion="0.6">''' \
        '''<Dataset name="%s_gene_ensembl" interface="default">''' \
        '''<Attribute name="ensembl_gene_id"/>''' \
        '''<Attribute name="external_gene_name"/>''' \
        '''<Attribute name="description"/>''' \
        '''</Dataset>''' \
        '''</Query>'''

    exampleURL = urlTemplate % (martname)
    req = requests.get(exampleURL, stream=True)
    for line in req.iter_lines():
        print(line)

if __name__ == '__main__':
    main(sys.argv[1])
