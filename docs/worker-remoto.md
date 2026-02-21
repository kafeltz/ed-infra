# Manual: Worker Remoto

Guia para instalar e operar o `ed-worker` em máquinas remotas, sem precisar
subir toda a infra (banco, Redis, frontends).

## Como funciona

O worker roda isolado em Docker e se conecta ao servidor principal via
**SSH tunnel**. O tunnel mapeia as portas do Redis e do PostgreSQL para o
`localhost` da máquina remota, e o container enxerga esse `localhost` graças
ao `network_mode: host`.

```
Máquina remota                         Servidor principal
┌─────────────────────────┐            ┌─────────────────────┐
│  easydoor-worker        │            │  easydoor-db  :5432 │
│  (Docker, host network) │            │  easydoor-redis:6379│
│                         │  SSH tunnel│                     │
│  localhost:5432 ────────┼────────────┼──▶ PostgreSQL       │
│  localhost:6379 ────────┼────────────┼──▶ Redis            │
│                         │            │                     │
│  Firefox (headless)     │            │                     │
└─────────────────────────┘            └─────────────────────┘
```

## Pré-requisitos

- Docker instalado na máquina remota
- Acesso SSH ao servidor principal
- Repositórios clonados lado a lado:

```
~/projects/easydoor/
├── ed-infra/        ← este repo
└── ed-raspadinha/   ← necessário para o build da imagem
```

## Instalação

### 1. Clonar os repositórios

```bash
mkdir -p ~/projects/easydoor && cd ~/projects/easydoor
git clone git@git.easydoor.ai:EasyDoor/ed-infra.git
git clone git@git.easydoor.ai:EasyDoor/ed-raspadinha.git
```

### 2. Configurar as variáveis de ambiente

```bash
cd ed-infra
cp .env.worker.example .env.worker
```

Editar `.env.worker` se as portas do tunnel forem diferentes das padrão:

```env
DATABASE_URL=postgresql://easydoor:SENHA@localhost:5432/easydoor
REDIS_URL=redis://localhost:6379/0
WORKER_MAX_TOTAL=3
WORKER_HEADLESS=1
```

### 3. Buildar a imagem

O build baixa o Firefox (~700MB) — só precisa rodar uma vez:

```bash
make worker-build
```

## Operação diária

### Abrir o SSH tunnel (antes de subir o worker)

```bash
ssh -N \
  -L 5432:localhost:5432 \
  -L 6379:localhost:6379 \
  usuario@servidor-principal
```

Dica: rodar em background com `ssh -fN ...` ou usar um serviço systemd.

### Subir o worker

```bash
make worker-up
```

### Acompanhar logs

```bash
make worker-logs
```

### Parar o worker

```bash
make worker-down
```

### Reiniciar

```bash
make worker-restart
```

## Testes

### Testar se o Firefox abre e raspa corretamente

```bash
make worker-test robo=vivareal logradouro="Rua Maria Müller Gieseler" bairro="Velha" localidade="Blumenau" uf=SC
```

Se retornar uma lista de anúncios em JSON, o Firefox e o tunnel estão funcionando.

### Verificar se o worker está conectado ao Redis e ao Postgres

```bash
make worker-logs
```

Deve aparecer na inicialização:
```
Conectado ao Redis.
Heartbeat ativo: easydoor:worker:<hostname> (TTL 60s)
```

## Ajuste de paralelismo

`WORKER_MAX_TOTAL` controla quantos Firefoxs rodam simultaneamente no container.
Ajustar conforme a capacidade da máquina:

| RAM disponível | WORKER_MAX_TOTAL recomendado |
|---|---|
| 4 GB | 1–2 |
| 8 GB | 3–4 |
| 16 GB | 5–8 |

Após alterar, recriar o container:

```bash
make worker-restart
```

## Troubleshooting

### Worker não conecta ao Redis/Postgres

Verificar se o tunnel está ativo:
```bash
nc -zv localhost 5432   # deve dizer "open"
nc -zv localhost 6379
```

### Firefox trava ou não abre

Verificar se o container tem memória compartilhada suficiente:
```bash
docker exec easydoor-worker df -h /dev/shm
```
Deve mostrar `2.0G`. Se não mostrar, o `shm_size: 2gb` não está sendo aplicado.

### Rebuild após atualização de código

```bash
git pull
make worker-build
make worker-restart
```
