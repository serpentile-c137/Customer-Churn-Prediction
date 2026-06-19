FROM python:3.11-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/app/src

# Install build tools only if some Python deps need compilation.
# If your requirements are fully wheels-based, you can remove this block.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy dependency file first for better Docker layer caching
COPY requirements.txt .

# Install dependencies into venv
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

############################
# 2) Runtime stage
############################
FROM python:3.11-slim AS runtime

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PATH="/opt/venv/bin:$PATH"

# Install only runtime OS packages you actually need.
# Keep curl only if needed for healthcheck or MLflow/local tracking use case.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy only the virtualenv from builder
COPY --from=builder /opt/venv /opt/venv

# Copy only required application files instead of COPY . .
# This reduces build context size and prevents accidental bloat.
COPY src /app/src
COPY requirements.txt /app/requirements.txt

# Copy model artifacts explicitly
COPY src/serving/model /app/src/serving/model
COPY src/serving/model/3b1a41221fc44548aed629fa42b762e0/artifacts/model /app/model
COPY src/serving/model/3b1a41221fc44548aed629fa42b762e0/artifacts/feature_columns.txt /app/model/feature_columns.txt
COPY src/serving/model/3b1a41221fc44548aed629fa42b762e0/artifacts/preprocessing.pkl /app/model/preprocessing.pkl

# Create non-root user
RUN addgroup --system app && adduser --system --group app
USER app

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "src.app.main:app", "--host", "0.0.0.0", "--port", "8000"]