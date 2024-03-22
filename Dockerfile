# Copyright (C) 2023-2024 Thien Tran, Wonderfall
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

ARG SYNAPSE_VERSION=1.103.0
ARG PYTHON_VERSION=3.11
ARG HARDENED_MALLOC_VERSION=11
ARG UID=991
ARG GID=991


### Build Hardened Malloc
FROM alpine:latest as build-malloc

ARG HARDENED_MALLOC_VERSION
ARG CONFIG_NATIVE=false
ARG VARIANT=default

RUN apk -U upgrade \
 && apk --no-cache add build-base git gnupg && cd /tmp \
 && wget -q https://github.com/thestinger.gpg && gpg --import thestinger.gpg \
 && git clone --depth 1 --branch ${HARDENED_MALLOC_VERSION} https://github.com/GrapheneOS/hardened_malloc \
 && cd hardened_malloc && git verify-tag $(git describe --tags) \
 && make CONFIG_NATIVE=${CONFIG_NATIVE} VARIANT=${VARIANT}


### Build Synapse
FROM python:${PYTHON_VERSION}-alpine as builder

ARG SYNAPSE_VERSION

RUN apk -U upgrade \
 && apk --no-cache add -t build-deps \
        build-base \
        libffi-dev \
        libjpeg-turbo-dev \
        libxslt-dev \
        linux-headers \
        openssl-dev \
        postgresql-dev \
        rustup \
        zlib-dev \
 && rustup-init -y && source $HOME/.cargo/env \
 && pip install --upgrade pip \
 && pip install --prefix="/install" --no-warn-script-location \
        matrix-synapse[all]==${SYNAPSE_VERSION}


### Build Production

FROM python:${PYTHON_VERSION}-alpine

LABEL maintainer="Thien Tran contact@tommytran.io"

ARG UID
ARG GID

RUN apk -U upgrade \
 && apk --no-cache add -t run-deps \
        libffi \
        libgcc \
        libjpeg-turbo \
        libstdc++ \
        libxslt \
        libpq \
        openssl \
        zlib \
        tzdata \
        xmlsec \
        git \
        curl \
        icu-libs \
 && adduser -g ${GID} -u ${UID} --disabled-password --gecos "" synapse \
 && rm -rf /var/cache/apk/*

RUN pip install --upgrade pip \
 && pip install -e "git+https://github.com/matrix-org/mjolnir.git#egg=mjolnir&subdirectory=synapse_antispam"

COPY --from=build-malloc /tmp/hardened_malloc/out/libhardened_malloc.so /usr/local/lib/
COPY --from=builder /install /usr/local
COPY --chown=synapse:synapse rootfs /

ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

USER synapse

VOLUME /data

EXPOSE 8008/tcp 8009/tcp 8448/tcp

ENTRYPOINT ["python3", "start.py"]

HEALTHCHECK --start-period=5s --interval=15s --timeout=5s \
    CMD curl -fSs http://localhost:8008/health || exit 1
