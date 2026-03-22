#!/usr/bin/env bash
# sync-prod-to-dev.sh — Copia o banco de produção inteiro para o dev local.
#
# Uso:
#   ./scripts/sync-prod-to-dev.sh
#
# Pré-requisitos:
#   - SSH configurado para mail.easydoor.ai
#   - Banco de dev rodando (make dev-up)
#   - Docker instalado localmente
#
# O que faz:
#   1. Avisa que o banco dev será destruído e pede confirmação
#   2. Roda pg_dump no servidor remoto via SSH pipe
#   3. Copia o dump para dentro do container dev e restaura com pg_restore
#
# Por que pg_dump/pg_restore rodam no servidor remoto / container (não local):
#   As ferramentas locais (pg_dump, pg_restore, psql) podem ter versão diferente
#   do PostgreSQL 18 em uso. pg_dump recusa dump cross-version e pg_restore
#   recusa restore com formato de versão superior. Usar o container dev (mesma
#   imagem do servidor) resolve isso sem instalar PG 18 localmente.
#
# Por que substituir o banco inteiro (em vez de sincronizar tabela por tabela):
#   A abordagem anterior tinha uma lista hardcoded de tabelas que ficava
#   desatualizada a cada migration novo. Substituir o banco completo elimina
#   essa manutenção: o dev fica idêntico à produção, independente de quantas
#   tabelas existam.

set -euo pipefail

# ─── Configuração ────────────────────────────────────────────────────────────

PROD_SSH_HOST="mail.easydoor.ai"
PROD_SSH_PORT=36000
PROD_DB_PORT=5434

DEV_CONTAINER="easydoor-db-dev"
DB_USER="easydoor"
DB_PASS="easydoor"
DB_NAME="easydoor"

DUMP_FILE="/tmp/easydoor-sync-$$.dump"
DUMP_FILE_IN_CONTAINER="/tmp/sync.dump"

# ─── Helpers ─────────────────────────────────────────────────────────────────

cleanup() {
    rm -f "$DUMP_FILE" 2>/dev/null || true
    docker exec "$DEV_CONTAINER" rm -f "$DUMP_FILE_IN_CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

dev_psql() {
    docker exec -e PGPASSWORD="$DB_PASS" "$DEV_CONTAINER" psql -U "$DB_USER" "$@" 2>&1 \
        | grep -v "^WARNING:.*No existing cluster"
}

# ─── AVISO ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ATENÇÃO — OPERAÇÃO DESTRUTIVA                               ║"
echo "║                                                              ║"
echo "║  O banco de dev LOCAL será DESTRUÍDO e substituído           ║"
echo "║  por uma cópia completa da PRODUÇÃO.                         ║"
echo "║                                                              ║"
echo "║  Dados locais não commitados serão perdidos.                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
read -r -p "Continuar? [s/N] " confirm
if [[ "${confirm,,}" != "s" ]]; then
    echo "Cancelado."
    exit 0
fi

# ─── Validação ───────────────────────────────────────────────────────────────

if ! docker exec -e PGPASSWORD="$DB_PASS" "$DEV_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" >/dev/null 2>&1; then
    echo "ERRO: Container ${DEV_CONTAINER} não está rodando."
    echo "      Execute: make dev-up"
    exit 1
fi

# ─── Dump da produção via SSH ────────────────────────────────────────────────
# LC_ALL=C evita warnings de perl/locale causados pelas variáveis LC_* do
# cliente sendo encaminhadas pelo SSH.

log "Exportando banco de produção via SSH (pg_dump remoto)..."
ssh -p "$PROD_SSH_PORT" "$PROD_SSH_HOST" \
    "LC_ALL=C PGPASSWORD=${DB_PASS} pg_dump -h localhost -p ${PROD_DB_PORT} -U ${DB_USER} -d ${DB_NAME} --no-owner --no-acl -Fc" \
    > "$DUMP_FILE"

log "Dump concluído ($(du -sh "$DUMP_FILE" | cut -f1))"

# ─── Restauração no dev ───────────────────────────────────────────────────────

log "Copiando dump para o container..."
docker cp "$DUMP_FILE" "${DEV_CONTAINER}:${DUMP_FILE_IN_CONTAINER}"

log "Destruindo banco dev..."
# Encerra conexões ativas antes de dropar (ex: psql aberto, backend rodando)
dev_psql -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid()" \
    >/dev/null
dev_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME}"
dev_psql -d postgres -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}"

log "Restaurando no dev..."
docker exec -e PGPASSWORD="$DB_PASS" "$DEV_CONTAINER" pg_restore \
    -U "$DB_USER" -d "$DB_NAME" \
    --no-owner --no-acl \
    "$DUMP_FILE_IN_CONTAINER"

# ─── Resumo ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo " Sync produção → dev concluído"
echo "═══════════════════════════════════════════"
dev_psql -d "$DB_NAME" -t -c "
    SELECT '  ' || table_name || ': ' || (xpath('/row/cnt/text()',
        query_to_xml('SELECT count(*) AS cnt FROM ' || quote_ident(table_name), true, true, '')))[1]::text || ' registros'
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER BY table_name
"
echo "═══════════════════════════════════════════"
