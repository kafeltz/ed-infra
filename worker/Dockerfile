FROM python:3.11-slim

# Dependências de sistema para o Firefox headless (Camoufox)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpangocairo-1.0-0 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libnss3 \
    libxss1 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    fonts-liberation \
    xvfb \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Camada 1: dependências Python (muda raramente) ──────────────
# Copiar apenas o requirements.txt antes do código-fonte para que
# o pip install fique em cache enquanto as dependências não mudarem.
COPY ed-worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Camada 2: binário do Firefox (~500 MB, muda quase nunca) ────
# Fallback --no-mmdb caso o repositório GeoLite2 esteja indisponível (erro 500).
RUN python -m camoufox fetch || python -m camoufox fetch --no-mmdb

# ── Camada 3: código-fonte (muda frequentemente) ────────────────
# raspadinha/ agora está dentro de ed-worker/ — não precisa de repo separado.
COPY ed-worker/ .

ENV WORKER_HEADLESS=1
CMD ["python", "worker.py"]
