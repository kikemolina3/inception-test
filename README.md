# inception-test

One-stop setup script for the **Taska Use Case C** astronomy pipeline. Installs and configures MinIO, Minikube, Lithops, and Python — designed for astronomers on **macOS** or **Ubuntu** (auto-detected).

## Quick start

```bash
./install/inception.sh --gitlab-user <user> --gitlab-password <password>
```

The script auto-detects whether you're on macOS or Linux and runs the appropriate logic.

## Flags

| Flag | Required | Default | Description |
|---|---|---|---|
| `--gitlab-user` | Yes | — | GitLab username for cloning the pipeline repo |
| `--gitlab-password` | Yes | — | GitLab password for cloning the pipeline repo |
| `--minio-id` | No | `1` | MinIO instance for Lithops (`1` or `2`) |

## What it does

1. Clones the **pipeline** repository from GitLab
2. Starts two **MinIO** Docker instances (`minio1`, `minio2`)
3. Installs the **MinIO client** (`mc`) and creates buckets
4. Uploads datasets to MinIO
5. Installs and starts **Minikube** (Kubernetes-in-Docker)
6. Generates the **Lithops** config (`~/.lithops/config`)
7. Installs **Python 3.10**, creates a venv, and installs the project via `pip install -e`

## Prerequisites

- **macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) + [Homebrew](https://brew.sh)
- **Ubuntu 22.04**: Docker installed and running

## Testing

```bash
./inception.sh --gitlab-user <user> --gitlab-password <password>
```

## CI

GitHub Actions run the full inception.sh on both platforms using repository secrets (`GITLAB_USER`, `GITLAB_PASSWORD`):
- **macOS** (`.github/workflows/macos-test.yml`): `macos-15-intel` + Docker via Colima
- **Ubuntu** (`.github/workflows/ubuntu-test.yml`): `ubuntu-22.04` with native Docker
