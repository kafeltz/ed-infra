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

# Instalar ed-raspadinha (repo irmão copiado junto pelo build context)
COPY ed-raspadinha/ /ed-raspadinha/
RUN pip install --no-cache-dir /ed-raspadinha/

# Instalar dependências do worker (sem o -e ../ed-raspadinha, já instalado acima)
COPY ed-worker/requirements.txt .
RUN grep -v 'ed-raspadinha' requirements.txt > /tmp/reqs.txt && \
    pip install --no-cache-dir -r /tmp/reqs.txt

# Baixar o binário do Firefox do Camoufox (baked na imagem)
RUN python -m camoufox fetch

# Código do worker
COPY ed-worker/ .

ENV WORKER_HEADLESS=1
CMD ["python", "worker.py"]
