ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ENV DEBIAN_FRONTEND=noninteractive

USER root

COPY configs/deps/packages.txt /tmp/packages.txt
RUN apt-get update && \
    grep -v '^\s*#' /tmp/packages.txt | grep -v '^\s*$' | \
    xargs apt-get install -y

# install zsh and oh-my-zsh
RUN apt-get install -y zsh wget && \
    wget -O /tmp/install.sh https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh && \
    chmod +x /tmp/install.sh && /tmp/install.sh && rm /tmp/install.sh

SHELL ["/bin/zsh", "-c"]

# install oh-my-zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# configure zsh
COPY docker/.zshrc /root/.zshrc

WORKDIR /workspace
CMD ["zsh"]
