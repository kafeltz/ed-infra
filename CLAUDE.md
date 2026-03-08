# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

Repositório de infraestrutura Docker da EasyDoor. Orquestra os serviços base (banco de dados, frontends, worker) via `docker compose`. O schema do banco **não** é gerenciado aqui — fica no repositório `ed-backend-api`.

## Comandos principais

```bash
make up              # Cria diretórios necessários, sobe todos os containers em background
make down            # Para e remove todos os containers
make build           # Reconstrói as imagens Docker
make logs            # Acompanha logs em tempo real (todos os serviços)
make psql            # Abre shell psql (requer PostgreSQL client local)
make restart-db      # Reinicia serviço específico (substitua 'db' pelo nome: ed-backend-api, ed-worker, etc.)
```

## Arquitetura

### Serviços e portas

| Container | Porta | Descrição |
|---|---|---|
| `easydoor-db` | 5434 (host) / 5432 | PostgreSQL 18 + PostGIS 3 + pgaudit |
| `easydoor-backend-api` | 8000 | API FastAPI — única a acessar o banco diretamente |
| `easydoor-worker` | — | Worker de scraping: polling HTTP na API, abre Firefox(es) |
| `easydoor-log-sep` | — | Separador de logs: filtra audit (pgaudit) de logs normais |
| `easydoor-nginx` | 4174, 4175, 4176 | NGINX interno: roteia `/api/` → backend, `/` → Vite |
| `easydoor-frontend` | — (interno) | `ed-frontend-app` (Vite preview) |
| `easydoor-ed-admin` | — (interno) | `ed-admin` (Vite preview) |
| `easydoor-ed-calibrador` | — (interno) | `ed-calibrador` (Vite preview) |

Um NGINX externo (fora deste repo) faz proxy reverso para as portas 4174/4175/4176, que chegam no `easydoor-nginx`. Ele roteia `/api/*` para o backend e o restante para o Vite preview correspondente.

### Volumes como bind mounts locais

- `./data` — dados do PostgreSQL (`/var/lib/postgresql`)
- `./postgres_logs` — logs brutos do PostgreSQL
- `./audit_logs` — logs de auditoria separados pelo `log_separator`

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

## Ambientes locais (dev vs PRD simulado)

Na máquina de desenvolvimento existem **dois ambientes Docker** que coexistem sem conflito:

| Ambiente | Comando | Compose file | Postgres | Keycloak | Apps |
|----------|---------|-------------|----------|----------|------|
| **Dev** | `make dev-up` | `docker-compose.dev.yml` | porta **5433** | porta 10082 | Só DB + Keycloak. Cada app sobe manual na sua pasta (`make dev`) |
| **PRD simulado** | `make up` | `docker-compose.yml` | porta **5434** | porta 8082 | Stack completa (backend, frontend, worker, nginx, etc.) |

**Containers:**
- Dev: `easydoor-db-dev`, `easydoor-keycloak-dev`
- PRD simulado: `easydoor-db`, `easydoor-backend-api`, `easydoor-frontend`, etc.

**Quando usar cada um:**
- **Dev** — desenvolvimento ativo, com hot reload nos apps (cada app roda com `make dev` na sua pasta)
- **PRD simulado** — testar o sistema completo como seria em produção, com todas as imagens Docker buildadas

**Atenção com portas ao rodar queries SQL:**
- `localhost:5433` → banco **dev**
- `localhost:5434` → banco **PRD simulado**
- `localhost:15432` → banco **PRD real** (via SSH tunnel, ver CLAUDE.md raiz do projeto)

## Variáveis de ambiente

Copiar `.env.example` para `.env` antes de subir:

```bash
cp .env.example .env
```

Variáveis: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `WORKER_API_KEY`.

Para o worker remoto, copiar `.env.worker.example` para `.env.worker`:

```bash
cp .env.worker.example .env.worker
```

Variáveis: `API_URL`, `WORKER_API_KEY`, `WORKER_MAX_TOTAL`, `WORKER_HEADLESS`.

## Sincronização de versão servidor/worker

O servidor expõe `GET /api/version` com a versão da imagem. Workers consultam a cada poll e param se a versão mudar.

### Como funciona

- `APP_VERSION` é calculada automaticamente no `Makefile` como o hash curto do git (`git rev-parse --short HEAD`)
- Ao buildar, o Dockerfile do backend recebe `SERVER_VERSION=$APP_VERSION` (o worker **não** recebe versão)
- O servidor expõe `GET /api/version` → `{"version": "<hash>"}`
- A cada poll, o worker compara a versão do servidor com a do poll anterior; se mudou, para e aguarda autoupdate

### Fluxo de deploy

```bash
# 1. Atualizar código e buildar
git pull --rebase gitea master
make build-push   # builda localmente e envia para o registry

# 2. Servidor PRD (se não houver CI ativo)
ssh usuario@servidor
cd ~/ed-infra && git pull gitea master
docker compose pull && docker compose up -d --no-build --remove-orphans

# 3. Workers remotos (em cada máquina)
cd ~/easydoor/ed-infra && git pull gitea master && make worker-up
```

Ver `docs/deploy.md` para o fluxo completo.

### Importante

- **Nunca defina `SERVER_VERSION` no `.env`** — a versão vem do build, não do ambiente
- `WORKER_VERSION` não existe mais — o worker detecta atualizações via `GET /api/version`
- Se o servidor subir com `SERVER_VERSION=""` (dev local), o worker nunca detecta mudança — útil para desenvolvimento

## Schema do banco

O container PostgreSQL sobe **sem tabelas**. O schema é gerenciado pelo `ed-backend-api`:

```bash
cd ~/ed-backend-api && PSQL_CMD='psql -h localhost -p 5434 -U easydoor -d easydoor' make migrate
```
