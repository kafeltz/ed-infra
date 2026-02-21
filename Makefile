up:
	docker compose up -d

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
