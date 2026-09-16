FROM python:3.12-slim

ENV PYTHONUNBUFFERED=True
WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./

# Cloud Run sets $PORT (default 8080). uvicorn serves the FastAPI app in main.py.
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1
