#!/bin/sh

TAG="2.1.0"
REPO="crukcibioinformatics/referencebuilder:$TAG"
SIF="referencebuilder-$TAG.sif"

sudo rm -f referencebuilder*.sif

sudo singularity build "$SIF" docker-daemon://${REPO}
sudo chown $USER "$SIF"
chmod a-x "$SIF"

