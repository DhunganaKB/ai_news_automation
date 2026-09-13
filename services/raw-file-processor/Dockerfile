FROM python:3.12-slim

ENV PYTHONUNBUFFERED=True
WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./

# Cloud Run sets $PORT (default 8080). gunicorn serves the Flask app in main.py.
CMD exec gunicorn --bind :${PORT:-8080} --workers 1 --threads 8 --timeout 0 main:app
