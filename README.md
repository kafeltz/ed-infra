# ed-infra

Infraestrutura completa EasyDoor em Docker: PostgreSQL 18 + PostGIS + Redis + 3 frontends.

## Serviços

| Serviço | Imagem | Porta |
|---|---|---|
| `db` | PG 18 + PostGIS 3 + pgaudit | 5432 |
| `redis` | redis:7-alpine | 6379 |
| `log_separator` | python:3.11-slim | — |
| `ed-frontend-app` | node:20-alpine (Vite preview) | 4175 |
| `admin` | node:20-alpine (Vite preview) | 4176 |
| `calibrador` | node:20-alpine (Vite preview) | 4174 |

O NGINX externo faz proxy reverso para essas portas.

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
