FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV EPICS_ROOT=/opt/epics

RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    make \
    python3 \
    git \
    gzip \
    tar

COPY . /opt/install
WORKDIR /opt/install

RUN chmod +x install.sh
RUN ./install.sh