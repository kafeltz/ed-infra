# Manual: Worker Remoto

Guia para instalar e operar o `ed-worker` em máquinas remotas, sem precisar
subir toda a infra (banco, frontends).

## Como funciona

O worker roda isolado em Docker e se comunica com o servidor exclusivamente
via **HTTP** — sem SSH tunnel, sem acesso direto ao banco, sem Redis.

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

## Pré-requisitos

- Docker instalado na máquina remota
- Acesso SSH ao servidor principal (para o deploy)
- Repositórios clonados lado a lado:

```
~/easydoor/
├── ed-infra/        ← orquestra o build
├── ed-worker/       ← código do worker
└── ed-raspadinha/   ← lib de scraping (necessária para o build da imagem)
```

## Instalação

### 1. Clonar os repositórios

```bash
mkdir -p ~/easydoor && cd ~/easydoor
git clone git@git.easydoor.ai:EasyDoor/ed-infra.git
git clone git@git.easydoor.ai:EasyDoor/ed-worker.git
git clone git@git.easydoor.ai:EasyDoor/ed-raspadinha.git
```

### 2. Configurar as variáveis de ambiente

```bash
cd ed-infra
cp .env.worker.example .env.worker
# editar .env.worker com a URL da API e a chave
```

`.env.worker`:
```env
API_URL=https://api.easydoor.ai   # ou http://<IP-DO-PC>:8000 para rede local
API_TOKEN=<token-de-autenticacao>
WORKER_API_KEY=<chave-segura>
WORKER_MAX_TOTAL=2
WORKER_HEADLESS=1
```

### 3. Buildar e subir

O build baixa o Firefox (~500 MB) — só precisa rodar uma vez:

```bash
make worker-build
make worker-up
make worker-logs
```

## Operação diária

```bash
make worker-up       # Sobe o worker
make worker-down     # Para o worker
make worker-restart  # Reinicia sem rebuild
make worker-logs     # Acompanha logs em tempo real
```

## Atualizar após deploy do servidor

Quando o servidor é atualizado, o worker recebe `409 Conflict` e para automaticamente.
Para atualizar, a partir do **PC principal**:

```bash
# Atualiza um worker remoto específico via SSH (pull + restart)
cd ../ed-worker
make update HOST=nome-do-host
```

Ou manualmente na máquina remota:

```bash
cd ~/easydoor/ed-infra
git pull --rebase gitea master
cd ../ed-worker && git pull --rebase gitea master
cd ../ed-raspadinha && git pull --rebase gitea master
cd ../ed-infra && make worker-rebuild
```

## Sincronização de versão

O worker tem `WORKER_VERSION` tatuada na imagem no momento do build (hash do git de `ed-infra`). Se a versão do worker divergir do servidor após um deploy:

1. O servidor rejeita o worker com `409 Conflict`
2. O worker loga `[WARN] Worker desatualizado...` e para o polling
3. O processo encerra limpo — o container reinicia automaticamente (via `restart: unless-stopped`) e volta a tentar conectar

Para ver a versão atual:
```bash
docker inspect easydoor-worker | grep WORKER_VERSION
```

## Testes

### Testar se o Firefox raspa corretamente

```bash
make worker-test robo=vivareal logradouro="Rua Maria Müller Gieseler" bairro="Velha" localidade="Blumenau" uf=SC
```

Se retornar uma lista de anúncios em JSON, o Firefox e a conexão com a API estão funcionando.

## Ajuste de paralelismo

`WORKER_MAX_TOTAL` controla quantos Firefoxs rodam simultaneamente no container.
Ajustar conforme a capacidade da máquina:

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

Verificar os logs:
```bash
make worker-logs
```

- `[WARN] Worker desatualizado` → versão desatualizada, rode `make worker-rebuild`
- `Erro: variável de ambiente WORKER_VERSION é obrigatória` → imagem buildada sem o build arg; rode `make worker-rebuild`
- Erro de conexão HTTP → verificar `API_URL` e `WORKER_API_KEY` no `.env.worker`

### Firefox trava ou não abre

Verificar se o container tem memória compartilhada suficiente:
```bash
docker exec easydoor-worker df -h /dev/shm
```
Deve mostrar `2.0G`. Se não mostrar, o `shm_size: 2gb` não está sendo aplicado.
