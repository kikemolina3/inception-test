#!/bin/bash

set -e

BUCKET="astronomics-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BLUE="\033[34m"
GREEN="\033[32m"
RESET="\033[0m"
RED="\033[31m"
YELLOW="\033[33m"

MINIO_URLS=(
    "http://minio1:9000"
    "http://minio2:9100"
)

# -------------------------------------------------------
# Auto-detect OS
# -------------------------------------------------------
case "$(uname -s)" in
    Darwin) TARGET_OS="macos" ;;
    Linux)  TARGET_OS="ubuntu" ;;
    *)
        echo -e "${RED}Unsupported OS: $(uname -s). Only macOS and Ubuntu are supported.${RESET}"
        exit 1
        ;;
esac

# -------------------------------------------------------
# Argument parsing
# -------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --gitlab-user) GITLAB_USER="$2"; shift ;;
        --gitlab-password) GITLAB_PASSWORD="$2"; shift ;;
        --minio-id) MINIO_ID="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$GITLAB_USER" || -z "$GITLAB_PASSWORD" ]]; then
    echo "Usage: $0 --gitlab-user <user> --gitlab-password <password> [--minio-id <1|2>]"
    echo ""
    echo "  --gitlab-user       GitLab username (required for cloning the pipeline repository)."
    echo "  --gitlab-password   GitLab password (required for cloning the pipeline repository)."
    echo "  --minio-id          (Optional) MinIO instance to use (1 or 2, default: 1)."
    exit 1
fi

PIPELINE_REPO="https://${GITLAB_USER}:${GITLAB_PASSWORD}@gitlab.bsc.es/extract/extract-use-cases/taska/use-case-c/pipeline.git"
PIPELINE_DIR="${HOME}/pipeline"

if [[ -n "$MINIO_ID" ]]; then
    MINIO_URL=${MINIO_URLS[$((MINIO_ID - 1))]}
else
    MINIO_URL=${MINIO_URLS[0]}
fi

# -------------------------------------------------------
# Platform-specific helpers
# -------------------------------------------------------

ensure_brew() {
    if ! command -v brew &> /dev/null; then
        echo -e "${RED}Homebrew is not installed. Install it from https://brew.sh${RESET}"
        exit 1
    fi
}

install_docker() {
    echo -e "${BLUE}Installing Docker...${RESET}"
    if [[ "$TARGET_OS" == "macos" ]]; then
        ensure_brew
        brew install --cask docker || true
        echo -e "${YELLOW}Docker Desktop installed. Please open it and start the engine before re-running this script.${RESET}"
        open -a Docker 2>/dev/null || true
        exit 0
    else
        sudo apt-get update -qq
        sudo apt-get install -y -qq ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
}

install_python() {
    echo -e "${BLUE}Installing Python 3.10...${RESET}"
    if [[ "$TARGET_OS" == "macos" ]]; then
        ensure_brew
        brew install python@3.10 || brew upgrade python@3.10 || true
        brew link python@3.10 --overwrite --force 2>/dev/null || true
    else
        sudo apt-get update -qq
        sudo apt-get install -y -qq software-properties-common
        sudo add-apt-repository -y ppa:deadsnakes/ppa
        sudo apt-get update -qq
        sudo apt-get install -y -qq python3.10 python3.10-venv
    fi
}

install_mc() {
    echo -e "${BLUE}Installing MinIO client (mc)...${RESET}"
    if [[ "$TARGET_OS" == "macos" ]]; then
        ensure_brew
        brew install minio/stable/mc 2>/dev/null || brew upgrade minio/stable/mc || true
    else
        sudo curl -sfL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
        sudo chmod +x /usr/local/bin/mc
    fi
}

install_minikube() {
    echo -e "${BLUE}Installing Minikube...${RESET}"
    if [[ "$TARGET_OS" == "macos" ]]; then
        ensure_brew
        brew install minikube 2>/dev/null || brew upgrade minikube || true
    else
        curl -sLO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm -f minikube-linux-amd64
    fi
}

get_minio_volume_path() {
    local instance=$1
    echo "${HOME}/minio-data/minio${instance}"
}

update_hosts_file() {
    if ! grep -q "minio1" /etc/hosts; then
        echo -e "${YELLOW}Adding minio1/minio2 to /etc/hosts (requires sudo)...${RESET}"
        echo "127.0.0.1 minio1" | sudo tee -a /etc/hosts
        echo "127.0.0.1 minio2" | sudo tee -a /etc/hosts
    fi
}

get_python_bin() {
    if [[ "$TARGET_OS" == "macos" ]]; then
        # Homebrew installs python@3.10 — find the correct binary
        local brew_prefix
        brew_prefix="$(brew --prefix python@3.10 2>/dev/null)"
        if [[ -x "${brew_prefix}/bin/python3.10" ]]; then
            echo "${brew_prefix}/bin/python3.10"
        elif command -v python3.10 &> /dev/null; then
            command -v python3.10
        else
            echo "python3"
        fi
    else
        echo "python3.10"
    fi
}

# -------------------------------------------------------
# Banner
# -------------------------------------------------------
echo -e "${BLUE}--------------------------------------------------------------------${RESET}"
echo -e "${BLUE}Taska Use Case C — Local Environment Setup (${TARGET_OS})${RESET}"
echo -e "${BLUE}1. Creating 2 MinIO instances.${RESET}"
echo -e "${BLUE}2. Creating a Minikube Kubernetes-in-Docker cluster.${RESET}"
echo -e "${BLUE}3. Automatically configure the Lithops config file.${RESET}"
echo -e "${BLUE}4. Uploading data to the MinIO instances.${RESET}"
echo -e "${BLUE}--------------------------------------------------------------------${RESET}"

