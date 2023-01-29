ARG BUILDER_REPOSITORY_URL=registry.hub.docker.com
ARG BUILDER_IMAGE_NAME=library/golang
ARG BUILDER_IMAGE_TAG=1.19-alpine3.17
FROM ${BUILDER_REPOSITORY_URL}/${BUILDER_IMAGE_NAME}:${BUILDER_IMAGE_TAG} AS builder

ENV GOFLAGS="-mod=readonly"

RUN apk add --update --no-cache bash ca-certificates curl git gcc g++
RUN git clone https://github.com/drakkan/sftpgo.git /workspace

WORKDIR /workspace

ARG GOPROXY
ARG SFTPGO_VERSION=v2.4.3

RUN git checkout ${SFTPGO_VERSION}
RUN go mod download

# This ARG allows to disable some optional features and it might be useful if you build the image yourself.
# For example you can disable S3 and GCS support like this:
# --build-arg FEATURES=nos3,nogcs
ARG FEATURES

RUN set -xe && \
    export COMMIT_SHA=${COMMIT_SHA:-$(git describe --always --abbrev=8 --dirty)} && \
    go build $(if [ -n "${FEATURES}" ]; then echo "-tags ${FEATURES}"; fi) -trimpath -ldflags "-s -w -X github.com/drakkan/sftpgo/v2/internal/version.commit=${COMMIT_SHA} -X github.com/drakkan/sftpgo/v2/internal/version.date=`date -u +%FT%TZ`" -v -o sftpgo

ARG BASE_REPOSITORY_URL=harbor.stacktonic.com.au
ARG BASE_IMAGE_NAME=stacktonic/alpine
ARG BASE_IMAGE_TAG=latest
FROM ${BASE_REPOSITORY_URL}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

# set up nsswitch.conf for Go's "netgo" implementation
# https://github.com/gliderlabs/docker-alpine/issues/367#issuecomment-424546457
RUN test ! -e /etc/nsswitch.conf && echo 'hosts: files dns' > /etc/nsswitch.conf

RUN mkdir -p /etc/sftpgo /var/lib/sftpgo /usr/share/sftpgo /srv/sftpgo/data /srv/sftpgo/backups
COPY --from=builder /etc/ssh/moduli /etc/sftpgo/moduli
COPY --from=builder /workspace/templates /usr/share/sftpgo/templates
COPY --from=builder /workspace/static /usr/share/sftpgo/static
COPY --from=builder /workspace/openapi /usr/share/sftpgo/openapi
COPY --from=builder /workspace/sftpgo /usr/local/bin/

ENV SFTPGO_LOG_FILE_PATH=""

RUN chown -R app:app /etc/sftpgo /srv/sftpgo && \
    chown app:app /var/lib/sftpgo && \
    chmod 700 /srv/sftpgo/backups
ADD root /

CMD []

EXPOSE 80 443 22 20 21 50000-50100


ENTRYPOINT ["/init"]