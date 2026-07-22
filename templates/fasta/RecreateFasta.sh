#!/bin/bash

# Processes a downloaded FASTA file or TAR of FASTA files and rebuilds them
# into a single FASTA file, optionally with some of the chromosomes/contigs
# ordered as given in the assembly's genome info file.
#
# Any contigs in the reference not present in the chromosome order argument,
# or if that argument is not given, will be ordered alpha-numerically
# (i.e. 2 comes before 10).


export TMPDIR=temp
mkdir -p "$TMPDIR"

function clean_up
{
    rm -rf "$TMPDIR"
    exit $1
}

trap clean_up SIGHUP SIGINT SIGTERM

java -Djava.io.tmpdir="$TMPDIR" \
!{javaMem} \
-cp !{params.REFBUILDER} \
org.cruk.pipelines.referencegenomes.RecreateFasta \
-i !{fastaFile} \
-o !{correctedFile} \
-t "$TMPDIR" \
-a "!{genomeInfo['version']}" \
-c "!{genomeInfo['order']}"

clean_up $?
