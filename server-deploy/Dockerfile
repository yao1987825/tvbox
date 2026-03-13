FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl \
    nginx \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/scripts /data /var/cache/nginx /var/log/nginx

COPY scripts/speedtest_v2.py /app/scripts/
COPY scripts/speedtest_cleaner.py /app/scripts/
RUN chmod +x /app/scripts/*.py || true

ENV PYTHONUNBUFFERED=1
ENV TZ=Asia/Shanghai
ENV TEST_INTERVAL=180
ENV TEST_TIMEOUT=5

EXPOSE 80

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "/app/scripts/speedtest_v2.py"]
