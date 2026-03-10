FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y -qq \
    curl git sudo ca-certificates gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CE (DinD)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
       https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update -qq \
    && apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace/

ENTRYPOINT ["/workspace/install/entrypoint.sh"]
