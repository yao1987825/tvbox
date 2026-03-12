# TVBox 服务器部署指南

本项目用于在私有服务器上部署 TVBox 配置自动更新服务。

## 功能说明

- 自动从 GitHub (qist/tvbox) 获取最新的点播源配置
- 保留本地测速后的直播源 (tvbox.m3u)
- 包含音乐 MTV 源
- 每天自动更新

## 文件说明

```
server-deploy/
├── scripts/
│   └── update_tvbox.sh    # 自动更新脚本
├── docs/
│   └── README.md          # 本文档
└── docker-compose/        # Docker 相关配置（如有需要）
```

## 部署步骤

### 1. 环境要求

- 服务器已安装 Docker
- 服务器运行着以下容器：
  - `iptv_nginx` - 提供 HTTP 服务 (端口 5353)
  - `iptv_speedtest` - IPTV 测速服务

### 2. 上传脚本

将 `scripts/update_tvbox.sh` 上传到服务器：

```bash
scp scripts/update_tvbox.sh root@你的服务器IP:/mnt/mmcblk2p4/docker/iptv-speedtest/data/
```

### 3. 设置执行权限

```bash
ssh root@你的服务器IP "chmod +x /mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh"
```

### 4. 配置定时任务

添加定时任务，每天早上 6 点自动更新：

```bash
ssh root@你的服务器IP "crontab -l | grep update_tvbox; echo '0 6 * * * /mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh >> /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log 2>&1' | crontab -"
```

### 5. 手动执行一次测试

```bash
ssh root@你的服务器IP "/mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh"
```

### 6. 验证

访问 `http://你的服务器IP:5353/myiptv.json` 确认配置正常。

## 配置说明

### myiptv.json 包含内容

- **点播源**: 0821.json (饭太硬 + 优质点播源) + MTV 音乐源
- **直播源**: tvbox.m3u (本地测速后的有效直播源)
- **spider**: jar/spider.jar

### 更新内容

每次更新会下载：
- `0821.json` - 主点播源配置
- `fty.json` - FTY 点播源
- `myiptv.json` - 合并后的主配置
- `jar/spider.jar` - 爬虫文件
- `jar/fan.txt` - 饭太硬爬虫
- `FTY/*.json` - FTY 分类配置

## 日志查看

```bash
# 查看更新日志
ssh root@你的服务器IP "cat /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log"

# 实时查看更新过程
ssh root@你的服务器IP "tail -f /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log"
```

## 常见问题

### Q: 如何手动更新？

```bash
ssh root@你的服务器IP "/mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh"
```

### Q: 如何修改更新时间？

编辑 crontab：
```bash
ssh root@你的服务器IP "crontab -e"
```

例如改为每天凌晨 3 点：
```
0 3 * * * /mnt/mmcblk2p4/docker/iptv-speedtest/data/update_tvbox.sh >> /mnt/mmcblk2p4/docker/iptv-speedtest/data/update.log 2>&1
```

### Q: 如何查看当前的配置？

```bash
curl -s http://你的服务器IP:5353/myiptv.json | python3 -m json.tool | head -50
```

### Q: 直播源在哪里配置的？

直播源由 `iptv_speedtest` 容器自动测速生成，存放在：
- `/mnt/mmcblk2p4/docker/iptv-speedtest/data/tvbox.m3u`

该容器每 3 分钟自动测速并更新直播源。

## 目录结构参考

服务器上的数据目录结构：
```
/mnt/mmcblk2p4/docker/iptv-speedtest/data/
├── myiptv.json          # 主配置文件（自动生成）
├── 0821.json            # 点播源（自动下载）
├── fty.json             # FTY源（自动下载）
├── tvbox.m3u            # 直播源（iptv_speedtest 自动生成）
├── tv.m3u               # 直播源（iptv_speedtest 自动生成）
├── jar/
│   ├── spider.jar       # 爬虫（自动下载）
│   └── fan.txt          # 饭太硬爬虫（自动下载）
├── FTY/                 # FTY 分类配置（自动下载）
├── update_tvbox.sh      # 更新脚本
└── update.log           # 更新日志
```

## 相关容器

### iptv_nginx

- 镜像: `nginx:alpine`
- 端口: 5353
- 用途: 提供 HTTP 服务，访问 JSON 配置文件

### iptv_speedtest

- 镜像: `iptv-speedtest:latest`
- 用途: IPTV 直播源测速，自动生成有效的 tvbox.m3u

## 许可证

本项目仅供个人学习使用。
