#!/bin/bash
# worker-autoupdate.sh — verifica se há nova versão do worker e atualiza.
# AMD64: compara digest da imagem no registry com a imagem rodando.
# ARM64: compara hash do ed-infra local com a versão rodando no container.
# Projetado para rodar via cronjob (a cada 1-5 minutos).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="docker.easydoor.ai/easydoor/ed-worker:latest"
COMPOSE_FILE="$INFRA_DIR/docker-compose.worker.yml"
LOG() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [worker-autoupdate] $*"; }

cd "$INFRA_DIR"

ARCH="$(uname -m)"

if [[ "$ARCH" == "aarch64" ]]; then
    # ── ARM64: sem imagem no registry — compara hash do ed-infra ──────────────
    LOG "ARM64: verificando via git..."
    git pull origin master --quiet

    CURRENT_HASH=$(git rev-parse --short HEAD)
    RUNNING_VERSION=$(docker inspect easydoor-worker \
        --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
        | grep '^WORKER_VERSION=' | cut -d= -f2 || echo "")

    if [[ -z "$RUNNING_VERSION" ]]; then
        LOG "Worker não está rodando. Iniciando..."
        make worker-up
        exit 0
    fi

    if [[ "$CURRENT_HASH" == "$RUNNING_VERSION" ]]; then
        LOG "Worker já está na versão mais recente ($CURRENT_HASH). Nada a fazer."
        exit 0
    fi

    LOG "Nova versão detectada ($RUNNING_VERSION → $CURRENT_HASH). Rebuilding..."
    make worker-up
    LOG "Worker atualizado com sucesso."

else
    # ── AMD64: compara digest da imagem no registry ───────────────────────────
    LOG "AMD64: verificando via registry..."
    docker pull "$IMAGE" --quiet > /dev/null

    RUNNING_ID=$(docker inspect easydoor-worker --format '{{.Image}}' 2>/dev/null || echo "")
    LATEST_ID=$(docker inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || echo "")

    if [[ -z "$RUNNING_ID" ]]; then
        LOG "Worker não está rodando. Iniciando..."
        docker compose -f "$COMPOSE_FILE" up -d
        LOG "Worker iniciado."
        exit 0
    fi

    if [[ "$RUNNING_ID" == "$LATEST_ID" ]]; then
        LOG "Worker já está na versão mais recente. Nada a fazer."
        exit 0
    fi

    LOG "Nova versão detectada. Atualizando..."
    docker compose -f "$COMPOSE_FILE" up -d --force-recreate
    LOG "Worker atualizado e reiniciado com sucesso."
fi
