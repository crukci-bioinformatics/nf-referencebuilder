#!/bin/bash

java -Djava.io.tmpdir="$TMPDIR" \
!{javaMem} \
-cp !{params.REFBUILDER} \
org.cruk.pipelines.referencegenomes.ConcatenateFiles \
-o "!{outputFile}" \
"!{inputFiles.join('" "')}"
