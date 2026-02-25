# ed-infra

Infraestrutura completa EasyDoor em Docker: PostgreSQL 18 + PostGIS + API backend + worker + 3 frontends.

## Serviços

| Serviço | Imagem | Porta |
|---|---|---|
| `db` | PG 18 + PostGIS 3 + pgaudit | 5434 (host) / 5432 |
| `ed-backend-api` | python (FastAPI) | 8000 |
| `ed-worker` | python:3.11-slim + Firefox | — |
| `ed-geocoder` | python:3.11-slim | — |
| `log_separator` | python:3.11-slim | — |
| `nginx` | nginx:alpine | 4174, 4175, 4176 |
| `ed-frontend-app` | node:20-alpine (Vite preview) | — (interno) |
| `ed-admin` | node:20-alpine (Vite preview) | — (interno) |
| `ed-calibrador` | node:20-alpine (Vite preview) | — (interno) |

O NGINX interno roteia `/api/` → backend e `/` → Vite preview. Um NGINX externo faz SSL e proxy para as portas acima.

## Arquitetura

```
                        ┌──────────────────────────────────────────────┐
                        │              docker-compose                   │
                        │                                               │
  NGINX externo (SSL)   │  ┌──────────┐   ┌───────────────────────┐   │
  stageadmin  ──────────┼─▶│  nginx   │──▶│  ed-admin  (Vite)     │   │
  stagefront  ──────────┼─▶│ (interno)│──▶│  ed-frontend (Vite)   │   │
  stagecalib  ──────────┼─▶│          │──▶│  ed-calibrador (Vite) │   │
                        │  │          │   └───────────────────────┘   │
                        │  │  /api/   │   ┌───────────────────────┐   │
                        │  │ ─────────┼──▶│  ed-backend-api       │   │
                        │  └──────────┘   └───────────┬───────────┘   │
                        │                      ▲      │               │
                        │                      │      ▼               │
                        │  ┌───────────────┐   │  ┌────────────┐      │
                        │  │  ed-worker    │   │  │ PostgreSQL │      │
                        │  │               │   │  │ (easydoor  │      │
                        │  │  worker.py    ├───┘  │  -db)      │      │
                        │  │    │          │      └─────┬──────┘      │
                        │  │    ▼          │  polling   │             │
                        │  │  Camoufox()   │  HTTP na   │             │
                        │  │    │          │  API       │             │
                        │  │    ▼          │            │             │
                        │  │  Firefox      │   ┌───────┴────────┐    │
                        │  └───────────────┘   │  ed-geocoder   │    │
                        │                      │  polling SQL   │    │
                        │                      │  ViaCEP +      │    │
                        │                      │  Nominatim     │    │
                        │                      └────────────────┘    │
                        └──────────────────────────────────────────────┘
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

Para rodar o worker em outras máquinas sem subir toda a infra, use o `docker-compose.worker.yml`. Ele contém apenas o `ed-worker` e se comunica exclusivamente via HTTP com a API — não requer SSH tunnel, acesso direto ao banco ou qualquer outro serviço.

### Pré-requisitos

O build precisa de três repositórios na mesma pasta pai:

```bash
mkdir ~/projects/easydoor && cd ~/projects/easydoor
git clone git@git.easydoor.ai:EasyDoor/ed-infra.git
git clone git@git.easydoor.ai:EasyDoor/ed-worker.git
git clone git@git.easydoor.ai:EasyDoor/ed-raspadinha.git
```

### Configurar e subir

```bash
cd ed-infra
cp .env.worker.example .env.worker
# editar .env.worker com a URL da API e a chave

