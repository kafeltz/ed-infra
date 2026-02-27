# Diário de Dificuldades e Soluções — ed-infra

Registro de problemas encontrados durante o desenvolvimento/operação desta infraestrutura e como foram resolvidos.

---

## 2026-02-22 — Migração Redis → HTTP (remoção do Redis)

### Contexto
Remoção completa do Redis do `docker-compose.yml` como parte da migração do worker para comunicação exclusiva via HTTP com a API. Ver plano completo em `/home/ismael/.claude/plans/joyful-rolling-ember.md`.

---

### Problema 1: `make up` travava em "Aguardando PostgreSQL aceitar conexões TCP..."

**Sintoma:** O target `up` do Makefile entrava em loop infinito tentando conectar ao PostgreSQL.

**Causa:** O Makefile tinha a porta `5432` hardcoded, mas o `docker-compose.yml` expõe o PostgreSQL no host pela porta `5434` (`5434:5432`).

**Solução:** Corrigir todas as ocorrências no Makefile de `-p 5432` para `-p 5434`, incluindo o loop de espera, a criação do banco e o target `psql`.

---

### Problema 2: Containers na mesma rede Docker não conseguiam se comunicar

**Sintoma:** O NGINX não conseguia alcançar nenhum outro container (`ed-admin`, `ed-frontend-app`, `ed-calibrador`, `ed-backend-api`). Todas as conexões resultavam em timeout. Ping entre containers retornava 100% de perda de pacotes.

**Diagnóstico:**
- UFW estava inativo (não era a causa)
- `iptables -L FORWARD` mostrava `policy DROP` com apenas as chains `DOCKER-USER` e `DOCKER-FORWARD`
- Docker versão 28.4.0 (versão recente com mudanças no gerenciamento de iptables)
- O container `easydoor-redis` da execução anterior (21 horas antes) ainda estava rodando, possivelmente deixando a rede em estado inconsistente

**Causa provável:** Regras iptables da rede `ed-infra_default` desincronizadas — combinação do Docker 28 com containers residuais de execução anterior.

**Solução:**
```bash
docker stop easydoor-redis && docker rm easydoor-redis  # remover container obsoleto
make down && make up  # recriar rede e containers do zero
```
O `docker compose down` remove os containers **e a rede Docker**, forçando o Docker a recriar as regras iptables do zero no próximo `up`.

---

### Problema 3: Vite preview retornava 403 Forbidden via NGINX

**Sintoma:** Após resolver a conectividade de rede, o NGINX conseguia alcançar os containers dos frontends, mas recebia `403 Forbidden`.

**Causa:** Vite 5+ implementou validação do header `Host` nas requisições. O NGINX estava configurado com `proxy_set_header Host $host`, que repassa o host original da requisição do cliente (ex: `localhost:4176`). O Vite rejeita hosts que não estejam na sua lista de permitidos.

**Solução:** Nos blocos `location /` do `nginx.conf` que fazem proxy para os frontends Vite, substituir `proxy_set_header Host $host` por `proxy_set_header Host "localhost"` — o Vite sempre aceita `localhost` como host válido.

```nginx
# Antes (causava 403)
proxy_set_header Host $host;

# Depois (funciona)
proxy_set_header Host "localhost";
```

Aplicado nos três frontends: `ed-frontend-app`, `ed-admin`, `ed-calibrador`.

---

## 2026-02-27 — Containers sem comunicação de rede (iptables-nft vs iptables-legacy)

### Sintoma

Frontend acessível diretamente pelo IP do container (`172.20.0.x:4175`) mas não via `localhost:4175`. NGINX retornava 504 Gateway Timeout. Ping entre containers na mesma rede resultava em 100% de perda de pacotes.

### Diagnóstico

