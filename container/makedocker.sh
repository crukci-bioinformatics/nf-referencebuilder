#!/bin/sh

DIR=$(dirname $0)

TAG="2.1.0"
REPO="crukcibioinformatics/referencebuilder:$TAG"

# Can't do this in the Dockerfile.
cp $DIR/../java/target/nf-referencebuilder-*.jar $DIR/nf-referencebuilder.jar

sudo docker build --tag "$REPO" --file Dockerfile .
if [ $? -eq 0 ]
then
    sudo docker push "$REPO"
fi
