#!/bin/bash
set -e

# debug entrypoint
if [ ${SKIP_DEBUG:-0} -eq 0 ]; then
    set -x
fi

# copy ssh keys for root
if [ -d /.ssh/ ]; then
    rsync -r --delete \
        /.ssh/ \
        /root/.ssh/ \
        ;
fi

# override apt sources
if [ -n "${APT_SOURCES}" ]; then
    echo "${APT_SOURCES}" > /etc/apt/sources.list.d/aptly.list
fi

# update packages list
if [ ${SKIP_UPDATE:-0} -eq 0 ]; then
    apt-get update
fi

# prepare missing dirs
mkdir -p \
    /build/tmp-dest \
    /build/tmp-build \
    /deb \
    /sources \
    ;

# fix /bin, /lib permissions
chmod 0755 \
    /bin \
    /lib \
    ;

# go to package recipe dir
if [ -n "${PACKAGE_DIR}" ]; then
    cd "${PACKAGE_DIR}"
fi

# run passed command
exec "$@"
