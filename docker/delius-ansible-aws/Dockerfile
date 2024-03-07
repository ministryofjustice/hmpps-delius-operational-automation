# Stage 1 of multi-stage docker file - build the session-manager plugin
FROM golang:1.15.3-alpine as ssm-builder

ARG VERSION=1.2.279.0

RUN set -ex && apk add --no-cache make git gcc libc-dev curl bash zip && \
  curl -sLO https://github.com/aws/session-manager-plugin/archive/${VERSION}.tar.gz && \
  mkdir -p /go/src/github.com && \
  tar xzf ${VERSION}.tar.gz && \
  mv session-manager-plugin-${VERSION} /go/src/github.com/session-manager-plugin && \
  cd /go/src/github.com/session-manager-plugin && \
  make release

# Stage 2 of multi-stage docker file - build the final image that copies in the plugin built above
FROM python:3-alpine3.19

LABEL org.opencontainers.image.authors="HMPPS Probation Webops Team (probation-webops@digital.justice.gov.uk)" \
  org.opencontainers.image.vendor="Ministry of Justice" \
  org.opencontainers.image.title="delius-ansible-aws" \
  org.opencontainers.image.description="delius-ansible-aws" \
  org.opencontainers.image.source="https://github.com/ministryofjustice/hmpps-delius-operational-automation"

RUN apk update --no-cache \
    && apk add gcc musl-dev python3-dev libffi-dev openssl-dev cargo \
    && apk add python3-dev py-setuptools build-base libffi-dev openssl-dev openssh-client git make jq bash curl \
    && apk upgrade --no-cache

# Pip
RUN pip install -U pip;
COPY requirements.txt requirements.yml ./
RUN pip install --upgrade -r requirements.txt \
  && ansible-galaxy collection install -r requirements.yml \
  && ansible-galaxy role install -r requirements.yml

# Install session manager
COPY  --from=ssm-builder /go/src/github.com/session-manager-plugin/bin/linux_amd64_plugin/session-manager-plugin /usr/local/bin/

RUN adduser -D -u 1000 ansible

# USER ansible

ENTRYPOINT /bin/bash