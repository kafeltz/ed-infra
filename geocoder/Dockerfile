FROM python:3.11-slim

WORKDIR /app

COPY ed-geocoder/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ed-geocoder/ .

CMD ["python", "geocoder.py"]
