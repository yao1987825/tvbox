#!/bin/bash
# TVBox 配置自动更新脚本
# 从 GitHub 获取最新配置
#
# 使用方法:
#   ./update_tvbox.sh                          # 使用默认路径
#   ./update_tvbox.sh /自定义/数据目录          # 指定数据目录
#   DATA_DIR=/自定义/目录 ./update_tvbox.sh    # 使用环境变量

set -e

# 支持三种方式指定数据目录:
# 1. 命令行参数: ./update_tvbox.sh /data
# 2. 环境变量: DATA_DIR=/data ./update_tvbox.sh
# 3. 默认路径
DATA_DIR="${1:-${DATA_DIR:-/data}}"

GITHUB_RAW="https://raw.githubusercontent.com/qist/tvbox/master"

LOG_FILE="${DATA_DIR}/update.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== 开始更新 TVBox 配置 =========="

cd "$DATA_DIR"

# 更新主配置文件
update_file() {
    local filename=$1
    local url="${GITHUB_RAW}/${filename}"
    local temp="${filename}.tmp"
    local backup="${filename}.bak"
    
    log "下载: $filename"
    if ! curl -sL --connect-timeout 30 --max-time 300 -o "$temp" "$url"; then
        log "✗ $filename 下载失败"
        rm -f "$temp"
        return 1
    fi
    
    # 检查下载的文件是否有效（大小>100字节）
    local size=$(wc -c < "$temp" 2>/dev/null || echo 0)
    if [ "$size" -lt 100 ]; then
        log "✗ $filename 下载文件无效 (size: $size)"
        rm -f "$temp"
        return 1
    fi
    
    # 如果原文件存在，备份并比较
    if [ -f "$filename" ]; then
        if diff -q "$filename" "$temp" > /dev/null 2>&1; then
            log "✓ $filename 无变化"
            rm -f "$temp"
        else
            cp "$filename" "$backup"
            mv "$temp" "$filename"
            log "✓ $filename 已更新"
            rm -f "$backup"
        fi
    else
        mv "$temp" "$filename"
        log "✓ $filename 已创建"
    fi
}

# 更新主配置文件 (从 qist/tvbox 获取)
# 使用 0821.json 作为主配置（饭太硬+优质点播源）
update_file "0821.json"
update_file "fty.json"

# 复制 0821.json 为 myiptv.json，并配置直播源和音乐源
if [ -f "0821.json" ] && [ -f "fty.json" ]; then
    python3 -c "
import json
try:
    with open('0821.json', 'r', encoding='utf-8') as f:
        data = json.load(f)
    with open('fty.json', 'r', encoding='utf-8') as f:
        fty = json.load(f)
    
    # 获取 fty.json 中的音乐源
    music_sites = [s for s in fty.get('sites', []) if '音乐' in s.get('name', '') or 'MTV' in s.get('name', '')]
    
    # 合并音乐源到 sites
    existing_keys = {s.get('key') for s in data.get('sites', [])}
    for site in music_sites:
        if site.get('key') not in existing_keys:
            data['sites'].append(site)
            print(f\"添加音乐源: {site.get('name')}\")
    
    # 配置直播源指向 tvbox.m3u
    data['lives'] = [{
        'name': 'live',
        'boot': False,
        'type': 0,
        'url': './tvbox.m3u',
        'playerType': 2,
        'ua': 'okhttp/3.8.1',
        'timeout': 20,
        'epg': 'https://epg.51zmt.top:8080/api/diyp/epg.xml',
        'logo': 'https://logo.wyfc.qzz.io/{name}.png'
    }]
    with open('myiptv.json', 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print('已创建 myiptv.json（0821.json + MTV音乐源 + tvbox.m3u）')
except Exception as e:
    print(f'出错: {e}')
" && log "已更新 myiptv.json（0821.json + MTV音乐源 + tvbox.m3u）"
fi

# 更新 jar 文件
mkdir -p "${DATA_DIR}/jar"

log "下载 spider.jar"
curl -sL --connect-timeout 30 --max-time 300 -o "${DATA_DIR}/jar/spider.jar" "${GITHUB_RAW}/jar/spider.jar" || log "spider.jar 下载失败，使用现有版本"

log "下载 fan.txt"
curl -sL --connect-timeout 30 --max-time 300 -o "${DATA_DIR}/jar/fan.txt" "${GITHUB_RAW}/jar/fan.txt" || log "fan.txt 下载失败，使用现有版本"

# 更新 FTY 目录
mkdir -p "${DATA_DIR}/FTY"
for file in bilibili.json biliych.json 高中课堂.json 戏曲大全.json MTV.json; do
    log "下载 FTY/$file"
    curl -sL --connect-timeout 30 --max-time 300 -o "${DATA_DIR}/FTY/$file" "${GITHUB_RAW}/FTY/$file" || log "FTY/$file 下载失败"
done

log "========== 更新完成 =========="
