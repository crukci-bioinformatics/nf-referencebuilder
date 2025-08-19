#!/bin/sh

DIR=$(dirname $0)
source $DIR/settings.sh

sudo rm -f "$IMAGE"

sudo singularity build "$IMAGE" docker-daemon://${REPO}
sudo chown $USER "$IMAGE"
chmod a-x "$IMAGE"


if [ ! -e "$SALMON_IMAGE" ]
then
    sudo singularity build "$SALMON_IMAGE" docker-daemon://${SALMON_REPO}
    sudo chown $USER "$SALMON_IMAGE"
    chmod a-x "$SALMON_IMAGE"
fi
