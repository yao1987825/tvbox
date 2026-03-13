#!/bin/bash
set -e

echo "Starting services..."

# 启动 Nginx（后台运行）
nginx -g 'daemon off;' &
echo "Nginx started"

# 启动直播源获取（后台运行）
(
    while true; do
        curl -fsSL "${SOURCE_URL:-https://gh-proxy.com/https://raw.githubusercontent.com/yaojiwei520/IPTV/refs/heads/main/iptv.m3u}" -o /data/iptv.m3u.tmp 2>/dev/null && \
        mv /data/iptv.m3u.tmp /data/iptv.m3u && \
        echo "$(date -Iseconds) iptv.m3u updated"
        sleep ${FETCH_INTERVAL:-3600}
    done
) &
echo "Fetcher started"

# 启动测速脚本（后台运行）
python3 /app/scripts/speedtest_v2.py &
echo "Speedtest started"

# 等待任意进程退出
wait
