#!/bin/bash

#===============================================================================
# TVBox 服务一键部署脚本
# 支持多平台、多设备
#===============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_DATA_DIR="/var/lib/docker/iptv-speedtest/data"
DEFAULT_SCRIPTS_DIR="/var/lib/docker/iptv-speedtest/scripts"
DEFAULT_HTTP_PORT="5353"
DOCKER_COMPOSE_FILE=""

#===============================================================================
# 工具函数
#===============================================================================

log_info() { echo -e "${BLUE}[信息]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*" >&2; }
log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 获取本机 IP
get_local_ip() {
    local ip
    if command_exists hostname; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
    if [ -z "$ip" ]; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[^ ]+' || true)
    fi
    if [ -z "$ip" ]; then
        ip="localhost"
    fi
    echo "$ip"
}

#===============================================================================
# 环境检测
#===============================================================================

check_environment() {
    log_step "检测运行环境"
    
    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $PRETTY_NAME"
    elif [ -f /etc/lede-release ]; then
        log_info "系统: OpenWrt/LEDE"
    elif [ -f /etc/openwrt_version ]; then
        log_info "系统: OpenWrt"
    else
        log_info "系统: Linux (未知发行版)"
    fi
    
    # 检测架构
    local arch
    arch=$(uname -m)
    log_info "架构: $arch"
    
    # 检查 Docker
    if ! command_exists docker; then
        log_error "Docker 未安装!"
        echo ""
        echo "请先安装 Docker:"
        echo "  Ubuntu/Debian: curl -fsSL https://get.docker.com | sh"
        echo "  OpenWrt: opkg install docker docker-compose"
        exit 1
    fi
    
    local docker_version
    docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
    log_success "Docker: $(docker --version 2>/dev/null | cut -d' ' -f3-)"
    
    # 检查 Docker Compose
    local compose_version=""
    if command_exists docker-compose; then
        compose_version=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        log_success "Docker Compose: v$compose_version"
    elif docker compose version &>/dev/null; then
        compose_version=$(docker compose version --short 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        log_success "Docker Compose: v$compose_version"
    else
        log_error "Docker Compose 未安装!"
        exit 1
    fi
    
    # 检查 Docker 服务状态
    if ! docker info &>/dev/null; then
        log_error "Docker 服务未运行!"
        echo ""
        echo "请启动 Docker 服务:"
        echo "  sudo systemctl start docker"
        echo "  # 或 OpenWrt"
        echo "  /etc/init.d/docker start"
        exit 1
    fi
    log_success "Docker 服务运行中"
    
    # 检测存储空间
    log_info "检测存储空间..."
    local available_space
    available_space=$(df -BG /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo "未知")
    
    if [ "$available_space" -lt 5 ]; then
        log_warning "可用空间不足 5GB，当前约 ${available_space}GB"
    else
        log_success "可用空间充足 (~${available_space}GB)"
    fi
}

#===============================================================================
# 配置检测
#===============================================================================

detect_existing_config() {
    log_step "检测现有配置"
    
    # 查找现有的 docker-compose.yml
    local possible_paths=(
        "/var/lib/docker/iptv-speedtest/docker-compose.yml"
        "$DEFAULT_DATA_DIR/../docker-compose.yml"
        "./docker-compose.yml"
        "$PROJECT_DIR/docker-compose.yml"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ]; then
            log_info "发现现有配置: $path"
            DOCKER_COMPOSE_FILE="$path"
            
            # 提取端口
            local port
            port=$(grep -oP 'ports:' -A 5 "$path" | grep -oP '"\K[0-9]+(?=:80)' | head -1 || echo "")
            if [ -n "$port" ]; then
                DEFAULT_HTTP_PORT="$port"
                log_info "检测到现有端口: $port"
            fi
            return 0
        fi
    done
    
    log_info "未发现现有配置，将创建新配置"
    return 1
}

#===============================================================================
# 用户配置
#===============================================================================

user_config() {
    log_step "配置部署参数"
    
    # 数据目录
    echo -e "${BOLD}数据目录${NC}"
    echo "  用于存放 m3u 文件、数据库等"
    read -p "  默认 [$DEFAULT_DATA_DIR]: " DATA_DIR
    : "${DATA_DIR:=$DEFAULT_DATA_DIR}"
    echo -e "  ${GREEN}→ $DATA_DIR${NC}"
    echo ""
    
    # 创建目录
    if ! mkdir -p "$DATA_DIR" 2>/dev/null; then
        log_error "无法创建目录 $DATA_DIR，请检查权限"
        sudo mkdir -p "$DATA_DIR"
        sudo chown -R $(whoami) "$(dirname "$DATA_DIR")"
    fi
    
    # HTTP 端口
    echo -e "${BOLD}HTTP 服务端口${NC}"
    echo "  用于访问 TVBox 配置"
    while true; do
        read -p "  默认 [$DEFAULT_HTTP_PORT]: " HTTP_PORT
        : "${HTTP_PORT:=$DEFAULT_HTTP_PORT}"
        
        if [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] && [ "$HTTP_PORT" -ge 1 ] && [ "$HTTP_PORT" -le 65535 ]; then
            break
        fi
        log_error "端口无效，请输入 1-65535 之间的数字"
    done
    echo -e "  ${GREEN}→ $HTTP_PORT${NC}"
    echo ""
    
    # 直播源选择
    echo -e "${BOLD}直播源${NC}"
    echo "  1) yaojiwei520/IPTV (推荐)"
    echo "  2) fanmingming/live"
    echo "  3) 自定义 URL"
    
    while true; do
        read -p "  选择 [1-3]: " source_choice
        : "${source_choice:=1}"
        
        case "$source_choice" in
            1)
                SOURCE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/yaojiwei520/IPTV/refs/heads/main/iptv.m3u"
                break
                ;;
            2)
                SOURCE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/index.m3u"
                break
                ;;
            3)
                read -p "  输入 URL: " SOURCE_URL
                if [ -n "$SOURCE_URL" ]; then
                    break
                fi
                ;;
            *) log_error "请输入 1-3" ;;
        esac
    done
    echo -e "  ${GREEN}→ $SOURCE_URL${NC}"
    echo ""
    
    # 获取间隔
    echo -e "${BOLD}直播源获取间隔${NC}"
    echo "  1) 30 分钟"
    echo "  2) 1 小时 (推荐)"
    echo "  3) 2 小时"
    
    while true; do
        read -p "  选择 [1-3]: " fetch_choice
        : "${fetch_choice:=2}"
        
        case "$fetch_choice" in
            1) FETCH_INTERVAL=1800; break ;;
            2) FETCH_INTERVAL=3600; break ;;
            3) FETCH_INTERVAL=7200; break ;;
            *) log_error "请输入 1-3" ;;
        esac
    done
    echo -e "  ${GREEN}→ $((FETCH_INTERVAL/60)) 分钟${NC}"
    echo ""
    
    # 测速间隔
    echo -e "${BOLD}测速间隔${NC}"
    echo "  1) 1 分钟"
    echo "  2) 3 分钟 (推荐)"
    echo "  3) 5 分钟"
    
    while true; do
        read -p "  选择 [1-3]: " test_choice
        : "${test_choice:=2}"
        
        case "$test_choice" in
            1) TEST_INTERVAL=60; break ;;
            2) TEST_INTERVAL=180; break ;;
            3) TEST_INTERVAL=300; break ;;
            *) log_error "请输入 1-3" ;;
        esac
    done
    echo -e "  ${GREEN}→ $((TEST_INTERVAL/60)) 分钟${NC}"
    echo ""
    
    SCRIPTS_DIR="$DATA_DIR/../scripts"
}

