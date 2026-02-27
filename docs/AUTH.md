# Autenticação EasyDoor — Keycloak

Manual de referência para humanos e IAs.

## Arquitetura

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Frontend   │────>│   Keycloak   │     │   Backend    │
│  (React SPA) │<────│  (IdP/Auth)  │     │  (FastAPI)   │
│  :5173/:4175 │     │    :8080     │     │    :8000     │
└──────┬───────┘     └──────────────┘     └──────┬───────┘
       │                                         │
       │  Bearer JWT ──────────────────────────> │
       │                                         │
       │                  JWKS (public keys) <───│
       │                                         │
       └─────── /api/* (proxy nginx) ───────────>│
```

**Fluxo:**
1. Usuário acessa o frontend
2. Frontend faz `check-sso` silencioso via iframe
3. Se não autenticado, redireciona para Keycloak login
4. Keycloak autentica e redireciona de volta com code (PKCE S256)
5. Frontend troca code por token JWT
6. Cada chamada à API inclui `Authorization: Bearer <jwt>`
7. Backend valida JWT usando chaves públicas JWKS do Keycloak

## Componentes

### Keycloak (IdP)

| Item | Valor |
|------|-------|
| Imagem | `quay.io/keycloak/keycloak:26.1` |
| Porta | 8080 |
| Admin console | `http://localhost:8080/admin` |
| Realm | `easydoor` |
| Client ID | `easydoor-frontend` (public, PKCE S256) |
| Banco | PostgreSQL `keycloak` (mesmo servidor, banco separado) |

**Usuários pré-configurados:**

| Username | Senha | Roles | Temporária? |
|----------|-------|-------|-------------|
| admin | EasyDoor@2024 | admin, avaliador | Não |
| ismael | EasyDoor@2024 | admin, avaliador | Não |
| demo | demo123 | avaliador, viewer | Sim (troca no 1o login) |

### Backend (FastAPI)

**Arquivo:** `ed-backend-api/auth.py`

Dependências FastAPI reutilizáveis:
- `require_auth` — exige JWT válido, retorna `TokenPayload`
- `optional_auth` — aceita anônimo, retorna `TokenPayload | None`

**Rotas protegidas (`require_auth`):**

| Router | Motivo |
|--------|--------|
| `avaliar.py` | Core do produto |
| `avaliacoes.py` | Histórico do usuário |
| `comparaveis.py` | Dados proprietários |
| `dados_regiao.py` | Consumo de recursos |
| `premissas.py` | Configuração do pipeline |

**Rotas públicas (sem auth):**

| Router | Motivo |
|--------|--------|
| `enderecos.py` | Autocomplete público |
| `ceps.py` | Busca pública |
| `worker.py` | Já usa `WORKER_API_KEY` |
| `/health` | Health check |

**Variáveis de ambiente:**
```
KEYCLOAK_URL=http://keycloak:8080          # URL interna Docker (para buscar JWKS)
KEYCLOAK_ISSUER_URL=http://localhost:8080  # URL que o browser vê (para validar issuer do JWT)
KEYCLOAK_REALM=easydoor
KEYCLOAK_CLIENT_ID=easydoor-frontend
```

**Nota importante**: `KEYCLOAK_URL` e `KEYCLOAK_ISSUER_URL` são diferentes porque o backend
acessa o Keycloak pela rede Docker (`keycloak:8080`), mas os tokens JWT são emitidos com o
issuer baseado em `KC_HOSTNAME` (a URL que o browser vê). Se forem iguais, a validação falha.

### Frontend (React)

**Arquivos-chave:**

| Arquivo | Função |
|---------|--------|
| `src/lib/keycloak.ts` | Instância singleton `keycloak-js` |
| `src/contexts/AuthContext.tsx` | Provider React com estado de auth |
| `src/components/ProtectedRoute.tsx` | Wrapper que redireciona para login |
| `src/api/client.ts` | `apiFetch()` com Bearer token automático |
| `public/silent-check-sso.html` | iframe para check-sso silencioso |

**Interface pública do `useAuth()`:**
```typescript
{
  autenticado: boolean;
  usuario: { nome: string; email: string } | null;
  login: () => void;      // redireciona para Keycloak
  logout: () => void;     // redireciona para Keycloak logout
  token: string | undefined;
  inicializado: boolean;
}
```

**Variáveis Vite (build-time):**
```
VITE_KEYCLOAK_URL=http://localhost:8080
VITE_KEYCLOAK_REALM=easydoor
VITE_KEYCLOAK_CLIENT_ID=easydoor-frontend
```

## Operações

### Subir tudo (primeira vez)

```bash
cd ed-infra

# 1. Criar banco keycloak (se ainda não existe)
make db-keycloak

# 2. Build e subir todos os containers
make rebuild

# 3. Aplicar schema do banco easydoor
cd ../ed-engine && make schema
```

### Dev local (sem Docker para frontend/backend)

```bash
cd ed-infra && make dev-up    # sobe banco + keycloak

# Em outro terminal:
cd ed-backend-api && make dev  # backend :8000

# Em outro terminal:
cd ed-frontend-app && npm run dev  # frontend :5173
```

### Verificar se Keycloak está saudável

```bash
curl -sf http://localhost:8080/health/ready
# {"status":"UP","checks":[...]}
```

### Obter token manualmente (para testar backend)

```bash
TOKEN=$(curl -s -X POST \
  'http://localhost:8080/realms/easydoor/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' \
  -d 'client_id=easydoor-frontend' \
  -d 'username=ismael' \
  -d 'password=EasyDoor@2024' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Testar rota protegida
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/v1/avaliacoes
```

### Invalidar cache JWKS do backend

Se rotacionar chaves no Keycloak, reiniciar o backend:
```bash
docker compose restart ed-backend-api
```

O cache JWKS também é invalidado automaticamente quando a validação falha
(tenta buscar novas chaves antes de retornar 401).

## Troubleshooting

### "Serviço de autenticação indisponível" (503)

O backend não consegue acessar o JWKS do Keycloak.
- Verificar se o container `easydoor-keycloak` está rodando: `docker ps`
- Verificar se o healthcheck está passando: `docker inspect easydoor-keycloak --format '{{.State.Health.Status}}'`
- Verificar conectividade: `docker exec easydoor-backend-api python -c "import httpx; print(httpx.get('http://keycloak:8080/realms/easydoor').status_code)"`

### Healthcheck do Keycloak

O Keycloak 26 expõe health na **porta 9000** (management), não na 8080.
A imagem UBI não tem `curl`, então o healthcheck usa `bash /dev/tcp`.
Se o healthcheck falhar, verificar logs: `docker logs easydoor-keycloak`

### "Token inválido ou expirado" (401)

- Token expirou (lifetime padrão: 5 min). Frontend renova automaticamente via `updateToken(70)`.
- Se persistir, verificar se relógios dos containers estão sincronizados.

### Frontend fica em loop de redirect

- Verificar se `redirectUris` no realm JSON inclui a URL do frontend.
- Verificar se `VITE_KEYCLOAK_URL` aponta para URL acessível **pelo browser** (não URL interna Docker).
- Para dev local: `VITE_KEYCLOAK_URL=http://localhost:8080` (não `http://keycloak:8080`).

### Keycloak não importa o realm

- O import só acontece na **primeira vez** que o container sobe (banco vazio).
- Para reimportar: dropar o banco `keycloak`, recriar e reiniciar:
  ```bash
  PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres \
    -c "DROP DATABASE keycloak; CREATE DATABASE keycloak OWNER easydoor;"
  docker compose restart keycloak
  ```

### Container do Keycloak demora para iniciar

Normal. O `start_period: 60s` no healthcheck dá tempo para a JVM iniciar.
Primeira inicialização pode levar 1-2 minutos (build do quarkus + import do realm).

## Segurança

- **PKCE S256**: protege contra interceptação do authorization code
- **Public client**: sem client secret (SPA não consegue guardar segredos)
- **check-sso silencioso**: verifica sessão sem redirecionar (UX suave)
- **Token rotation**: backend tenta renovar JWKS automaticamente em caso de falha
- **Brute force protection**: habilitado no realm (Keycloak bloqueia após tentativas falhas)

## Deploy em Stage/HML

No servidor de stage, o `.env` deve ter:

```env
KC_HOSTNAME=stageauth.easydoor.ai
VITE_KEYCLOAK_URL=https://stageauth.easydoor.ai
```

Além disso, criar um vhost NGINX externo para `stageauth.easydoor.ai` que faz
proxy para `localhost:8080` (Keycloak):

```nginx
server {
    listen 443 ssl;
    server_name stageauth.easydoor.ai;

    ssl_certificate /etc/letsencrypt/live/easydoor.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/easydoor.ai/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
}
```

E adicionar `https://stageauth.easydoor.ai` nos `redirectUris` e `webOrigins`
do realm se necessário (já estão configurados para `https://stage.easydoor.ai`).

## Referência para IAs

Ao trabalhar com autenticação neste projeto:

1. **Nunca remover** `Depends(require_auth)` de rotas protegidas sem pedir ao usuário
2. **Rotas novas** no backend que acessam dados de usuário devem usar `require_auth`
3. **Rotas novas** puramente públicas (sem dados sensíveis) não precisam de auth
4. **Frontend**: todo componente dentro de `ProtectedRoute` pode assumir que `autenticado === true`
5. **client.ts**: já injeta Bearer token automaticamente — não duplicar
6. **Keycloak admin**: `http://localhost:8080/admin` — usar para gerenciar usuários, ver sessões
7. **Variáveis Docker vs Browser**: `KEYCLOAK_URL` (backend, rede Docker) ≠ `VITE_KEYCLOAK_URL` (browser, localhost)
