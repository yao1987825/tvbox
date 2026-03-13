# TVBox 服务器部署问题记录

## 问题 1: 容器启动后不断重启

### 原因
- Docker 镜像的 ENTRYPOINT 配置问题
- 镜像运行的是 `update_tvbox.sh` 脚本，执行完成后就退出了
- 需要同时启动多个服务：Nginx、直播源获取、测速脚本

### 解决方案
修改 `docker-entrypoint.sh`，同时启动所有服务：

```bash
#!/bin/bash
set -e

echo "Starting services..."

# 启动 Nginx
nginx -g 'daemon off;' &

# 启动直播源获取
(
    while true; do
        curl -fsSL "${SOURCE_URL}" -o /data/iptv.m3u.tmp && \
        mv /data/iptv.m3u.tmp /data/iptv.m3u
        sleep ${FETCH_INTERVAL:-3600}
    done
) &

# 启动测速脚本
python3 /app/scripts/speedtest_v2.py &

wait
```

### 状态
- [x] 已修复代码
- [ ] 等待 GitHub Actions 自动构建新镜像

## 问题 2: Nginx 可执行文件未找到

### 原因
- 旧版镜像没有正确安装 Nginx

### 解决方案
确保 Dockerfile 正确安装 nginx：

```dockerfile
RUN apt-get update && apt-get install -y \
    curl \
    nginx \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*
```

### 状态
- [x] 已修复 Dockerfile
- [ ] 等待重新构建镜像
