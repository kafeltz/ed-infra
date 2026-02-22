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
