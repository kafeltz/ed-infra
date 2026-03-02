# Deploy — EasyDoor

## Visão geral

As imagens Docker são buildadas localmente (ou pela CI) e publicadas no registry privado
`docker.easydoor.ai`. O servidor de produção apenas faz `docker pull` — não precisa de nenhum
código-fonte além do `ed-infra`.

---

## Fluxo manual (máquina local)

Use quando não há CI configurada, ou para forçar um deploy imediato.

### Pré-requisitos

- Todos os repos irmãos presentes em `~/projects/easydoor/`:
  `ed-backend-api`, `ed-worker`, `ed-raspadinha`, `ed-geocoder`, `ed-watchdog`,
  `ed-frontend-app`, `ed-admin`, `ed-calibrador`
- Docker autenticado no registry (ver abaixo)

### 1. Autenticar no registry

```bash
echo 'SENHA' | docker login docker.easydoor.ai -u ismael --password-stdin
```

A senha está na memória do projeto (`MEMORY.md`). Só precisa fazer isso uma vez por máquina —
o Docker salva as credenciais em `~/.docker/config.json`.

### 2. Atualizar o código

```bash
# Em ed-infra e em cada repo irmão relevante:
git pull gitea master
```

### 3. Buildar e publicar todas as imagens

```bash
make build-push
```

Esse target faz dois passos em sequência:

1. `make build` — builda com o overlay `docker-compose.build.yml`, tatuando
   `APP_VERSION=$(git rev-parse --short HEAD)` nas imagens
2. `make push` — faz tag `:latest` + push de cada imagem para `docker.easydoor.ai/easydoor/`

**Só buildar** (sem push):
```bash
make build
```

**Só fazer push** (imagens já buildadas):
```bash
make push
```

### 4. Deploy no servidor PRD

```bash
make prd-deploy PRD_HOST=usuario@servidor
```

O que esse target faz via SSH:
```bash
cd ~/ed-infra
git pull gitea master      # atualiza compose files e configs
docker compose pull        # baixa as novas imagens do registry
docker compose up -d --no-build --remove-orphans
```

> O servidor não precisa de nenhum outro repositório além de `ed-infra`.

---

## Imagens e tags

| Imagem | Tag | Quando muda |
|--------|-----|-------------|
| `ed-postgres` | `:latest` | Raramente (mudança no Dockerfile do postgres) |
| `ed-keycloak` | `:latest` | Raramente (mudança no Dockerfile do keycloak) |
| `ed-backend-api` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |
| `ed-worker` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |
| `ed-geocoder` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |
| `ed-watchdog` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |
| `ed-frontend-app` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |
| `ed-admin` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |
| `ed-calibrador` | `:88b1ae3` + `:latest` | A cada push em qualquer serviço |

`APP_VERSION` = hash curto do HEAD de `ed-infra` (ex: `88b1ae3`).

---

## Setup inicial do servidor PRD

Quando o servidor estiver pronto:

```bash
# 1. Clonar apenas o ed-infra
git clone git@git.easydoor.ai:EasyDoor/ed-infra.git
cd ed-infra

# 2. Configurar variáveis de ambiente
cp .env.example .env
vim .env   # preencher POSTGRES_PASSWORD, WORKER_API_KEY, KC_HOSTNAME, etc.

# 3. Autenticar no registry
echo 'SENHA' | docker login docker.easydoor.ai -u ismael --password-stdin

# 4. Subir tudo (puxa as imagens automaticamente)
make up
```

A partir daí, deploys futuros são apenas `make prd-deploy PRD_HOST=...`.

---

## Fluxo CI (Gitea Actions)

> **Ainda não ativo** — requer configurar um Gitea Actions runner e secrets.
> Ver issue correspondente.

Quando configurado, o CI dispara automaticamente ao fazer push em qualquer repo de serviço:

```
push em ed-backend-api (ou outro serviço)
  └─ trigger-build.yml → dispara workflow em ed-infra
       └─ build-and-push.yml → builda + push → (futuramente) deploy automático no PRD
```

Secrets necessários no Gitea (`ed-infra` > Settings > Actions > Secrets):
- `REGISTRY_USER` — `ismael`
- `REGISTRY_PASSWORD` — senha do registry
- `GITEA_TOKEN` — token para clonar repos privados na CI
- `SSH_PRIVATE_KEY` — chave SSH para deploy no servidor (fase futura)
- `SSH_HOST` — IP/hostname do servidor PRD (fase futura)

---

## Dev local (sem registry)

Para desenvolvimento, use o overlay de build diretamente — sem precisar do registry:

```bash
make build       # builda localmente com docker-compose.build.yml
make rebuild     # builda + recria containers
make up          # sobe (puxa do registry — requer login)
```

Para subir com imagens buildadas localmente em vez do registry, use o overlay:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d
```
