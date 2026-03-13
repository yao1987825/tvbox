FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/update_tvbox.sh /app/
RUN chmod +x /app/update_tvbox.sh

ENV DATA_DIR=/data
ENV GITHUB_RAW=https://raw.githubusercontent.com/qist/tvbox/master

CMD ["/app/update_tvbox.sh"]
