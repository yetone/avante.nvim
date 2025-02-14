FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/root/.local/bin:$PATH"

RUN uv python install 3.11

RUN uv python list

ENV PATH="/root/.uv/python/3.11/bin:$PATH"

COPY requirements.txt .

RUN uv venv --python 3.11

RUN uv pip install -r requirements.txt

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

EXPOSE ${PORT}

COPY . .

CMD ["bash", "-c", "source .venv/bin/activate && uvicorn src.main:app --host 0.0.0.0 --port ${PORT}"]
