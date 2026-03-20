ARG BASE_IMAGE
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

USER root

COPY configs/deps/packages.txt /tmp/packages.txt
RUN apt-get update && \
    grep -v '^\s*#' /tmp/packages.txt | grep -v '^\s*$' | \
    xargs apt-get install -y

WORKDIR /workspace
RUN echo 'set -o vi' >> /root/.bashrc
CMD ["bash"]
