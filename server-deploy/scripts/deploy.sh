#!/bin/bash

# TVBox 服务一键部署脚本
# 支持交互式配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置默认值
DEFAULT_DATA_DIR="/var/lib/docker/iptv-speedtest/data"
DEFAULT_SCRIPTS_DIR="/var/lib/docker/iptv-speedtest/scripts"
DEFAULT_HTTP_PORT="5353"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# 欢迎信息
welcome() {
    clear
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     TVBox 服务一键部署脚本           ║${NC}"
    echo -e "${GREEN}║     自动化部署 IPTV 测速服务          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# 检查 Docker 环境
check_docker() {
    print_step "检查 Docker 环境"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    print_success "Docker 已安装: $(docker --version)"
    
    if ! command -v docker compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose 未安装"
        exit 1
    fi
    print_success "Docker Compose 已安装"
    
    if ! docker info &> /dev/null; then
        print_error "Docker 服务未运行，请启动 Docker"
        exit 1
    fi
    print_success "Docker 服务运行中"
}

# 配置数据目录
config_data_dir() {
    print_step "配置数据目录"
    
    echo "请输入数据存储目录（用于存放 m3u 文件、数据库等）："
    echo -e "  默认: ${GREEN}${DEFAULT_DATA_DIR}${NC}"
    echo ""
    read -p "请输入路径 [直接回车使用默认值]: " DATA_DIR
    
    if [ -z "$DATA_DIR" ]; then
        DATA_DIR="$DEFAULT_DATA_DIR"
    fi
    
    echo ""
    print_info "数据目录: $DATA_DIR"
    
    # 创建目录
    print_info "创建数据目录..."
    mkdir -p "$DATA_DIR"
    
    if [ $? -ne 0 ]; then
        print_error "创建数据目录失败，请检查权限"
        exit 1
    fi
    print_success "数据目录创建成功"
    
    # 创建脚本目录
    mkdir -p "${DATA_DIR}/../scripts"
    SCRIPTS_DIR="${DATA_DIR}/../scripts"
    print_info "脚本目录: $SCRIPTS_DIR"
}

# 配置端口
config_port() {
    print_step "配置 HTTP 服务端口"
    
    echo "请输入 HTTP 服务端口（用于访问 TVBox 配置）："
    echo -e "  默认: ${GREEN}${DEFAULT_HTTP_PORT}${NC}"
    echo ""
    read -p "请输入端口 [直接回车使用默认值]: " HTTP_PORT
    
    if [ -z "$HTTP_PORT" ]; then
        HTTP_PORT="$DEFAULT_HTTP_PORT"
    fi
    
    # 验证端口
    if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || [ "$HTTP_PORT" -lt 1 ] || [ "$HTTP_PORT" -gt 65535 ]; then
        print_error "端口号无效，请输入 1-65535 之间的数字"
        exit 1
    fi
    
    # 检查端口是否被占用
    if ss -tlnp 2>/dev/null | grep -q ":$HTTP_PORT " || netstat -tlnp 2>/dev/null | grep -q ":$HTTP_PORT "; then
        print_warning "端口 $HTTP_PORT 已被占用!"
        read -p "是否继续? (y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_info "已取消部署"
            exit 0
        fi
    fi
    
    echo ""
    print_info "HTTP 端口: $HTTP_PORT"
}

# 配置直播源
config_source() {
    print_step "配置直播源"
    
    echo "请选择直播源类型："
    echo "  1) yaojiwei520/IPTV (推荐)"
    echo "  2) fanmingming/live"
    echo "  3) 自定义 URL"
    echo ""
    read -p "请选择 [1-3，直接回车使用默认值]: " source_choice
    
    case "$source_choice" in
        1)
            SOURCE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/yaojiwei520/IPTV/refs/heads/main/iptv.m3u"
            ;;
        2)
            SOURCE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/index.m3u"
            ;;
        3)
            echo ""
            read -p "请输入直播源 URL: " SOURCE_URL
            if [ -z "$SOURCE_URL" ]; then
                print_error "URL 不能为空"
                exit 1
            fi
            ;;
        *)
            SOURCE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/yaojiwei520/IPTV/refs/heads/main/iptv.m3u"
            ;;
    esac
    
    echo ""
    print_info "直播源: $SOURCE_URL"
}

