FROM python:3.11-slim-bookworm

COPY gitconfig /root/.gitconfig

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl git \
  && rm -rf /var/lib/apt/lists/* \
  && curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/root/.local/bin:$PATH" \
  PYTHONPATH=/app/src \
  PYTHONUNBUFFERED=1 \
  PYTHONDONTWRITEBYTECODE=1

COPY requirements.txt .

# 直接安装到系统依赖中，不创建虚拟环境
RUN uv pip install --system -r requirements.txt

COPY . .

CMD ["uvicorn", "src.main:app", "--workers", "3", "--host", "0.0.0.0", "--port", "20250"]
