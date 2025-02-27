#!/bin/sh

TAG="2.1.1"
REPO="crukcibioinformatics/referencebuilder:$TAG"
IMAGE="referencebuilder-$TAG.sif"

sudo rm -f "$IMAGE"

sudo singularity build "$IMAGE" docker-daemon://${REPO}
sudo chown $USER "$IMAGE"
chmod a-x "$IMAGE"