#===============================================================================
# 部署流程
#===============================================================================

prepare_scripts() {
    log_step "准备脚本文件"
    
    # 创建脚本目录
    mkdir -p "$SCRIPTS_DIR"
    
    # 克隆测速脚本
    local temp_dir
    temp_dir=$(mktemp -d)
    
    log_info "克隆测速脚本..."
    if command_exists git; then
        if git clone --depth 1 https://github.com/yao1987825/iptv-speedtest.git "$temp_dir" 2>/dev/null; then
            cp -f "$temp_dir/scripts/"*.py "$SCRIPTS_DIR/" 2>/dev/null || true
            rm -rf "$temp_dir"
            
            if [ -f "$SCRIPTS_DIR/speedtest_v2.py" ]; then
                log_success "测速脚本准备完成"
            else
                log_warning "测速脚本不完整，尝试备用方案"
            fi
        else
            log_warning "无法访问 GitHub，使用备用脚本"
            create_backup_script
        fi
    else
        log_warning "Git 未安装，使用备用脚本"
        create_backup_script
    fi
    
    # 复制更新脚本
    if [ -f "$PROJECT_DIR/scripts/update_tvbox.sh" ]; then
        cp -f "$PROJECT_DIR/scripts/update_tvbox.sh" "$SCRIPTS_DIR/" 2>/dev/null || true
    fi
}

