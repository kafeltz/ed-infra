# ed-infra

Infraestrutura completa EasyDoor em Docker: PostgreSQL 18 + PostGIS + Redis + 3 frontends.

## Serviços

| Serviço | Imagem | Porta |
|---|---|---|
| `db` | PG 18 + PostGIS 3 + pgaudit | 5432 |
| `redis` | redis:7-alpine | 6379 |
| `log_separator` | python:3.11-slim | — |
| `ed-worker` | python:3.11-slim + Firefox | — |
| `nginx` | nginx:alpine | 4174, 4175, 4176 |
| `ed-frontend-app` | node:20-alpine (Vite preview) | — (interno) |
| `ed-admin` | node:20-alpine (Vite preview) | — (interno) |
| `ed-calibrador` | node:20-alpine (Vite preview) | — (interno) |
| `ed-backend-api` | python (FastAPI) | 8000 |

O NGINX interno roteia `/api/` → backend e `/` → Vite preview. Um NGINX externo faz SSL e proxy para as portas acima.

## Arquitetura

```
                        ┌─────────────────────────────────────────────┐
                        │              docker-compose                  │
                        │                                              │
  NGINX externo (SSL)   │  ┌──────────┐   ┌──────────────────────┐   │
  stageadmin  ──────────┼─▶│  nginx   │──▶│  ed-admin  (Vite)    │   │
  stagefront  ──────────┼─▶│ (interno)│──▶│  ed-frontend (Vite)  │   │
  stagecalib  ──────────┼─▶│          │──▶│  ed-calibrador (Vite)│   │
                        │  │          │   └──────────────────────┘   │
                        │  │  /api/   │   ┌──────────────────────┐   │
                        │  │ ─────────┼──▶│  ed-backend-api      │   │
                        │  └──────────┘   └──────────┬───────────┘   │
                        │                            │               │
                        │  ┌─────────────────────┐  │               │
                        │  │     ed-worker        │  │               │
                        │  │                      │  ▼               │
                        │  │  worker.py           │  ┌────────────┐  │
                        │  │    │                 │  │ PostgreSQL │  │
                        │  │    ▼                 ├─▶│  (easydoor │  │
                        │  │  Camoufox()          │  │   -db)     │  │
                        │  │    │                 │  └────────────┘  │
                        │  │    ▼                 │  ┌────────────┐  │
                        │  │  🦊 Firefox          ├─▶│   Redis    │  │
                        │  │  (baked na imagem)   │  │ (easydoor  │  │
                        │  │                      │  │   -redis)  │  │
                        │  └─────────────────────┘  └────────────┘  │
                        └─────────────────────────────────────────────┘
```

### Worker e o Firefox

O `ed-worker` e o Firefox **não são containers separados** — o Firefox roda como processo filho dentro do próprio container do worker.

Em modo desenvolvimento (fora do Docker), o worker é um processo Python no seu PC e o Firefox abre localmente via `ed-raspadinha/venv/`. Dentro do Docker, é exatamente o mesmo modelo: o worker é um processo Python dentro do container `easydoor-worker`, e o Firefox abre dentro desse mesmo container — instalado na imagem durante o `docker build` via `python -m camoufox fetch`.

| | Desenvolvimento | Docker |
|---|---|---|
| Firefox instalado em | `ed-raspadinha/venv/` (via `make install`) | imagem `easydoor-worker` (via `docker build`) |
| Quem instalou | `python -m camoufox fetch` no venv local | `python -m camoufox fetch` no Dockerfile |
| Código do robô | `ed-raspadinha/` no host | copiado para dentro da imagem no build |

## Deploy do worker em máquinas remotas

Para instalar o worker em outras máquinas sem subir toda a infra, use o `docker-compose.worker.yml`. Ele contém apenas o `ed-worker` e se conecta ao Redis e PostgreSQL do servidor principal via **SSH tunnel**.

### 1. Abrir o tunnel no host remoto

```bash
ssh -N \
  -L 5432:localhost:5432 \
  -L 6379:localhost:6379 \
  usuario@servidor-principal
```

### 2. Configurar e subir

```bash
cp .env.worker.example .env.worker
# editar .env.worker se as portas forem diferentes

docker compose -f docker-compose.worker.yml build
docker compose -f docker-compose.worker.yml up -d
```

O `network_mode: host` faz o container enxergar o `localhost` do host — onde o tunnel está escutando. Sem isso, `localhost` dentro do container seria o próprio container, não o host.

---

## Worker de scraping (ed-worker)

O worker consome CEPs da fila Redis (`easydoor:ceps:fila`), abre instâncias do Firefox via **Camoufox** (Firefox anti-detecção, headless) e persiste anúncios diretamente no PostgreSQL.

### Paralelismo

O número de Firefoxs simultâneos é controlado por `WORKER_MAX_TOTAL` no `docker-compose.yml`:

```yaml
environment:
  WORKER_MAX_TOTAL: "3"   # até 3 CEPs/browsers em paralelo no mesmo container
```

Não é necessário rodar múltiplos containers — só aumentar esse número.

