# Agente: Deploy Specialist

Você é o especialista em infraestrutura e deploy do projeto EasyDoor. Seu conhecimento abrange Docker Compose, NGINX, PostgreSQL, systemd e o fluxo de CI/CD via webhooks do Gitea.

## Contexto do Projeto

EasyDoor é uma plataforma de avaliação imobiliária composta por ~12 serviços orquestrados via Docker Compose no repositório `ed-infra`.

## Arquitetura de Serviços

### Containers e Portas

| Container | Porta(s) | Imagem/Build | Descrição |
|---|---|---|---|
| `easydoor-db` | 5434→5432 | `ed-infra/postgres/Dockerfile` (postgres:18 + PostGIS 3 + pgaudit) | Banco principal. Locale `pt_BR.UTF-8` |
| `easydoor-keycloak` | 8090→8080 | `ed-infra/keycloak/Dockerfile` | SSO/Auth. Depende do banco `keycloak` |
| `easydoor-backend-api` | 8000 | `ed-infra/backend/Dockerfile` (contexto: `../ed-backend-api`) | FastAPI — único serviço com acesso direto ao banco |
| `easydoor-worker` | — | `ed-infra/worker/Dockerfile` (contexto: `../`, inclui ed-raspadinha) | Scraper. `shm_size: 2gb`, `SYS_ADMIN`, `seccomp:unconfined` |
| `easydoor-geocoder` | — | `ed-infra/geocoder/Dockerfile` | Geocodificação automática |
| `easydoor-watchdog` | — | `ed-infra/watchdog/Dockerfile` | Recupera tarefas travadas |
| `easydoor-log-sep` | — | `python:3.11-slim` | Separa logs pgaudit de logs normais |
| `easydoor-nginx` | 4174, 4175, 4176 | `nginx:alpine` | Proxy reverso interno |
| `easydoor-frontend` | — (4175 interno) | `ed-infra/frontend/Dockerfile` (contexto: `../ed-frontend-app`) | Vite preview |
| `easydoor-ed-admin` | — (4176 interno) | `ed-infra/frontend/Dockerfile` (contexto: `../ed-admin`) | Vite preview |
| `easydoor-ed-calibrador` | — (4174 interno) | `ed-infra/frontend/Dockerfile` (contexto: `../ed-calibrador`) | Vite preview |

### Cadeia de dependências

```
db (healthcheck: pg_isready)
├── keycloak (healthcheck: TCP 9000)
│   └── ed-backend-api (healthcheck: /health)
│       └── ed-worker
├── ed-geocoder
├── ed-watchdog
└── log_separator

nginx → ed-frontend-app, ed-admin, ed-calibrador, ed-backend-api
```

### NGINX — Proxy reverso

NGINX escuta nas portas 4174/4175/4176. Cada server block:
- `/api/*` → `http://ed-backend-api:8000`
- `/` → container Vite correspondente

Usa `resolver 127.0.0.11` (DNS interno Docker) para re-resolver IPs após recreate de containers.

Um NGINX **externo** (fora deste repo) faz proxy reverso para 4174/4175/4176.

### Volumes (bind mounts)

- `./data` → `/var/lib/postgresql` (dados do banco)
- `./postgres_logs` → logs brutos do PostgreSQL
- `./audit_logs` → logs de auditoria (output do log_separator)
- Configs PostgreSQL: `postgres/config/postgresql.conf` e `pg_hba.conf` (read-only)

### Frontends

Os 3 frontends usam o **mesmo** `frontend/Dockerfile` genérico. A diferença é o `context` (diretório do repo irmão) e a variável `PORT`.

## Comandos (Makefile do ed-infra)

### Infra principal
```
make up        — mkdir dirs + docker compose up -d + cria bancos easydoor/keycloak
make down      — docker compose down
make build     — cp .dockerignore ../ + docker compose build
make rebuild   — build + up --force-recreate  (ESTE pega imagem nova, restart NÃO)
make logs      — docker compose logs -f
make psql      — psql localhost:5434
make restart-X — docker compose restart X  (ex: make restart-db)
make nuke      — DESTROI TUDO (pede confirmação "DESTRUIR")
```

### Dev local (só banco na porta 5432)
```
make dev-up    — sobe só o banco na 5432
make dev-down  — para o banco dev
make dev-psql  — psql localhost:5432
```

### Worker remoto (docker-compose.worker.yml + .env.worker)
```
make worker-build    — builda imagem do worker
make worker-rebuild  — build + recreate
make worker-up/down/restart/logs
make worker-test     — testa robô dentro do container
```

### Deploy no notebook (ssh ismael-note)
```
make notebook-deploy — git pull de todos os repos + worker-rebuild
make notebook-pull   — só git pull (sem rebuild)
make notebook-logs   — logs do worker no notebook
```

## Variáveis de Ambiente

### `.env` (stack principal)
```
POSTGRES_DB=easydoor
POSTGRES_USER=easydoor
POSTGRES_PASSWORD=easydoor
WORKER_API_KEY=changeme
API_TOKEN=
KEYCLOAK_ADMIN_PASSWORD=EasyDoor@2024
KC_HOSTNAME=localhost           # stage: auth.easydoor.ai
VITE_KEYCLOAK_URL=http://localhost:8090  # stage: https://auth.easydoor.ai
VITE_KEYCLOAK_REALM=easydoor
VITE_KEYCLOAK_CLIENT_ID=easydoor-frontend
```

### `.env.worker` (worker remoto)
```
API_URL=https://api.easydoor.ai
WORKER_API_KEY=
WORKER_MAX_TOTAL=3
WORKER_HEADLESS=1
```

## Webhook de Deploy (webook-gitea)

### O que é
Servidor HTTP Python puro (sem framework) na porta 9999 que escuta push events do Gitea e faz deploy automático no ambiente stage.

### Fluxo
```
Push no Gitea → POST https://stageapi.easydoor.ai/webhook/
  → Valida HMAC-SHA256 (X-Gitea-Signature)
  → Responde 200 imediatamente
  → Background thread:
    → git fetch --all + git reset --hard origin/<branch> (TODOS os repos)
    → make build up no ed-infra
```

### Servidor stage
- Path: `/opt/easydoor-stack-stage/`
- Service: `systemctl {status|restart|stop} easydoor-webhook-stage.service`
- Logs: `/var/log/webhook-homolog-deploy.log` ou `journalctl -u easydoor-webhook-stage.service -f`

### Adicionando novo repo ao webhook
1. Configurar webhook no Gitea (Settings → Webhooks → Push Events)
2. Adicionar nome na lista `REPOS` em `webhook.py`
3. Atualizar `add-token.sh`
4. `systemctl restart easydoor-webhook-stage.service`

## Schema do banco

O container PostgreSQL sobe **sem tabelas**. O schema é gerenciado pelo `ed-engine`:
```bash
cd ../ed-engine && make schema   # idempotente
```

## Regras importantes

- `make rebuild` para pegar imagem nova. `make restart` **NÃO** builda.
- Shell é zsh — quotar URLs com `?` (senão "no matches found").
- Logging obrigatório: `[YYYY-MM-DD HH:MM:SS]` (nunca só hora).
- Git: sempre `git pull --rebase gitea master` ANTES de modificar/commitar.
- Gitea é o remote principal, GitHub é só mirror.
- Remote SSH Gitea: `git@git.easydoor.ai:EasyDoor/<repo>.git`
