.DEFAULT_GOAL := help

# Versão atual: hash curto do git (ex: a1b2c3d). Exportada para docker compose
# usar no build arg de SERVER_VERSION.
APP_VERSION := $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
export APP_VERSION

REGISTRY := docker.easydoor.ai/easydoor
SERVICES_VERSIONED := ed-backend-api ed-worker ed-geocoder ed-watchdog \
                      ed-frontend-app ed-admin ed-calibrador
SERVICES_STABLE := ed-postgres ed-keycloak

help:
	@echo ""
	@echo "Infra EasyDoor"
	@echo ""
	@echo "  Desenvolvimento local"
	@echo "    dev-up             Sobe banco (5433) + Keycloak (10082) para dev local"
	@echo "    dev-down           Para o banco de dev"
	@echo "    dev-psql           Abre shell psql no banco de dev"
	@echo "    dev-sync           Copia dados de produção para o banco dev local"
	@echo ""
	@echo "  Infra local"
	@echo "    up                 Sobe todos os containers e garante os bancos criados"
	@echo "    down               Para todos os containers"
	@echo "    logs               Acompanha logs em tempo real"
	@echo "    psql               Abre shell psql no banco"
	@echo "    restart-<serviço>  Reinicia um serviço (ex: make restart-db)"
	@echo "    nuke               ⚠  Destrói tudo — containers + dados + logs"
	@echo ""
	@echo "  Worker remoto  (docker-compose.worker.yml + .env.worker)"
	@echo "    worker-up          Sobe o worker"
	@echo "    worker-down        Para o worker"
	@echo "    worker-restart     Reinicia o worker sem rebuild"
	@echo "    worker-logs        Acompanha logs do worker em tempo real"
	@echo "    worker-test        Testa o Firefox dentro do container"
	@echo "                       Ex: make worker-test robo=vivareal logradouro=\"Rua X\" bairro=Centro localidade=Blumenau uf=SC"
	@echo "    worker-update      Puxa imagem latest do registry e reinicia se necessário"
	@echo "    worker-autoupdate-install    Instala cronjob de atualização automática (5 min)"
	@echo "    worker-autoupdate-uninstall  Remove o cronjob"
	@echo ""
	@echo "  Build e Registry (docker.easydoor.ai)"
	@echo "    build              Builda todas as imagens"
	@echo "    rebuild            Builda e recria os containers"
	@echo "    push               Envia imagens buildadas para o registry"
	@echo "    build-push         Builda e envia todas as imagens"
	@echo "    worker-build       Builda a imagem do worker"
	@echo "    worker-rebuild     Builda e recria o container do worker"
	@echo ""

# ─── Desenvolvimento local ────────────────────────────────────────────────────
# Sobe banco (porta 5433) + Keycloak (porta 10082).
# Coexiste com o ambiente de produção local (porta 5432/5434).
# Backend e frontend rodam nativamente no Linux (sem Docker).

DEV_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.dev.yml

.PHONY: dev-up dev-down dev-psql

dev-up:
	mkdir -p postgres_logs audit_logs data
	chmod 777 postgres_logs audit_logs data
	$(DEV_COMPOSE) up -d db
	@echo "Aguardando PostgreSQL aceitar conexões..."
	@until PGPASSWORD=easydoor psql -h localhost -p 5433 -U easydoor -d easydoor -c "SELECT 1" >/dev/null 2>&1; do sleep 1; done
	@PGPASSWORD=easydoor psql -h localhost -p 5433 -U easydoor -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='keycloak'" | grep -q 1 || \
		PGPASSWORD=easydoor psql -h localhost -p 5433 -U easydoor -d postgres \
		-c "CREATE DATABASE keycloak OWNER easydoor;"
	$(DEV_COMPOSE) up -d keycloak
	@echo "Aguardando Keycloak ficar pronto..."
	@until curl -sf http://localhost:10082/health/ready >/dev/null 2>&1; do sleep 2; done
	@echo ""
	@echo "Banco dev pronto em localhost:5433"
	@echo "Keycloak dev pronto em http://localhost:10082"
	@echo "  Admin console: http://localhost:10082/admin  (admin / EasyDoor@2024)"
	@echo ""
	@echo "Agora rode em terminais separados:"
	@echo "  cd ../ed-backend-api && PSQL_CMD='psql -h localhost -p 5433 -U easydoor -d easydoor' make migrate"
	@echo "  cd ../ed-backend-api && DATABASE_URL=postgresql://easydoor:easydoor@localhost:5433/easydoor make dev"
	@echo "  cd ../ed-frontend-app && npm run dev"

