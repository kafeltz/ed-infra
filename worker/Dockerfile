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
# Copiar apenas os metadados de dependências, não o código-fonte.
# Assim o pip install + camoufox fetch ficam em cache enquanto as
# dependências não mudarem.

COPY ed-raspadinha/pyproject.toml /ed-raspadinha/pyproject.toml
COPY ed-raspadinha/raspadinha/__init__.py /ed-raspadinha/raspadinha/__init__.py
RUN pip install --no-cache-dir /ed-raspadinha/

COPY ed-worker/requirements.txt .
RUN grep -v 'ed-raspadinha' requirements.txt > /tmp/reqs.txt && \
    pip install --no-cache-dir -r /tmp/reqs.txt

# ── Camada 2: binário do Firefox (~500 MB, muda quase nunca) ────
RUN python -m camoufox fetch

# ── Camada 3: código-fonte (muda frequentemente) ────────────────
# Invalidar aqui NÃO rebaixa as camadas acima.
COPY ed-raspadinha/ /ed-raspadinha/
RUN pip install --no-cache-dir --no-deps /ed-raspadinha/

COPY ed-worker/ .

ENV WORKER_HEADLESS=1
CMD ["python", "worker.py"]