# 创建备用脚本
create_backup_script() {
    cat > "$SCRIPTS_DIR/speedtest_v2.py" << 'SCRIPT'
#!/usr/bin/env python3
"""备用测速脚本 - 简化版"""
import os
import time
import subprocess

M3U_FILE = os.getenv("M3U_FILE", "/data/iptv.m3u")
TV_M3U = os.getenv("TV_M3U_PATH", "/data/tv.m3u")
TVBOX_M3U = os.getenv("TVBOX_M3U_PATH", "/data/tvbox.m3u")

def test_channel(url):
    try:
        result = subprocess.run(["curl", "-sI", "-m", "5", url], 
                              capture_output=True, timeout=6)
        return result.returncode == 0
    except:
        return False

def main():
    print("Starting simplified speedtest...")
    if not os.path.exists(M3U_FILE):
        print(f"{M3U_FILE} not found, waiting...")
        return
    
    # 简单处理：复制文件
    with open(M3U_FILE, 'r') as f:
        content = f.read()
    
    with open(TV_M3U, 'w') as f:
        f.write(content)
    with open(TVBOX_M3U, 'w') as f:
        f.write(content)
    
    print(f"Updated {TV_M3U} and {TVBOX_M3U}")

if __name__ == "__main__":
    while True:
        main()
        time.sleep(180)
SCRIPT
    chmod +x "$SCRIPTS_DIR/speedtest_v2.py"
}

generate_compose() {
    log_step "生成配置文件"
    
    local compose_file="$DATA_DIR/../docker-compose.yml"
    
    cat > "$compose_file" << EOF
version: '3.8'

services:
  iptv_nginx:
    image: nginx:alpine
    container_name: iptv_nginx
    ports:
      - "${HTTP_PORT}:80"
    volumes:
      - ${DATA_DIR}:/usr/share/nginx/html:ro
    restart: unless-stopped

  iptv_fetcher:
    image: ghcr.io/yao1987825/iptv-fetcher:latest
    container_name: iptv_fetcher
    network_mode: host
    volumes:
      - ${DATA_DIR}:/data
    environment:
      - SOURCE_URL=${SOURCE_URL}
      - FETCH_INTERVAL=${FETCH_INTERVAL}
    restart: unless-stopped

  iptv_speedtest:
    image: ghcr.io/yao1987825/iptv-speedtest:latest
    container_name: iptv_speedtest
    network_mode: host
    volumes:
      - ${DATA_DIR}:/data
      - ${SCRIPTS_DIR}:/app/scripts:ro
    environment:
      - TZ=Asia/Shanghai
      - TEST_INTERVAL=${TEST_INTERVAL}
      - TEST_TIMEOUT=5
    restart: unless-stopped
EOF

    DOCKER_COMPOSE_FILE="$compose_file"
    log_success "配置文件: $compose_file"
}

deploy() {
    log_step "开始部署"
    
    local compose_dir
    compose_dir=$(dirname "$DOCKER_COMPOSE_FILE")
    
    cd "$compose_dir"
    
    # 停止旧容器
    log_info "停止旧容器..."
    docker compose down &>/dev/null || true
    
    # 拉取镜像
    log_info "拉取镜像（首次可能需要几分钟）..."
    if ! docker compose pull 2>&1 | tee /tmp/docker_pull.log; then
        log_error "镜像拉取失败"
        if grep -q "no such image" /tmp/docker_pull.log; then
            log_error "镜像不存在，可能需要手动构建"
        fi
        exit 1
    fi
    
    # 启动服务
    log_info "启动服务..."
    if ! docker compose up -d 2>&1; then
        log_error "服务启动失败"
        docker compose logs
        exit 1
    fi
    
    # 等待启动
    sleep 5
    
    # 检查状态
    local failed=0
    for container in iptv_nginx iptv_fetcher iptv_speedtest; do
        if docker ps | grep -q "$container"; then
            log_success "$container 运行中"
        else
            log_error "$container 未运行"
            failed=1
        fi
    done
    
    if [ $failed -eq 1 ]; then
        log_error "部分服务启动失败"
        docker compose logs
        exit 1
    fi
}