dev-down:
	$(DEV_COMPOSE) down

dev-psql:
	PGPASSWORD=easydoor psql -h localhost -p 5433 -U easydoor -d easydoor

dev-sync: ## Copia dados de produção para o banco dev local
	./scripts/sync-prod-to-dev.sh

# ─── Infra local ──────────────────────────────────────────────────────────────

up:
	mkdir -p postgres_logs audit_logs data
	chmod 777 postgres_logs audit_logs data
	docker compose up -d --remove-orphans --force-recreate
	@echo "Aguardando PostgreSQL aceitar conexões TCP..."
	@until PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres -c "SELECT 1" >/dev/null 2>&1; do sleep 1; done
	@PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='easydoor'" | grep -q 1 || \
		PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres \
		-c "CREATE DATABASE easydoor OWNER easydoor;"
	@PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='keycloak'" | grep -q 1 || \
		PGPASSWORD=easydoor psql -h localhost -p 5434 -U easydoor -d postgres \
		-c "CREATE DATABASE keycloak OWNER easydoor;"
	@echo "Bancos prontos (easydoor + keycloak)."

down:
	docker compose down

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

worker-up:
	$(WORKER_COMPOSE) pull
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

# ─── Build e Registry ──────────────────────────────────────────────────────

build:
	cp -f .dockerignore ../
	@echo "Buildando com APP_VERSION=$(APP_VERSION)"
	docker compose build

rebuild:
	cp -f .dockerignore ../
	@echo "Buildando com APP_VERSION=$(APP_VERSION)"
	docker compose build
	docker compose up -d --force-recreate

push:
	@echo "Push de imagens para $(REGISTRY) com tag $(APP_VERSION)..."
	@for svc in $(SERVICES_VERSIONED); do \
		docker tag $(REGISTRY)/$$svc:$(APP_VERSION) $(REGISTRY)/$$svc:latest 2>/dev/null || true; \
		docker push $(REGISTRY)/$$svc:$(APP_VERSION); \
		docker push $(REGISTRY)/$$svc:latest; \
	done
	@for svc in $(SERVICES_STABLE); do \
		docker push $(REGISTRY)/$$svc:latest; \
	done

worker-build:
	cp -f .dockerignore ../
	@echo "Buildando worker com APP_VERSION=$(APP_VERSION)"
	$(WORKER_COMPOSE) build

worker-rebuild:
	cp -f .dockerignore ../
	@echo "Buildando worker com APP_VERSION=$(APP_VERSION)"
	$(WORKER_COMPOSE) build
	$(WORKER_COMPOSE) up -d --force-recreate

worker-update:
	bash scripts/worker-autoupdate.sh

AUTOUPDATE_SCRIPT := $(CURDIR)/scripts/worker-autoupdate.sh
AUTOUPDATE_LOG    := /tmp/worker-autoupdate.log
AUTOUPDATE_CRON   := */5 * * * * bash $(AUTOUPDATE_SCRIPT) >> $(AUTOUPDATE_LOG) 2>&1

worker-autoupdate-install:
	@( crontab -l 2>/dev/null | grep -v worker-autoupdate.sh ; echo "$(AUTOUPDATE_CRON)" ) | crontab -
	@echo "Cronjob instalado. Verifique com: crontab -l"

worker-autoupdate-uninstall:
	@crontab -l 2>/dev/null | grep -v worker-autoupdate.sh | crontab -
	@echo "Cronjob removido."

build-push: build push

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
