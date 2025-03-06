#!/bin/sh

DIR=$(dirname $0)
source $DIR/settings.sh

# Can't do this in the Dockerfile.
cp $DIR/../java/target/nf-referencebuilder-*.jar $DIR/nf-referencebuilder.jar

sudo docker build --tag "$REPO" --file Dockerfile .

