up:
	mkdir -p postgres_logs audit_logs data redis_data
	chmod 777 postgres_logs audit_logs data redis_data
	docker compose up -d
	@echo "Aguardando PostgreSQL ficar saudável..."
	@until docker inspect --format='{{.State.Health.Status}}' easydoor-db 2>/dev/null | grep -q healthy; do sleep 1; done
	@PGPASSWORD=easydoor psql -h localhost -p 5432 -U easydoor -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='easydoor'" | grep -q 1 || \
		PGPASSWORD=easydoor psql -h localhost -p 5432 -U easydoor -d postgres \
		-c "CREATE DATABASE easydoor OWNER easydoor;"
	@echo "Banco pronto."

down:
	docker compose down

build:
	docker compose build

logs:
	docker compose logs -f

psql:
	psql -h localhost -p 5432 -U easydoor -d easydoor

restart-%:
	docker compose restart $*

nuke:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║                  ⚠  ATENÇÃO — PONTO SEM VOLTA  ⚠            ║"
	@echo "╠══════════════════════════════════════════════════════════════╣"
	@echo "║  Isso vai DESTRUIR permanentemente:                          ║"
	@echo "║                                                              ║"
	@echo "║   • Todos os containers (db, redis, frontends, backend)      ║"
	@echo "║   • TODOS OS DADOS do PostgreSQL (tabelas, schema, seeds)    ║"
	@echo "║   • Todos os dados do Redis                                  ║"
	@echo "║   • Todos os logs                                            ║"
	@echo "║                                                              ║"
	@echo "║  Após isso, rode:  make up && make schema  para recomeçar.   ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@read -p "  Digite DESTRUIR para confirmar: " confirm && [ "$$confirm" = "DESTRUIR" ] || (echo "Cancelado."; exit 1)
	@echo ""
	docker compose down
	rm -rf ./redis_data ./postgres_logs ./audit_logs
	rm -rf ./data
	@echo ""
	@echo "Tudo destruído. Rode 'make up' para recomeçar do zero."
