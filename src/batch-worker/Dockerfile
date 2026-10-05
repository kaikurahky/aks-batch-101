FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py .

RUN useradd --create-home --uid 10001 worker
USER 10001

ENTRYPOINT ["python", "/app/worker.py"]