### Requisitos especiais do Firefox em Docker

O Firefox requer configurações específicas no container para funcionar estável:

| Configuração | Motivo |
|---|---|
| `shm_size: 2gb` | O `/dev/shm` padrão do Docker (64MB) é insuficiente para o Firefox e causa crashes |
| `security_opt: seccomp:unconfined` | O sandbox do Firefox usa syscalls bloqueadas pelo perfil seccomp padrão do Docker |
| `cap_add: SYS_ADMIN` | Necessário para o namespace de processos do sandbox do Firefox |

Sem essas três configurações o Firefox trava ou não abre.

## Primeiros passos (novo programador)

### Pré-requisitos

- Docker e Docker Compose instalados
- `psql` (cliente PostgreSQL) instalado localmente
- Repositórios irmãos clonados na **mesma pasta pai**:

```
easydoor/
├── ed-infra/        ← este repo
├── ed-engine/       ← schema e lógica SQL
├── ed-backend-api/  ← API backend
├── ed-frontend-app/ ← frontend principal
├── ed-admin/        ← painel admin
└── ed-calibrador/   ← ferramenta de calibração
```

### 1. Configurar variáveis de ambiente

```bash
cp .env.example .env
# Para desenvolvimento local, os valores do .env.example já funcionam.
```

### 2. Subir a infraestrutura

```bash
make up
```

Isso cria os diretórios de dados, sobe todos os containers e garante que o banco `easydoor` existe.

### 3. Aplicar o schema do banco

O banco sobe vazio. O schema (tabelas, indexes, triggers, functions) é gerenciado pelo `ed-engine`:

```bash
cd ../ed-engine
make schema   # cria toda a estrutura
make seed     # popula dados iniciais (mat_ajustes + anúncios)
```

Ambos os comandos são idempotentes e podem ser reexecutados a qualquer momento sem perder dados.

### 4. Verificar que tudo está funcionando

```bash
# Containers saudáveis
docker compose ps

# Banco com schema aplicado
psql -h localhost -U easydoor -d easydoor -c "\dt"

# PostGIS ativo
psql -h localhost -U easydoor -d easydoor -c "SELECT PostGIS_version();"

# Redis
redis-cli ping

# Frontends (se buildados)
curl -s http://localhost:4175 | head -5   # ed-frontend-app
curl -s http://localhost:4176 | head -5   # ed-admin
curl -s http://localhost:4174 | head -5   # ed-calibrador
```

---

## Comandos do dia a dia

```bash
make up            # Sobe todos os containers (seguro rodar mais de uma vez)
make down          # Para todos os containers
make build         # Reconstrói as imagens Docker
make logs          # Acompanha logs em tempo real
make psql          # Abre shell psql no banco
make restart-db    # Reinicia serviço específico (ex: db, redis, ed-admin...)
make nuke          # ⚠ DESTRÓI TUDO — containers + dados + logs (pede confirmação)
```

### Recomeçar do zero

Se precisar apagar tudo e reinicializar (ex: banco corrompido, testar migração):

```bash
make nuke     # destrói tudo (pede confirmação digitando DESTRUIR)
make up       # recria infra limpa
cd ../ed-engine && make schema && make seed
```

## Migração PG 16 nativo → PG 18 Docker

```bash
# 1. Backup no PG 16 nativo
pg_dump -U easydoor -Fc easydoor > ~/backup_pg16_$(date +%Y%m%d).dump

# 2. Subir containers
cd ~/easydoor/ed-infra && make up

# 3. Restaurar dump no PG 18
pg_restore -h localhost -p 5432 -U easydoor -d easydoor \
  --no-owner --role=easydoor ~/backup_pg16_*.dump

# 4. Validar dados
psql -h localhost -p 5432 -U easydoor -d easydoor -c "SELECT COUNT(*) FROM anuncios;"

# 5. Parar PG 16 nativo
sudo systemctl stop postgresql && sudo systemctl disable postgresql

# 6. Reaplicar functions do ed-engine
cd ~/ed-engine && make schema
```

## Verificação

```bash
docker compose ps
psql -h localhost -U easydoor -d easydoor -c "SELECT PostGIS_version();"
curl -s http://localhost:4175 | head -5
curl -s http://localhost:4176 | head -5
curl -s http://localhost:4174 | head -5
redis-cli ping
cd ~/ed-engine && make test-quick
```

## Estrutura

```
ed-infra/
├── docker-compose.yml
├── .env.example
├── Makefile
├── postgres/
│   ├── Dockerfile                  # PG 18 + PostGIS + pgaudit (via pgdg APT)
│   ├── config/
│   │   ├── postgresql.conf
│   │   └── pg_hba.conf
│   └── separate_logs_realtime.py   # Separador de logs de auditoria
└── frontend/
    └── Dockerfile                  # Vite build + preview genérico (node 20)
```

Os frontends (`ed-frontend-app`, `admin`, `calibrador`) são buildados a partir dos seus próprios repositórios usando o `frontend/Dockerfile` genérico deste repo.
