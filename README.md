# inception-test

One-stop setup script for the **Taska Use Case C** astronomy pipeline. Installs and configures MinIO, Minikube, Lithops, and Python — designed for astronomers on **macOS** (default) or Ubuntu.

## Quick start (macOS)

```bash
./install/inception.sh --gitlab-user <user> --gitlab-password <password>
```

## Quick start (Ubuntu)

```bash
./install/inception.sh --os ubuntu --gitlab-user <user> --gitlab-password <password>
```

## Flags

| Flag | Required | Default | Description |
|---|---|---|---|
| `--gitlab-user` | Yes* | — | GitLab username for datasets repo |
| `--gitlab-password` | Yes* | — | GitLab password for datasets repo |
| `--os` | No | `macos` | Target OS: `macos` or `ubuntu` |
| `--minio-id` | No | `1` | MinIO instance for Lithops (`1` or `2`) |
| `--skip-datasets` | No | — | Skip dataset clone/upload (for CI) |

\* Not required when `--skip-datasets` is used.

## What it does

1. Starts two **MinIO** Docker instances (`minio1`, `minio2`)
2. Installs the **MinIO client** (`mc`) and creates buckets
3. Clones datasets from GitLab and uploads to MinIO (unless `--skip-datasets`)
4. Installs and starts **Minikube** (Kubernetes-in-Docker)
5. Generates the **Lithops** config (`~/.lithops/config`)
6. Installs **Python 3.10**, creates a venv, and installs the project

## Prerequisites

- **macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) + [Homebrew](https://brew.sh)
- **Ubuntu 22.04**: Docker installed and running

## Testing in Docker (Ubuntu DinD)

```bash
docker build -t inception-test .
docker run --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  inception-test --gitlab-user <user> --gitlab-password <password>
```

## CI

The GitHub Action (`.github/workflows/macos-test.yml`) runs on `macos-latest` with `--skip-datasets` to validate the full setup without GitLab credentials.
