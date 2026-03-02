# Manual: Worker Remoto

Guia para instalar e operar o `ed-worker` em máquinas remotas, sem precisar
subir toda a infra (banco, frontends).

## Como funciona

O worker roda isolado em Docker e se comunica com o servidor exclusivamente
via **HTTP** — sem SSH tunnel, sem acesso direto ao banco.

```
Máquina remota                         Servidor principal
┌─────────────────────────┐            ┌─────────────────────┐
│  easydoor-worker        │            │  ed-backend-api     │
│  (Docker)               │  HTTP      │  :8000              │
│                         ├───────────▶│                     │
│  GET  /proximo-cep      │            │  PostgreSQL         │
│  POST /anuncios         │            │  (interno)          │
│  PATCH /ceps/{cep}/... │            │                     │
│                         │            └─────────────────────┘
│  Firefox (headless)     │
└─────────────────────────┘
```

A imagem é puxada do registry privado `docker.easydoor.ai` — não é necessário
clonar nenhum repositório de código além do `ed-infra`.

## Pré-requisitos

- Docker instalado na máquina remota

## Instalação

### 1. Clonar apenas o ed-infra

```bash
mkdir -p ~/easydoor && cd ~/easydoor
git clone git@git.easydoor.ai:EasyDoor/ed-infra.git
```

### 2. Autenticar no registry (uma vez)

```bash
docker login docker.easydoor.ai
# usuário: ismael
# senha: ver MEMORY.md
```

### 3. Configurar as variáveis de ambiente

```bash
cd ed-infra
cp .env.worker.example .env.worker
# editar .env.worker com a URL da API e a chave
```

`.env.worker`:
```env
API_URL=https://api.easydoor.ai   # ou http://<IP-DO-PC>:8000 para rede local
WORKER_API_KEY=<chave-segura>
WORKER_MAX_TOTAL=2
WORKER_HEADLESS=1
```

### 4. Subir

```bash
make worker-up
make worker-logs
```

O Docker puxa a imagem `ed-worker:latest` do registry automaticamente (~1 GB na primeira vez).

## Operação diária

```bash
make worker-up       # Sobe o worker
make worker-down     # Para o worker
make worker-restart  # Reinicia sem atualizar
make worker-logs     # Acompanha logs em tempo real
```

## Atualizar após deploy do servidor

Quando o servidor é atualizado, o worker recebe `409 Conflict` e para automaticamente.
Para atualizar, na máquina que roda o worker:

```bash
cd ~/easydoor/ed-infra
git pull gitea master   # atualiza o compose file
make worker-up          # pull da nova imagem + recria o container
```

## Sincronização de versão

O worker tem `WORKER_VERSION` tatuada na imagem no momento do build (hash do git de `ed-infra`).
Se a versão do worker divergir do servidor após um deploy:

1. O servidor rejeita com `409 Conflict`
2. O worker loga `[WARN] Worker desatualizado...` e para o polling
3. O container reinicia automaticamente (`restart: unless-stopped`) e volta a tentar

Para ver a versão atual:
```bash
docker inspect easydoor-worker | grep WORKER_VERSION
```

## Testes

```bash
make worker-test robo=vivareal logradouro="Rua Maria Müller Gieseler" bairro="Velha" localidade="Blumenau" uf=SC
```

Se retornar uma lista de anúncios em JSON, o Firefox e a conexão com a API estão funcionando.

## Ajuste de paralelismo

`WORKER_MAX_TOTAL` controla quantos Firefoxs rodam simultaneamente no container.

| RAM disponível | WORKER_MAX_TOTAL recomendado |
|---|---|
| 4 GB | 1–2 |
| 8 GB | 3–4 |
| 16 GB | 5–8 |

Após alterar `.env.worker`, recriar o container:
```bash
make worker-restart
```

## Troubleshooting

### Worker para logo após subir

```bash
make worker-logs
```

- `[WARN] Worker desatualizado` → versão desatualizada, rode `git pull gitea master && make worker-up` na máquina do worker
- Erro de conexão HTTP → verificar `API_URL` e `WORKER_API_KEY` no `.env.worker`

### Firefox trava ou não abre

```bash
docker exec easydoor-worker df -h /dev/shm
```

Deve mostrar `2.0G`. Se não mostrar, o `shm_size: 2gb` não está sendo aplicado.
