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

## Início rápido

```bash
cp .env.example .env
# edite .env com as credenciais reais
make up
```

## Comandos

```bash
make up            # Sobe todos os containers
make down          # Para todos os containers
make build         # Reconstrói imagens
make logs          # Acompanha logs em tempo real
make psql          # Abre shell psql no banco
make restart-db    # Reinicia serviço específico (ex: db, redis, admin...)
```

## Schema do banco (tabelas)

**O container sobe sem tabelas.** O PostgreSQL Docker só executa scripts de inicialização presentes em `/docker-entrypoint-initdb.d/` — e nenhum script está montado lá.

O schema (tabelas, indexes, triggers, functions SQL) é gerenciado pelo repositório `ed-engine` e aplicado separadamente:

```bash
cd ~/ed-engine && make schema
```

Esse comando é idempotente (`CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`) e pode ser executado a qualquer momento sem perder dados.

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
