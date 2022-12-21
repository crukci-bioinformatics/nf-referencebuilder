#!/bin/sh

TAG="2.0.0"
REPO="crukcibioinformatics/referencebuilder:$TAG"

sudo rm -f referencebuilder*.sif

sudo singularity build referencebuilder-$TAG.sif docker-daemon://${REPO}
sudo chown $USER referencebuilder-$TAG.sif
chmod a-x referencebuilder-$TAG.sif