#===============================================================================
# 显示结果
#===============================================================================

show_result() {
    log_step "部署完成"
    
    local server_ip
    server_ip=$(get_local_ip)
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         服务访问地址                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}主配置:${NC}   http://${server_ip}:${HTTP_PORT}/myiptv.json"
    echo -e "  ${BOLD}直播源:${NC}   http://${server_ip}:${HTTP_PORT}/tvbox.m3u"
    echo -e "  ${BOLD}文件目录:${NC} http://${server_ip}:${HTTP_PORT}/"
    echo ""
    
    echo -e "${CYAN}常用命令:${NC}"
    echo "  查看日志:  cd $(dirname "$DOCKER_COMPOSE_FILE") && docker compose logs -f"
    echo "  重启服务:  cd $(dirname "$DOCKER_COMPOSE_FILE") && docker compose restart"
    echo "  停止服务:  cd $(dirname "$DOCKER_COMPOSE_FILE") && docker compose down"
    echo "  查看状态:  docker ps | grep iptv"
    echo ""
    
    echo -e "${CYAN}数据目录:${NC}"
    echo "  $DATA_DIR"
    echo ""
}

#===============================================================================
# 卸载
#===============================================================================

uninstall() {
    log_step "卸载服务"
    
    local compose_file
    if [ -n "$1" ]; then
        compose_file="$1/docker-compose.yml"
    else
        compose_file="$DEFAULT_DATA_DIR/../docker-compose.yml"
    fi
    
    if [ -f "$compose_file" ]; then
        local compose_dir
        compose_dir=$(dirname "$compose_file")
        
        cd "$compose_dir"
        log_info "停止并删除容器..."
        docker compose down
        
        log_info "删除配置和数据? (数据目录不会被删除)"
        read -p "  删除配置? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -f "$compose_file"
            rm -rf "$(dirname "$compose_file")/scripts"
            log_success "配置已删除"
        fi
    else
        log_error "未找到配置文件"
    fi
}

#===============================================================================
# 状态查看
#===============================================================================

status() {
    log_step "服务状态"
    
    echo ""
    docker ps --filter "name=iptv" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    # 查看日志摘要
    log_info "最近日志 (最后 5 行):"
    docker logs --tail 5 iptv_nginx 2>/dev/null | grep -v "^$" | tail -3 || true
}

#===============================================================================
# 更新
#===============================================================================

update() {
    log_step "更新服务"
    
    local compose_file="${1:-$DEFAULT_DATA_DIR/../docker-compose.yml}"
    
    if [ ! -f "$compose_file" ]; then
        log_error "未找到配置文件"
        exit 1
    fi
    
    local compose_dir
    compose_dir=$(dirname "$compose_file")
    
    cd "$compose_dir"
    
    log_info "拉取最新镜像..."
    docker compose pull
    
    log_info "重启服务..."
    docker compose down
    docker compose up -d
    
    log_success "更新完成"
}

#===============================================================================
# 主流程
#===============================================================================

show_help() {
    cat << EOF
TVBox 服务一键部署脚本

用法: 
  $0 [命令] [参数]

命令:
  deploy     部署服务 (默认)
  status     查看服务状态
  update     更新服务
  uninstall  卸载服务

示例:
  $0                 # 交互式部署
  $0 status          # 查看状态
  $0 update          # 更新服务

EOF
}

main() {
    local command="${1:-deploy}"
    shift || true
    
    case "$command" in
        deploy)
            # 显示欢迎
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║     TVBox 服务一键部署脚本           ║${NC}"
            echo -e "${GREEN}║     自动化部署 IPTV 测速服务          ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
            echo ""
            
            check_environment
            detect_existing_config || true
            user_config
            prepare_scripts
            generate_compose
            deploy
            show_result
            ;;
        status)
            status
            ;;
        update)
            update "$@"
            ;;
        uninstall)
            uninstall "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
