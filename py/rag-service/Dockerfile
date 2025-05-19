FROM python:3.11-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl git \
  && rm -rf /var/lib/apt/lists/* \
  && curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/root/.local/bin:$PATH" \
  PYTHONUNBUFFERED=1 \
  PYTHONDONTWRITEBYTECODE=1

COPY requirements.txt .

# 直接安装到系统依赖中，不创建虚拟环境
RUN uv pip install --system -r requirements.txt

COPY . .

CMD ["uv", "run", "fastapi", "run", "src/main.py", "--workers", "3", "--port", "20250"]
