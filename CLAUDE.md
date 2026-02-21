# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

Repositório de infraestrutura Docker da EasyDoor. Orquestra os serviços base (banco de dados, cache, frontends) via `docker compose`. O schema do banco **não** é gerenciado aqui — fica no repositório `ed-engine`.

## Comandos principais

```bash
make up              # Cria diretórios necessários, sobe todos os containers em background
make down            # Para e remove todos os containers
make build           # Reconstrói as imagens Docker
make logs            # Acompanha logs em tempo real (todos os serviços)
make psql            # Abre shell psql (requer PostgreSQL client local)
make restart-db      # Reinicia serviço específico (substitua 'db' pelo nome: redis, ed-frontend-app, etc.)
```

## Arquitetura

### Serviços e portas

| Container | Porta | Descrição |
|---|---|---|
| `easydoor-db` | 5432 | PostgreSQL 18 + PostGIS 3 + pgaudit |
| `easydoor-redis` | 6379 | Redis 7 com persistência |
| `easydoor-log-sep` | — | Separador de logs: filtra audit (pgaudit) de logs normais |
| `easydoor-worker` | — | Worker de scraping: consome fila Redis, abre Firefox(es), grava no Postgres |
| `easydoor-nginx` | 4174, 4175, 4176 | NGINX interno: roteia `/api/` → backend, `/` → Vite |
| `easydoor-frontend` | — (interno) | `ed-frontend-app` (Vite preview) |
| `easydoor-ed-admin` | — (interno) | `ed-admin` (Vite preview) |
| `easydoor-ed-calibrador` | — (interno) | `ed-calibrador` (Vite preview) |

Um NGINX externo (fora deste repo) faz proxy reverso para as portas 4174/4175/4176, que chegam no `easydoor-nginx`. Ele roteia `/api/*` para o backend e o restante para o Vite preview correspondente.

### Volumes como bind mounts locais

- `./data` — dados do PostgreSQL (`/var/lib/postgresql`)
- `./postgres_logs` — logs brutos do PostgreSQL
- `./audit_logs` — logs de auditoria separados pelo `log_separator`
- `./redis_data` — dados de persistência do Redis

Esses diretórios são criados pelo `make up` e estão no `.gitignore`.

### Frontends

Os três frontends (`ed-frontend-app`, `ed-admin`, `ed-calibrador`) são buildados com um único `frontend/Dockerfile` genérico (build Vite + preview). O `context` do build aponta para o repositório irmão (`../ed-frontend-app`, etc.), mas o Dockerfile vem de `../ed-infra/frontend/Dockerfile`.

### PostgreSQL customizado

O `postgres/Dockerfile` parte de `postgres:18` e adiciona via apt do repositório PGDG (Debian Trixie):
- `postgresql-18-postgis-3` + scripts
- `postgresql-18-pgaudit`
- Locale `pt_BR.UTF-8`

Configurações customizadas são montadas como bind mounts read-only:
- `postgres/config/postgresql.conf`
- `postgres/config/pg_hba.conf`

### Separação de logs de auditoria

O serviço `log_separator` executa `postgres/separate_logs_realtime.py` em tempo real, lendo `/var/log/postgresql/postgresql.log` e separando entradas pgaudit em `audit_logs/audit.log` e logs normais em `audit_logs/postgres.log`.

## Variáveis de ambiente

Copiar `.env.example` para `.env` antes de subir:

```bash
cp .env.example .env
```

Variáveis: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`.

## Schema do banco

O container PostgreSQL sobe **sem tabelas**. O schema é gerenciado pelo `ed-engine`:

```bash
cd ~/ed-engine && make schema   # idempotente — pode rodar a qualquer momento
```
