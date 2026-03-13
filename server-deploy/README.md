# TVBox 服务器部署

整合 IPTV 直播源测速、自动更新的一键部署方案。

## Docker 镜像

```bash
# 拉取镜像
docker pull ghcr.io/yao1987825/tvbox-server:latest
```

## 快速开始

```bash
# 克隆项目
git clone https://github.com/yao1987825/tvbox.git
cd tvbox/server-deploy

# 复制配置
cp .env.example .env

# 启动服务
docker compose up -d
```

## 不同设备配置

### .env 配置示例

```bash
# ==================== 必填配置 ====================

# 数据目录（根据不同设备修改）
DATA_DIR=/mnt/mmcblk2p4/docker/iptv-speedtest/data

# 脚本目录
SCRIPTS_DIR=./server-deploy/scripts

# ==================== 可选配置 ====================

# 直播源获取间隔（秒），默认 1 小时
FETCH_INTERVAL=3600

# 测速间隔（秒），默认 3 分钟
TEST_INTERVAL=180

# 单个频道超时时间（秒）
TEST_TIMEOUT=5

# 直播源 URL
SOURCE_URL=https://gh-proxy.com/https://raw.githubusercontent.com/yaojiwei520/IPTV/refs/heads/main/iptv.m3u
```

### 设备配置对照表

| 设备类型 | 示例设备 | DATA_DIR 配置 |
|---------|---------|---------------|
| ImmortalWrt (ARM) | 你的服务器 | `/mnt/mmcblk2p4/docker/iptv-speedtest/data` |
| OpenWrt (ARM) | 路由器 | `/mnt/storage/iptv-speedtest/data` |
| x86 服务器 | VPS/PC | `/docker/iptv-speedtest/data` |
| 群晖 NAS | DS220+ | `/volume1/docker/iptv-speedtest/data` |
| 威联通 NAS | TS-453D | `/share/Container/iptv-speedtest/data` |

### 示例配置

```bash
# ImmortalWrt (ARM 设备)
DATA_DIR=/mnt/mmcblk2p4/docker/iptv-speedtest/data

# x86 服务器
DATA_DIR=/docker/iptv-speedtest/data

# 群晖 NAS
DATA_DIR=/volume1/docker/iptv-speedtest/data
```

## 服务说明

### 整合服务 (tvbox_server)

- **功能**: 
  - Nginx HTTP 服务 (端口 5353)
  - 自动获取 IPTV 直播源
  - 直播源测速清洗
  - TVBox 配置自动更新

- **环境变量**:
  | 变量 | 默认值 | 说明 |
  |------|--------|------|
  | DATA_DIR | /data | 数据目录 |
  | TEST_INTERVAL | 180 | 测速间隔（秒） |
  | TEST_TIMEOUT | 5 | 超时时间（秒） |
  | FETCH_INTERVAL | 3600 | 直播源获取间隔 |
  | SOURCE_URL | - | 直播源 URL |

## 服务访问

```bash
# 主配置
http://your-server:5353/myiptv.json

# 直播源
http://your-server:5353/tvbox.m3u
http://your-server:5353/tv.m3u

# 点播源
http://your-server:5353/0821.json
http://your-server:5353/fty.json

# 文件目录
http://your-server:5353/
```

## 手动命令

```bash
# 查看容器状态
docker ps

# 查看日志
docker logs -f tvbox_server

# 手动更新 TVBox 配置
docker exec tvbox_server python3 /app/scripts/speedtest_v2.py

# 重启容器
docker restart tvbox_server
```

## 定时任务

建议配合 crontab 使用：

```bash
crontab -e

# 每天早上 6 点自动更新 TVBox 配置
0 6 * * * docker restart tvbox_server
```

## 数据目录结构

```
{_DATA_DIR}/
├── iptv.m3u              # 原始直播源
├── tv.m3u                # 测速后的直播源
├── tvbox.m3u             # TVBox 格式直播源
├── myiptv.json           # TVBox 主配置
├── 0821.json             # 点播源
├── fty.json              # FTY 源
├── iptv_speedtest.db     # 测速数据库
├── fan.txt               # 爬虫配置
├── jar/                  # 爬虫文件
│   ├── spider.jar
│   └── fan.txt
├── FTY/                  # FTY 分类配置
└── update.log            # 更新日志
```
