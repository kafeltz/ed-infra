.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "Infra EasyDoor"
	@echo ""
	@echo "  Infra principal"
	@echo "    up                 Sobe todos os containers e garante o banco criado"
	@echo "    down               Para todos os containers"
	@echo "    build              Reconstrói todas as imagens"
	@echo "    logs               Acompanha logs em tempo real"
	@echo "    psql               Abre shell psql no banco"
	@echo "    restart-<serviço>  Reinicia um serviço (ex: make restart-db)"
	@echo "    nuke               ⚠  Destrói tudo — containers + dados + logs"
	@echo ""
	@echo "  Worker remoto  (docker-compose.worker.yml + .env.worker)"
	@echo "    worker-build       Builda a imagem do worker (inclui Firefox)"
	@echo "    worker-up          Sobe o worker"
	@echo "    worker-down        Para o worker"
	@echo "    worker-restart     Reinicia o worker sem rebuild"
	@echo "    worker-logs        Acompanha logs do worker em tempo real"
	@echo "    worker-test        Testa o Firefox dentro do container"
	@echo "                       Ex: make worker-test robo=vivareal logradouro=\"Rua X\" bairro=Centro localidade=Blumenau uf=SC"
	@echo ""

up:
	mkdir -p postgres_logs audit_logs data
	chmod 777 postgres_logs audit_logs data
	docker compose up -d
	@echo "Aguardando PostgreSQL aceitar conexões TCP..."
	@until PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres -c "SELECT 1" >/dev/null 2>&1; do sleep 1; done
	@PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='easydoor'" | grep -q 1 || \
		PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres \
		-c "CREATE DATABASE easydoor OWNER easydoor;"
	@echo "Banco pronto."

down:
	docker compose down

build:
	docker compose build

logs:
	docker compose logs -f

psql:
	psql -h localhost -p 5434 -U easydoor -d easydoor

restart-%:
	docker compose restart $*

# ─── Worker remoto ───────────────────────────────────────────────────────────
# Usa docker-compose.worker.yml + .env.worker
# Ver docs/worker-remoto.md para instruções completas.

WORKER_COMPOSE := docker compose -f docker-compose.worker.yml

worker-build:
	$(WORKER_COMPOSE) build

worker-up:
	$(WORKER_COMPOSE) up -d
	@echo "Worker iniciado. Acompanhe com: make worker-logs"

worker-down:
	$(WORKER_COMPOSE) down

worker-restart:
	$(WORKER_COMPOSE) restart ed-worker

worker-logs:
	$(WORKER_COMPOSE) logs -f ed-worker

worker-test:
	@if [ -z "$(robo)" ]; then \
		echo "Uso: make worker-test robo=vivareal logradouro=\"Rua X\" bairro=Centro localidade=Blumenau uf=SC"; \
		exit 1; \
	fi
	docker exec easydoor-worker \
		env RASPADINHA_HEADLESS=1 \
		python -m raspadinha \
		robo=$(robo) \
		$(if $(logradouro),logradouro="$(logradouro)") \
		$(if $(bairro),bairro="$(bairro)") \
		$(if $(localidade),localidade="$(localidade)") \
		$(if $(uf),uf="$(uf)") \
		$(if $(cep),cep="$(cep)")

# ─── Destruição total ─────────────────────────────────────────────────────────

nuke:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║                  ⚠  ATENÇÃO — PONTO SEM VOLTA  ⚠            ║"
	@echo "╠══════════════════════════════════════════════════════════════╣"
	@echo "║  Isso vai DESTRUIR permanentemente:                          ║"
	@echo "║                                                              ║"
	@echo "║   • Todos os containers (db, frontends, backend, worker)     ║"
	@echo "║   • TODOS OS DADOS do PostgreSQL (tabelas, schema, seeds)    ║"
	@echo "║   • Todos os logs                                            ║"
	@echo "║                                                              ║"
	@echo "║  Após isso, rode:  make up && make schema  para recomeçar.   ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@read -p "  Digite DESTRUIR para confirmar: " confirm && [ "$$confirm" = "DESTRUIR" ] || (echo "Cancelado."; exit 1)
	@echo ""
	docker compose down
	rm -rf ./postgres_logs ./audit_logs
	docker run --rm -v "$(PWD)/data:/data" alpine sh -c "rm -rf /data/*"
	@echo ""
	@echo "Tudo destruído. Rode 'make up' para recomeçar do zero."
