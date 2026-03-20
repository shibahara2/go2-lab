ARG BASE_IMAGE
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

USER root

COPY configs/deps/packages.txt /tmp/packages.txt
RUN apt-get update && \
    grep -v '^\s*#' /tmp/packages.txt | grep -v '^\s*$' | \
    xargs apt-get install -y

# ホストと同じユーザーを動的に作成
ARG USERNAME
ARG USER_UID
ARG USER_GID
RUN groupadd --gid $USER_GID $USERNAME || true && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -o && \
    usermod -aG video $USERNAME

WORKDIR /workspace
RUN echo 'set -o vi' >> /home/${USERNAME}/.bashrc
USER ${USERNAME}
CMD ["bash"]
