FROM python:3.12-slim-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir ansible-core==2.21.4 ansible-lint==26.9.0 docker \
 && ansible-galaxy collection install community.docker -p /usr/share/ansible/collections

# Pipeline runs this as UID 1000; Ansible needs a writable home for its temp dir.
ENV HOME=/tmp