make worker-build
make worker-up
make worker-logs
```

### Cenário 1 — Worker aponta para o PC local (rede local)

Descubra o IP do PC na rede local:

```bash
# rodar no PC onde a API está rodando
hostname -I | awk '{print $1}'
```

`.env.worker`:
```env
API_URL=http://<IP-DO-PC>:8000
WORKER_API_KEY=changeme
WORKER_MAX_TOTAL=2
WORKER_HEADLESS=1
```

### Cenário 2 — Worker aponta para servidor externo

`.env.worker`:
```env
API_URL=http://worker.kafeltz.com.br
WORKER_API_KEY=<chave-segura>
WORKER_MAX_TOTAL=2
WORKER_HEADLESS=1
```

Pré-requisitos no servidor externo:
- API (`ed-backend-api`) rodando e acessível na porta configurada
- Mesma `WORKER_API_KEY` configurada no servidor

---

## Worker de scraping (ed-worker)

O worker faz polling HTTP na API (`GET /api/v1/worker/proximo-cep`), abre instâncias do Firefox via **Camoufox** (Firefox anti-detecção, headless) e persiste anúncios via API HTTP.

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
├── ed-geocoder/     ← scheduler de geocodificação
├── ed-worker/       ← worker de scraping
├── ed-raspadinha/   ← lib de scraping (usada pelo worker)
├── ed-frontend-app/ ← frontend principal
├── ed-admin/        ← painel admin
└── ed-calibrador/   ← ferramenta de calibração
```

**Todos os repositórios acima são necessários para o build.** O `docker compose build` usa `context: ../` (diretório pai), então cada serviço espera que seu repositório exista como pasta irmã do `ed-infra`. Se faltar algum, o build falha com erro `not found`.

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

# API respondendo
curl -s http://localhost:8000/health

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
make restart-db    # Reinicia serviço específico (ex: db, ed-admin, ed-worker...)
make nuke          # ⚠ DESTRÓI TUDO — containers + dados + logs (pede confirmação)

# Rebuildar e reiniciar um serviço específico (ex: após atualizar o código do ed-admin)
docker compose build ed-admin && docker compose up -d ed-admin
```

### Recomeçar do zero

Se precisar apagar tudo e reinicializar (ex: banco corrompido, testar migração):

```bash
make nuke     # destrói tudo (pede confirmação digitando DESTRUIR)
make up       # recria infra limpa
cd ../ed-engine && make schema && make seed
```

## Geocoder (ed-geocoder)

Scheduler que preenche lat/lon dos anúncios automaticamente. Faz polling no Postgres, encontra anúncios sem coordenadas e geocodifica via ViaCEP + Nominatim. Resultados ficam em `geocodificacao_cache` para evitar chamadas repetidas.

- **Polling**: a cada 30s (configurável via `GEOCODER_POLL_INTERVAL`)
- **Batch**: 50 anúncios por ciclo (configurável via `GEOCODER_BATCH_SIZE`)
- **Rate limit**: 1 req/seg no Nominatim (sleep 1.1s entre chamadas)
- **Acesso direto ao banco** (não passa pela API)

```bash
# Verificar logs do geocoder
docker logs -f easydoor-geocoder
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
curl -s http://localhost:8000/health     # API backend
cd ~/ed-engine && make test-quick
```

## Estrutura

```
ed-infra/
├── docker-compose.yml              # Stack completa (dev local)
├── docker-compose.worker.yml       # Apenas worker (deploy remoto)
├── .env.example                    # Variáveis da stack principal
├── .env.worker.example             # Variáveis do worker remoto
├── Makefile
├── postgres/
│   ├── Dockerfile                  # PG 18 + PostGIS + pgaudit (via pgdg APT)
│   ├── config/
│   │   ├── postgresql.conf
│   │   └── pg_hba.conf
│   └── separate_logs_realtime.py   # Separador de logs de auditoria
├── backend/
│   └── Dockerfile                  # FastAPI (ed-backend-api)
├── worker/
│   └── Dockerfile                  # Worker + Firefox (ed-worker + ed-raspadinha)
├── geocoder/
│   └── Dockerfile                  # Geocoder (ed-geocoder)
├── frontend/
│   └── Dockerfile                  # Vite build + preview genérico (node 20)
└── nginx/
    └── nginx.conf                  # Roteia /api/ → backend, / → Vite
```

Os frontends (`ed-frontend-app`, `admin`, `calibrador`) são buildados a partir dos seus próprios repositórios usando o `frontend/Dockerfile` genérico deste repo.
