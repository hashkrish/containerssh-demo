FROM python:3.11-slim AS base

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py /app/app.py

# Test stage - includes test dependencies
FROM base AS test

RUN pip install --no-cache-dir pytest pytest-cov flask-testing

COPY tests/ /app/tests/

# Production stage
FROM base AS production

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app", "--workers", "2", "--timeout", "30", "--access-logfile", "-"]
