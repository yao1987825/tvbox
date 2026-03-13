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

## 问题 3: 端口 80 被占用

### 错误信息
```
[emerg] bind() to 0.0.0.0:80 failed (98: Address in use)
```

### 原因
- 服务器上已有其他 nginx 容器占用端口 80

### 解决方案
使用端口映射或修改为使用其他端口：

```bash
# 使用 5353 端口映射
docker run -d -p 5353:80 ...
```

### 状态
- [x] 已解决（使用端口 5353）

## 问题 4: 测速脚本找不到

### 错误信息
```
python3: can't open file '/app/scripts/speedtest_v2.py': [Errno 2] No such file or directory
```

### 原因
- iptv-speedtest 镜像里没有包含测速脚本
- 需要从 GitHub 克隆脚本到本地

### 解决方案
在部署时克隆脚本：

```bash
cd /var/lib/docker/iptv-speedtest
git clone https://github.com/yao1987825/iptv-speedtest.git temp
cp temp/scripts/*.py scripts/
rm -rf temp
```

然后挂载脚本目录：

```bash
docker run -v /var/lib/docker/iptv-speedtest/scripts:/app/scripts:ro ...
```

### 状态
- [x] 已解决
