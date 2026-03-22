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
  `ed-backend-api`, `ed-worker`, `ed-geocoder`, `ed-watchdog`,
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

1. `make build` — builda todas as imagens tatuando `APP_VERSION=$(git rev-parse --short HEAD)`
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

No servidor:
```bash
cd ~/ed-infra
git pull gitea master
docker compose pull
docker compose up -d --no-build --remove-orphans
```

> O servidor não precisa de nenhum outro repositório além de `ed-infra`.

---

## Imagens e tags

| Imagem | Tag | Quando muda |
|--------|-----|-------------|
| `ed-postgres` | `:latest` | Raramente (mudança no Dockerfile do postgres) |
| `ed-keycloak` | `:latest` | Raramente (mudança no Dockerfile do keycloak) |
| `ed-backend-api` | `:<hash>` + `:latest` | A cada push em qualquer serviço |
| `ed-worker` | `:<hash>` + `:latest` | A cada push em qualquer serviço |
| `ed-geocoder` | `:<hash>` + `:latest` | A cada push em qualquer serviço |
| `ed-watchdog` | `:<hash>` + `:latest` | A cada push em qualquer serviço |
| `ed-frontend-app` | `:<hash>` + `:latest` | A cada push em qualquer serviço |
| `ed-admin` | `:<hash>` + `:latest` | A cada push em qualquer serviço |
| `ed-calibrador` | `:<hash>` + `:latest` | A cada push em qualquer serviço |

`APP_VERSION` = hash curto do HEAD de `ed-infra` no momento do build.

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

A partir daí, deploys futuros seguem o fluxo da seção acima (build-push + pull no servidor).

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

Para desenvolvimento local, use o `make rebuild` em vez de `make up`:

```bash
make build       # builda as imagens localmente
make rebuild     # builda + recria os containers (sem precisar do registry)
```

> **Atenção:** `make up` tenta puxar a imagem com tag `:<hash-do-git-local>` do registry.
> Se você fez commits locais sem dar `make push`, o Docker não vai encontrar essa tag e vai falhar.
> Use `make rebuild` para dev local, ou `make up` só após `make build-push`.
