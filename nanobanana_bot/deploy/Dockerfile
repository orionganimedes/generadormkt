# Alternativa a systemd. El contexto de build es la raíz del repositorio:
#   docker build -f nanobanana_bot/deploy/Dockerfile -t nanobanana-bot .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN groupadd --system bot && useradd --system --gid bot --home-dir /app bot

COPY nanobanana_bot/requirements.txt /app/nanobanana_bot/requirements.txt
RUN pip install --no-cache-dir -r /app/nanobanana_bot/requirements.txt

COPY --chown=bot:bot nanobanana_bot /app/nanobanana_bot

USER bot
CMD ["python", "-m", "nanobanana_bot.bot"]
