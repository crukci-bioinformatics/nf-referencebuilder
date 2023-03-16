FROM    crukcibioinformatics/alignment:4.2.0

LABEL   maintainer="Richard Bowers<richard.bowers@cruk.cam.ac.uk>"

ARG INSTALL_DIR=/opt
ARG BUILD_DIR=/var/tmp/alignment_software_build

ARG JELLYFISH_V=2.3.0
ARG SALMON_V=1.9.0

ARG TAROPTS="--no-same-owner --no-same-permissions"

RUN dnf install -y python3 python3-urllib3

RUN mkdir -p ${INSTALL_DIR} ${BUILD_DIR}

# Salmon
RUN cd ${BUILD_DIR}; \
    wget -O salmon-${SALMON_V}.tar.gz https://github.com/COMBINE-lab/salmon/releases/download/v${SALMON_V}/salmon-${SALMON_V}_linux_x86_64.tar.gz && \
    tar ${TAROPTS} -xzf salmon-${SALMON_V}.tar.gz && \
    cp -rp salmon-${SALMON_V}_linux_x86_64/* /usr/local && \
    rm -f /usr/local/sample_data.tgz

# UCSC Tools
RUN cd /usr/local/bin; \
    wget http://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64/genePredToGtf && \
    wget http://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64/gtfToGenePred && \
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