# -------------------------------------------------------
# Docker
# -------------------------------------------------------
if ! command -v docker &> /dev/null; then
    install_docker
fi

# -------------------------------------------------------
# MinIO instances
# -------------------------------------------------------
echo -e "${BLUE}Setting up MinIO instances...${RESET}"
docker stop minio1 minio2 2>/dev/null || true
docker rm minio1 minio2 2>/dev/null || true

MINIO1_VOL="$(get_minio_volume_path 1)"
MINIO2_VOL="$(get_minio_volume_path 2)"
mkdir -p "$MINIO1_VOL" "$MINIO2_VOL"

docker run -d \
  --name minio1 \
  -p 9000:9000 \
  -p 9001:9001 \
  -v "${MINIO1_VOL}:/data" \
  minio/minio server /data --console-address ":9001"

docker run -d \
  --name minio2 \
  -p 9100:9100 \
  -p 9101:9101 \
  -v "${MINIO2_VOL}:/data" \
  minio/minio server /data --address ":9100" --console-address ":9101"

echo -e "${BLUE}Waiting for MinIO to be ready...${RESET}"
until curl -s http://127.0.0.1:9000/minio/health/live > /dev/null; do
    sleep 2
done
until curl -s http://127.0.0.1:9100/minio/health/live > /dev/null; do
    sleep 2
done
echo -e "${GREEN}MinIO is ready.${RESET}"

# -------------------------------------------------------
# Install mc
# -------------------------------------------------------
if ! command -v mc &> /dev/null; then
    install_mc
fi

mc alias set minio1 http://127.0.0.1:9000 minioadmin minioadmin > /dev/null
mc alias set minio2 http://127.0.0.1:9100 minioadmin minioadmin > /dev/null
if ! mc ls minio1/${BUCKET} &> /dev/null; then
    mc mb minio1/${BUCKET}
fi
if ! mc ls minio2/${BUCKET} &> /dev/null; then
    mc mb minio2/${BUCKET}
fi

# -------------------------------------------------------
# Clone pipeline repo
# -------------------------------------------------------
echo -e "${BLUE}Cloning pipeline repository...${RESET}"
if [[ -d "${PIPELINE_DIR}/.git" ]]; then
    echo -e "${YELLOW}Pipeline repo already exists at ${PIPELINE_DIR}, pulling latest...${RESET}"
    git -C "${PIPELINE_DIR}" pull --ff-only || true
else
    rm -rf "${PIPELINE_DIR}"
    git clone "${PIPELINE_REPO}" "${PIPELINE_DIR}"
fi

# -------------------------------------------------------
# Dataset upload
# -------------------------------------------------------
echo -e "${BLUE}Pushing datasets to MinIO instances...${RESET}"
mc cp -r "${PIPELINE_DIR}/datasets/" minio1/${BUCKET}/ > /dev/null
mc cp -r "${PIPELINE_DIR}/datasets/" minio2/${BUCKET}/ > /dev/null

# -------------------------------------------------------
# Minikube
# -------------------------------------------------------
echo -e "${BLUE}Setting up Minikube cluster...${RESET}"
if ! command -v minikube &> /dev/null; then
    install_minikube
fi
minikube start --driver=docker

update_hosts_file

docker network connect minikube minio1 2>/dev/null || true
docker network connect minikube minio2 2>/dev/null || true

# -------------------------------------------------------
# Lithops config
# -------------------------------------------------------
echo -e "${BLUE}Configuring Lithops...${RESET}"
mkdir -p ~/.lithops
if [ -e ~/.lithops/config ] && [ ! -e ~/.lithops/config.inception.bak ]; then
    mv ~/.lithops/config ~/.lithops/config.inception.bak
fi

cat > ~/.lithops/config << LITHOPS_EOF
lithops:
  backend: k8s
  storage: minio
  monitoring_interval: 1

minio:
   bucket_name: flexecutor-demo
   endpoint: ${MINIO_URL}
   access_key_id: minioadmin
   secret_access_key: minioadmin

k8s:
  docker_server: registry.gitlab.bsc.es
  runtime_timeout: 18000
  runtime: registry.gitlab.bsc.es/extract/extract-use-cases/taska/use-case-c/pipeline:310
  docker_user: ${GITLAB_USER}
  namespace: taska-c
  docker_password: ${GITLAB_PASSWORD}
LITHOPS_EOF

# -------------------------------------------------------
# Python 3.10 + venv
# -------------------------------------------------------
echo -e "${BLUE}Installing Python 3.10 & project dependencies...${RESET}"
PYTHON_BIN="$(get_python_bin)"

if ! command -v "$PYTHON_BIN" &> /dev/null; then
    install_python
    PYTHON_BIN="$(get_python_bin)"
fi

# -------------------------------------------------------
# uv (fast Python package manager)
# -------------------------------------------------------
if ! command -v uv &> /dev/null; then
    echo -e "${BLUE}Installing uv...${RESET}"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"
fi

cd "${PIPELINE_DIR}"
uv sync --python "$PYTHON_BIN"

echo -e "${GREEN}--------------------------------------------------------------------${RESET}"
echo -e "${GREEN}Setup completed successfully!${RESET}"
echo -e "${GREEN}Activate the virtualenv: source ${PIPELINE_DIR}/.venv/bin/activate${RESET}"
echo -e "${GREEN}Test the setup: lithops hello${RESET}"
echo -e "${GREEN}--------------------------------------------------------------------${RESET}"