1. `docker compose ps` confirmou que o NGINX estava com binding correto (`0.0.0.0:4174-4176`)
2. `docker exec easydoor-nginx ping ed-frontend-app` → 100% packet loss (mesmo estando na mesma rede `ed-infra_default`)
3. Logs do nginx: `upstream timed out (110: Operation timed out) while connecting to upstream`
4. `iptables --version` revelou: `iptables v1.8.7 (nf_tables)` — sistema usando `iptables-nft`

### Causa

O Docker escreve suas regras de FORWARD e NAT usando `iptables-legacy`, mas o sistema estava configurado para usar `iptables-nft` como backend padrão. As regras escritas pelo Docker ficavam **invisíveis para o kernel** (que lia apenas as regras nftables), então todo tráfego inter-container era silenciosamente descartado.

Isso ocorre em sistemas Ubuntu/Debian modernos onde `update-alternatives` aponta `iptables` para `/usr/sbin/iptables-nft` por padrão.

### Solução

```bash
# Trocar para o backend legacy (que o Docker usa)
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Reiniciar o Docker para recriar as regras no backend correto
sudo systemctl restart docker

# Recriar todos os containers (a rede precisa ser recriada)
docker compose down && docker compose up -d
```

### Como verificar se o problema está ativo

```bash
iptables --version
# Se mostrar "(nf_tables)", o Docker não está conseguindo registrar suas regras
# Se mostrar "(legacy)", está correto
```

---

## 2026-02-27 — 502 Bad Gateway nos frontends após `--force-recreate`

### Sintoma

Após recriar os containers dos frontends (`ed-frontend-app`, `ed-admin`, `ed-calibrador`) com `docker compose up -d --force-recreate`, o NGINX retornava `502 Bad Gateway` para todos eles. Os containers Vite estavam rodando normalmente.

### Diagnóstico

```
[error] connect() failed (111: Connection refused) while connecting to upstream
upstream: "http://172.20.0.2:4176/"
```

O NGINX tentava conectar ao IP antigo do container, mas os IPs haviam mudado após o recreate.

### Causa

O NGINX resolve os hostnames dos `proxy_pass` em tempo de inicialização e cacheia os IPs indefinidamente. Quando containers são recriados e recebem novos IPs via DHCP interno do Docker, o NGINX continua tentando o IP antigo.

### Solução

Adicionar o resolver DNS interno do Docker ao `nginx.conf` e usar variáveis nos `proxy_pass` — isso força o NGINX a re-resolver via DNS a cada `valid=10s` segundos:

```nginx
http {
    resolver 127.0.0.11 valid=10s ipv6=off;

    server {
        location / {
            set $upstream http://ed-frontend-app:4175;
            proxy_pass $upstream;  # variável = resolução dinâmica
        }
    }
}
```

Sem a variável `$upstream`, mesmo com o `resolver` configurado o NGINX ignora o DNS e usa o IP cacheado.

---

## 2026-02-27 — Worker com erro 500: coluna `worker_hostname` ausente

### Sintoma

Container `easydoor-worker` em restart loop. Logs do backend:

```
psycopg.errors.UndefinedColumn: column "worker_hostname" of relation "ceps_cadastrados" does not exist
```

### Causa

O `ed-backend-api` foi atualizado para gravar o hostname do worker na tabela `ceps_cadastrados`, mas a migração correspondente não foi adicionada ao `ed-engine`. Como `make schema` usa `CREATE TABLE IF NOT EXISTS`, ele não altera tabelas existentes — a coluna simplesmente nunca foi criada.

### Solução

```bash
# Aplicar a migração no banco em execução
PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d easydoor \
  -c "ALTER TABLE ceps_cadastrados ADD COLUMN IF NOT EXISTS worker_hostname TEXT;"
```

E atualizar o `sql/schema.sql` do `ed-engine` para incluir a coluna na definição da tabela (para novas instalações).

### Lição

Ao adicionar colunas ao schema via backend, sempre atualizar `ed-engine/sql/schema.sql` **na mesma PR**. O `make schema` é idempotente mas não executa migrações — não há sistema de migrations automático.