# 配置时间间隔
config_interval() {
    print_step "配置时间间隔"
    
    echo "直播源获取间隔（多久更新一次直播源）："
    echo "  1) 30 分钟"
    echo "  2) 1 小时 (推荐)"
    echo "  3) 2 小时"
    echo "  4) 6 小时"
    echo ""
    read -p "请选择 [1-4，直接回车使用默认值]: " fetch_choice
    
    case "$fetch_choice" in
        1) FETCH_INTERVAL=1800 ;;
        2) FETCH_INTERVAL=3600 ;;
        3) FETCH_INTERVAL=7200 ;;
        4) FETCH_INTERVAL=21600 ;;
        *) FETCH_INTERVAL=3600 ;;
    esac
    
    echo ""
    print_info "获取间隔: $((FETCH_INTERVAL/60)) 分钟"
    
    echo ""
    echo "测速间隔（多久测速一次所有频道）："
    echo "  1) 1 分钟"
    echo "  2) 3 分钟 (推荐)"
    echo "  3) 5 分钟"
    echo "  4) 10 分钟"
    echo ""
    read -p "请选择 [1-4，直接回车使用默认值]: " test_choice
    
    case "$test_choice" in
        1) TEST_INTERVAL=60 ;;
        2) TEST_INTERVAL=180 ;;
        3) TEST_INTERVAL=300 ;;
        4) TEST_INTERVAL=600 ;;
        *) TEST_INTERVAL=180 ;;
    esac
    
    echo ""
    print_info "测速间隔: $((TEST_INTERVAL/60)) 分钟"
}

# 克隆必要脚本
clone_scripts() {
    print_step "获取测速脚本"
    
    print_info "从 GitHub 获取测速脚本..."
    
    # 检查脚本目录
    if [ ! -d "$SCRIPTS_DIR" ]; then
        mkdir -p "$SCRIPTS_DIR"
    fi
    
    # 克隆或更新
    if [ -d "$SCRIPTS_DIR/.git" ]; then
        cd "$SCRIPTS_DIR"
        git pull origin master 2>/dev/null || true
    else
        rm -rf "$SCRIPTS_DIR"
        git clone --depth 1 https://github.com/yao1987825/iptv-speedtest.git temp
        mkdir -p "$SCRIPTS_DIR"
        cp -r temp/scripts/* "$SCRIPTS_DIR/" 2>/dev/null || true
        rm -rf temp
    fi
    
    if [ -f "$SCRIPTS_DIR/speedtest_v2.py" ]; then
        print_success "测速脚本获取成功"
    else
        print_error "测速脚本获取失败"
        exit 1
    fi
}

# 生成 docker-compose.yml
generate_compose() {
    print_step "生成配置文件"
    
    COMPOSE_FILE="$DATA_DIR/../docker-compose.yml"
    
    cat > "$COMPOSE_FILE" << EOF
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

    print_success "配置文件已生成: $COMPOSE_FILE"
}

# 启动服务
start_services() {
    print_step "启动服务"
    
    COMPOSE_FILE="$DATA_DIR/../docker-compose.yml"
    COMPOSE_DIR=$(dirname "$COMPOSE_FILE")
    
    cd "$COMPOSE_DIR"
    
    print_info "拉取 Docker 镜像..."
    docker compose pull
    
    print_info "启动容器..."
    docker compose up -d
    
    # 等待服务启动
    print_info "等待服务启动..."
    sleep 5
    
    # 检查服务状态
    if docker ps | grep -q iptv_nginx && \
       docker ps | grep -q iptv_fetcher && \
       docker ps | grep -q iptv_speedtest; then
        print_success "所有服务启动成功!"
    else
        print_error "服务启动失败，请检查日志"
        docker compose logs
        exit 1
    fi
}

# 显示部署结果
show_result() {
    print_step "部署完成!"
    
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         服务访问地址                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}主配置:${NC}   http://${SERVER_IP}:${HTTP_PORT}/myiptv.json"
    echo -e "  ${BLUE}直播源:${NC}   http://${SERVER_IP}:${HTTP_PORT}/tvbox.m3u"
    echo -e "  ${BLUE}文件浏览:${NC} http://${SERVER_IP}:${HTTP_PORT}/"
    echo ""
    
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  查看日志: cd $DATA_DIR/../ && docker compose logs -f"
    echo "  重启服务: cd $DATA_DIR/../ && docker compose restart"
    echo "  停止服务: cd $DATA_DIR/../ && docker compose down"
    echo ""
    
    echo -e "${YELLOW}数据目录:${NC}"
    echo "  $DATA_DIR"
    echo ""
}

# 主流程
main() {
    welcome
    check_docker
    config_data_dir
    config_port
    config_source
    config_interval
    clone_scripts
    generate_compose
    start_services
    show_result
}

# 执行主流程
main "$@"
