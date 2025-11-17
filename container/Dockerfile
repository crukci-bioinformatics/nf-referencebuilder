FROM    crukcibioinformatics/alignment:4.3.4

LABEL   maintainer="Richard Bowers<richard.bowers@cruk.cam.ac.uk>"

ARG INSTALL_DIR=/opt
ARG BUILD_DIR=/var/tmp/alignment_software_build

ARG JELLYFISH_V=2.3.1

ARG TAROPTS="--no-same-owner --no-same-permissions"

RUN dnf install -y autoconf cmake diffutils python3 python3-urllib3

RUN mkdir -p ${INSTALL_DIR} ${BUILD_DIR}

# UCSC Tools
# Newer versions won't run on Rocky8: glibc is tool old.
RUN cd /usr/local/bin; \
    wget http://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64.v385/genePredToGtf && \
    wget http://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64.v385/gtfToGenePred && \
    chmod a+rx genePredToGtf gtfToGenePred

# Jellyfish
RUN cd ${BUILD_DIR}; \
    wget https://github.com/gmarcais/Jellyfish/releases/download/v${JELLYFISH_V}/jellyfish-${JELLYFISH_V}.tar.gz && \
    tar ${TAROPTS} -xzf jellyfish-${JELLYFISH_V}.tar.gz
RUN cd ${BUILD_DIR}/jellyfish-${JELLYFISH_V}; \
    export SAMTOOLS=/usr/local/bin/samtools && \
    ./configure --prefix=/usr/local && \
    make && \
    make install

# This pipeline's Java programs.
COPY nf-referencebuilder.jar /usr/local/lib

## Clean up
RUN cd / && rm -rf ${BUILD_DIR}
