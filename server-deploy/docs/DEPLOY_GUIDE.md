# TVBox 服务部署脚本使用指南

本指南介绍如何使用一键部署脚本在各种设备上部署 TVBox 服务。

## 环境要求

| 要求 | 说明 |
|------|------|
| Docker | 20.10+ |
| Docker Compose | 2.0+ |
| 网络 | 能访问 GitHub |

## 支持的设备

- x86 服务器（VPS、PC）
- ARM 设备（OpenWrt、ImmortalWrt）
- 群晖 NAS
- 威联通 NAS
- 其他 Linux 设备

## 快速开始

### 方式一：直接运行

```bash
# 下载脚本
curl -sL https://raw.githubusercontent.com/yao1987825/tvbox/master/server-deploy/scripts/deploy.sh -o /tmp/deploy.sh

# 添加执行权限
chmod +x /tmp/deploy.sh

# 运行脚本
/tmp/deploy.sh
```

### 方式二：克隆后运行

```bash
# 克隆项目
git clone https://github.com/yao1987825/tvbox.git
cd tvbox/server-deploy/scripts

# 运行脚本
./deploy.sh
```

## 交互配置说明

运行脚本后，会依次提示配置以下内容：

### 1. 数据目录

用于存放 m3u 文件、数据库等数据。

```
请输入数据目录 [/var/lib/docker/iptv-speedtest/data]:
```

**不同设备建议**：
- OpenWrt/ImmortalWrt: `/mnt/storage/iptv-speedtest/data`
- x86 服务器: `/var/lib/docker/iptv-speedtest/data`
- 群晖 NAS: `/volume1/docker/iptv-speedtest/data`

### 2. HTTP 端口

用于访问 TVBox 配置的端口。

```
请输入 HTTP 端口 [5353]:
```

建议使用非标准端口（如 5353、8080）避免冲突。

### 3. 直播源选择

```
请选择直播源:
1) yaojiwei520/IPTV (推荐)
2) fanmingming/live
3) 自定义 URL
```

推荐使用 `yaojiwei520/IPTV`，频道较全。

### 4. 获取间隔

直播源多久自动更新一次：

- 30 分钟
- 1 小时（推荐）
- 2 小时

### 5. 测速间隔

所有频道多久测速一次：

- 1 分钟
- 3 分钟（推荐）
- 5 分钟

## 部署完成

部署成功后，会显示服务访问地址：

```
╔════════════════════════════════════════╗
║         服务访问地址                   ║
╚════════════════════════════════════════╝

  主配置:   http://192.168.1.100:5353/myiptv.json
  直播源:   http://192.168.1.100:5353/tvbox.m3u
  文件目录: http://192.168.1.100:5353/
```

## 常用命令

### 查看状态

```bash
cd /var/lib/docker/iptv-speedtest
docker compose ps
```

### 查看日志

```bash
# 实时日志
docker compose logs -f

# 仅查看测速日志
docker compose logs iptv_speedtest

# 仅查看获取日志
docker compose logs iptv_fetcher
```

### 重启服务

```bash
docker compose restart
```

### 停止服务

```bash
docker compose down
```

### 更新服务

```bash
# 方式一：使用脚本
./deploy.sh update

# 方式二：手动更新
cd /var/lib/docker/iptv-speedtest
docker compose pull
docker compose up -d
```

## 卸载服务

```bash
# 使用脚本卸载
./deploy.sh uninstall
```

## 配置说明

### 修改端口

编辑 `docker-compose.yml`：

```yaml
ports:
  - "8080:80"  # 改为 8080
```

修改后执行：

```bash
docker compose up -d
```

### 修改直播源

编辑 `.env` 文件或环境变量：

```bash
# 停止服务
docker compose down

# 修改环境变量
export SOURCE_URL="新的直播源URL"

# 重启
docker compose up -d
```

### 修改测速间隔

```bash
# 停止服务
docker compose down

# 修改环境变量（单位：秒）
export TEST_INTERVAL=300  # 5分钟

# 重启
docker compose up -d
```

## 故障排查

### 问题：Docker 未安装

```
[错误] Docker 未安装!
```

**解决方案**：

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh

# CentOS
yum install docker -y
systemctl start docker
systemctl enable docker

# OpenWrt
opkg update
opkg install docker docker-compose
```

### 问题：端口被占用

```
[警告] 端口 5353 已被占用!
```

**解决方案**：

1. 查看占用进程：`netstat -tlnp | grep 5353`
2. 停止占用服务
3. 或选择其他端口

### 问题：镜像拉取失败

```
[错误] 镜像拉取失败
```

**解决方案**：

1. 检查网络：`curl -I https://ghcr.io`
2. 配置镜像代理
3. 或手动构建镜像

### 问题：服务启动失败

```bash
# 查看详细日志
docker compose logs

# 检查容器状态
docker compose ps

# 查看具体错误
docker logs <容器名>
```

## 数据目录结构

部署后，数据目录结构如下：

```
/var/lib/docker/iptv-speedtest/
├── data/
│   ├── iptv.m3u          # 原始直播源
│   ├── tv.m3u            # 测速后的直播源
│   ├── tvbox.m3u         # TVBox 格式直播源
│   ├── myiptv.json       # TVBox 主配置
│   ├── 0821.json          # 点播源配置
│   ├── fty.json           # FTY 点播源
│   ├── iptv_speedtest.db  # 测速数据库
│   ├── jar/               # 爬虫文件
│   └── FTY/              # FTY 分类
├── scripts/
│   ├── speedtest_v2.py   # 测速脚本
│   └── speedtest_cleaner.py
└── docker-compose.yml    # 配置文件
```

## TVBox 配置

在 TVBox 中添加直播源：

- **主配置地址**: `http://你的IP:5353/myiptv.json`
- **或直接用直播源**: `http://你的IP:5353/tvbox.m3u`

## 相关链接

- GitHub 仓库: https://github.com/yao1987825/tvbox
- TVBox 配置: https://github.com/qist/tvbox
- 直播源: https://github.com/yaojiwei520/IPTV
