#!/usr/bin/env bash
# sync-prod-to-dev.sh — Copia dados do banco de produção para o dev local.
#
# Uso:
#   ./scripts/sync-prod-to-dev.sh              # sincroniza todas as tabelas
#   ./scripts/sync-prod-to-dev.sh anuncios     # sincroniza só uma tabela
#
# Pré-requisitos:
#   - SSH configurado para mail.easydoor.ai (ssh config ou chave)
#   - Banco de dev rodando na porta 5433 (make dev-up)
#   - psql instalado localmente
#
# O que faz:
#   1. Abre SSH tunnel temporário para o banco de produção
#   2. Exporta tabelas via \COPY (CSV)
#   3. Importa no banco dev local (TRUNCATE + COPY)
#   4. Refresh da materialized view mv_anuncios_venda
#   5. Fecha o tunnel
#
# Tabelas sincronizadas (na ordem correta para respeitar dependências):
#   - premissas
#   - mat_ajustes
#   - anuncios
#   - geocodificacao_cache
#   - enderecos
#   - ceps_cadastrados

set -euo pipefail

# ─── Configuração ────────────────────────────────────────────────────────────

PROD_SSH_HOST="mail.easydoor.ai"
PROD_SSH_PORT=36000
PROD_DB_PORT=5434
TUNNEL_LOCAL_PORT=15432

DEV_DB_PORT=5433
DB_USER="easydoor"
DB_PASS="easydoor"
DB_NAME="easydoor"

PROD_DSN="postgresql://${DB_USER}:${DB_PASS}@localhost:${TUNNEL_LOCAL_PORT}/${DB_NAME}"
DEV_DSN="postgresql://${DB_USER}:${DB_PASS}@localhost:${DEV_DB_PORT}/${DB_NAME}"

DUMP_DIR="/tmp/easydoor-sync-$$"

# Tabelas a sincronizar (ordem importa para dependências)
ALL_TABLES=(premissas mat_ajustes anuncios geocodificacao_cache enderecos ceps_cadastrados)

# ─── Helpers ─────────────────────────────────────────────────────────────────

cleanup() {
    # Fechar tunnel
    if [[ -n "${TUNNEL_PID:-}" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
        kill "$TUNNEL_PID" 2>/dev/null || true
        echo "[OK] Tunnel SSH fechado"
    fi
    # Limpar CSVs
    rm -rf "$DUMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

psql_prod() { psql "$PROD_DSN" "$@" 2>&1 | grep -v "^Warning:.*No existing cluster"; }
psql_dev()  { psql "$DEV_DSN"  "$@" 2>&1 | grep -v "^Warning:.*No existing cluster"; }

# ─── Validações ──────────────────────────────────────────────────────────────

# Banco dev rodando?
if ! psql_dev -c "SELECT 1" >/dev/null 2>&1; then
    echo "ERRO: Banco dev não está rodando na porta ${DEV_DB_PORT}."
    echo "      Execute: cd ed-infra && make dev-up"
    exit 1
fi

# Determinar tabelas
if [[ $# -gt 0 ]]; then
    TABLES=("$@")
else
    TABLES=("${ALL_TABLES[@]}")
fi

# ─── SSH Tunnel ──────────────────────────────────────────────────────────────

log "Abrindo tunnel SSH para produção..."

# Fechar tunnel antigo na mesma porta, se existir
if lsof -ti :${TUNNEL_LOCAL_PORT} >/dev/null 2>&1; then
    kill "$(lsof -ti :${TUNNEL_LOCAL_PORT})" 2>/dev/null || true
    sleep 1
fi

ssh -p "$PROD_SSH_PORT" -L "${TUNNEL_LOCAL_PORT}:localhost:${PROD_DB_PORT}" \
    -N -f -o ExitOnForwardFailure=yes "$PROD_SSH_HOST"
TUNNEL_PID=$(lsof -ti :${TUNNEL_LOCAL_PORT} | head -1)

# Esperar tunnel ficar pronto
for i in $(seq 1 10); do
    if psql_prod -c "SELECT 1" >/dev/null 2>&1; then break; fi
    sleep 1
done

if ! psql_prod -c "SELECT 1" >/dev/null 2>&1; then
    echo "ERRO: Não foi possível conectar ao banco de produção via tunnel."
    exit 1
fi

log "Tunnel ativo (PID ${TUNNEL_PID})"

# ─── Export / Import ─────────────────────────────────────────────────────────

mkdir -p "$DUMP_DIR"

for table in "${TABLES[@]}"; do
    log "Exportando ${table} de produção..."
    psql_prod -c "\\COPY ${table} TO '${DUMP_DIR}/${table}.csv' WITH CSV HEADER"
    rows=$(wc -l < "${DUMP_DIR}/${table}.csv")
    rows=$((rows - 1))  # descontar header

    log "Importando ${table} no dev (${rows} registros)..."
    psql_dev -c "TRUNCATE ${table} CASCADE"
    psql_dev -c "\\COPY ${table} FROM '${DUMP_DIR}/${table}.csv' WITH CSV HEADER"
done

# ─── Refresh MV ──────────────────────────────────────────────────────────────

log "Refresh da materialized view..."
if psql_dev -c "SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_anuncios_venda'" -t | grep -q 1; then
    psql_dev -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_anuncios_venda"
    mv_count=$(psql_dev -t -c "SELECT count(*) FROM mv_anuncios_venda" | tr -d ' ')
    log "MV atualizada (${mv_count} registros)"
else
    log "MV mv_anuncios_venda não existe (rode as migrations primeiro)"
fi

# ─── Resumo ──────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo " Sync produção → dev concluído"
echo "═══════════════════════════════════════════"
for table in "${TABLES[@]}"; do
    rows=$(wc -l < "${DUMP_DIR}/${table}.csv")
    rows=$((rows - 1))
    printf "  %-25s %6d registros\n" "${table}" "${rows}"
done
echo "═══════════════════════════════════════════"
