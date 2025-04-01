FROM python:3-slim

LABEL org.opencontainers.image.authors="HMPPS Probation Webops Team (probation-webops@digital.justice.gov.uk)" \
  org.opencontainers.image.vendor="Ministry of Justice" \
  org.opencontainers.image.title="delius-ansible-aws" \
  org.opencontainers.image.description="delius-ansible-aws" \
  org.opencontainers.image.source="https://github.com/ministryofjustice/hmpps-delius-operational-automation"

RUN apt update && apt install -y curl git bash jq && apt clean

RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq &&\
    chmod +x /usr/bin/yq

RUN if curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb" && dpkg -i session-manager-plugin.deb; then \
  echo "Session manager plugin installed"; \
  else \
  rm -f session-manager-plugin.deb && \
  curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb" -o "session-manager-plugin.deb" && \
  dpkg -i session-manager-plugin.deb; \
  fi

ENV TZ=Europe/London
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# Pip
COPY requirements.txt requirements.yml ./
RUN pip install -U pip && pip install --upgrade -r requirements.txt \
  && ansible-galaxy collection install -r requirements.yml \
  && ansible-galaxy role install -r requirements.yml

RUN useradd -m -u 1001 -s /bin/bash ansible && passwd -d ansible

USER ansible
