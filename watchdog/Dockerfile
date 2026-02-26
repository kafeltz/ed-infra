FROM python:3.12-slim

WORKDIR /app

COPY ed-watchdog/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ed-watchdog/watchdog.py .

CMD ["python", "-u", "watchdog.py"]
