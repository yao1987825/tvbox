# TVBox 服务器部署指南

本项目用于在私有服务器上部署 TVBox 配置自动更新服务。

## 功能说明

- 自动从 GitHub (qist/tvbox) 获取最新的点播源配置
- 保留本地测速后的直播源 (tvbox.m3u)
- 包含音乐 MTV 源
- 每天自动更新

## 目录结构

```
server-deploy/
├── docker-compose/
│   ├── docker-compose.yml    # Docker Compose 配置
│   ├── nginx/
│   │   └── default.conf     # Nginx 配置
│   ├── data/                # 数据目录（部署时自动创建）
│   └── scripts/              # 脚本目录（部署时自动创建）
├── scripts/
│   └── update_tvbox.sh       # 自动更新脚本
└── docs/
    └── README.md             # 本文档
```

## 快速开始

### 方式一：使用已有数据目录（推荐）

如果服务器已有数据目录，直接启动容器：

```bash
# 1. 创建目录结构
mkdir -p /mnt/mmcblk2p4/docker/iptv-speedtest/{nginx,scripts}

# 2. 复制配置文件
cp docker-compose/nginx/default.conf /mnt/mmcblk2p4/docker/iptv-speedtest/nginx/

# 3. 复制更新脚本
cp scripts/update_tvbox.sh /mnt/mmcblk2p4/docker/iptv-speedtest/data/

# 4. 设置执行权限
chmod +x /mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh

# 5. 启动容器
docker run -d \
  --name iptv_nginx \
  --network host \
  -v /mnt/mmcblk2p4/docker/iptv-speedtest/data:/data:ro \
  -v /mnt/mmcblk2p4/docker/iptv-speedtest/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro \
  --restart unless-stopped \
  nginx:alpine

docker run -d \
  --name iptv_speedtest \
  --network host \
  -v /mnt/mmcblk2p4/docker/iptv-speedtest/data:/data \
  -v /mnt/mmcblk2p4/docker/iptv-speedtest/scripts:/app/scripts \
  --restart unless-stopped \
  iptv-speedtest:latest
```

### 方式二：使用 Docker Compose（全新部署）

```bash
# 1. 进入 docker-compose 目录
cd server-deploy/docker-compose

# 2. 创建必要的目录
mkdir -p data scripts nginx

# 3. 复制更新脚本
cp ../scripts/update_tvbox.sh data/

# 4. 设置执行权限
chmod +x data/update_tvbox.sh

# 5. 启动服务
docker-compose up -d
```

## 容器说明

### iptv_nginx
- **镜像**: `nginx:alpine`
- **端口**: 5353
- **用途**: 提供 HTTP 服务，访问 JSON 配置文件
- **挂载**: 
  - `./data:/data:ro` - 数据目录（只读）
  - `./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro` - Nginx 配置

### iptv_speedtest
- **镜像**: `iptv-speedtest:latest`
- **用途**: IPTV 直播源测速，自动生成有效的 tvbox.m3u
- **挂载**:
  - `./data:/data` - 数据目录（读写）
  - `./scripts:/app/scripts` - 脚本目录

### iptv_fetcher
- **镜像**: `curlimages/curl:latest`
- **用途**: IPTV 抓取（辅助容器）

## 配置定时任务

添加定时任务，每天早上 6 点自动更新：

```bash
# 编辑 crontab
crontab -e

# 添加以下行：
0 6 * * * /mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh >> /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log 2>&1
```

## 手动执行更新

```bash
# SSH 到服务器执行
ssh root@你的服务器IP "/mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh"
```

## 验证

访问以下地址确认服务正常：

```bash
# 主配置文件
curl http://10.10.10.130:5353/myiptv.json

# 直播源
curl http://10.10.10.130:5353/tvbox.m3u

# 点播源
curl http://10.10.10.130:5353/0821.json
```

## 服务器数据目录结构

```
/mnt/mmcblk2p4/docker/iptv-speedtest/
├── data/
│   ├── myiptv.json          # 主配置文件（自动生成）
│   ├── 0821.json            # 点播源（自动下载）
│   ├── fty.json             # FTY源（自动下载）
│   ├── tvbox.m3u            # 直播源（iptv_speedtest 自动生成）
│   ├── tv.m3u               # 直播源（iptv_speedtest 自动生成）
│   ├── iptv.m3u             # 原始直播源
│   ├── fan.txt              # 饭太硬爬虫配置
│   ├── fty.jar              # FTY 爬虫
│   ├── jar/
│   │   ├── spider.jar       # 爬虫（自动下载）
│   │   └── fan.txt          # 爬虫配置
│   ├── FTY/                 # FTY 分类配置
│   │   ├── bilibili.json
│   │   ├── biliych.json
│   │   ├── MTV.json
│   │   └── ...
│   ├── update_tvbox.sh      # 更新脚本
│   └── update.log           # 更新日志
├── nginx/
│   └── default.conf         # Nginx 配置文件
└── scripts/
    ├── speedtest_v2.py      # 测速脚本
    └── speedtest_cleaner.py # 清理脚本
```

## 更新脚本说明

`update_tvbox.sh` 脚本支持三种方式指定数据目录：

```bash
# 方式1: 命令行参数
./update_tvbox.sh /mnt/mmcblk2p4/docker/iptv-speedtest/data

# 方式2: 环境变量
DATA_DIR=/mnt/mmcblk2p4/docker/iptv-speedtest/data ./update_tvbox.sh

# 方式3: 默认路径
./update_tvbox.sh
```

### 脚本功能

1. 下载主配置文件 (0821.json, fty.json)
2. 合并生成 myiptv.json（包含 MTV 音乐源和直播源）
3. 下载爬虫文件 (jar/spider.jar, jar/fan.txt)
4. 下载 FTY 分类配置

## 日志查看

```bash
# 查看更新日志
cat /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log

# 实时查看更新过程
tail -f /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log

# 查看测速日志
cat /mnt/mmcblk2p4/docker/iptv-speedtest/data/clean.log
```

## 常见问题

### Q: 如何修改 Nginx 端口？

编辑 `docker-compose.yml` 中的端口映射：
```yaml
ports:
  - "8080:80"  # 改为 8080 端口
```

### Q: 如何修改自动更新时间？

编辑 crontab：
```bash
crontab -e
# 将 0 6 * * * 改为 desired time
# 例如每天凌晨 3 点：0 3 * * *
```

### Q: 如何手动更新直播源？

```bash
docker exec iptv_speedtest python3 /app/scripts/speedtest_v2.py
```

### Q: 如何查看容器日志？

```bash
# Nginx 日志
docker logs iptv_nginx

# 测速容器日志
docker logs iptv_speedtest

# 实时日志
docker logs -f iptv_nginx
```

## 相关链接

- TVBox 项目: https://github.com/qist/tvbox
- IPTV Speedtest: https://github.com/yao1987825/iptv-speedtest
