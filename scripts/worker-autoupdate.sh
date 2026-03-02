#!/bin/bash
# worker-autoupdate.sh — verifica se há nova imagem do worker no registry
# e atualiza automaticamente se necessário.
# Projetado para rodar via cronjob a cada 5 minutos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="docker.easydoor.ai/easydoor/ed-worker:latest"
COMPOSE_FILE="$INFRA_DIR/docker-compose.worker.yml"
LOG() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [worker-autoupdate] $*"; }

cd "$INFRA_DIR"

LOG "Verificando atualização..."
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

LOG "Nova versão detectada ($(docker inspect "$IMAGE" --format '{{.RepoTags}}')). Atualizando..."
docker compose -f "$COMPOSE_FILE" up -d --force-recreate
LOG "Worker atualizado e reiniciado com sucesso."
