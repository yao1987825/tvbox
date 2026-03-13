#!/usr/bin/env python3
"""
IPTV 直播源测速清洗脚本
读取 iptv.m3u，对每个频道进行测速，清洗无效数据，保存到 SQLite 数据库
"""

import sqlite3
import subprocess
import json
import os
import time
import sys
from datetime import datetime
from pathlib import Path
import logging

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def init_database(db_path):
    """初始化 SQLite 数据库"""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 创建频道表
    c.execute('''
        CREATE TABLE IF NOT EXISTS channels (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL UNIQUE,
            group_name TEXT,
            status TEXT DEFAULT 'untested',
            response_time_ms INTEGER,
            last_test_time TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # 创建测速历史表
    c.execute('''
        CREATE TABLE IF NOT EXISTS speed_test_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            channel_id INTEGER NOT NULL,
            response_time_ms INTEGER,
            status TEXT,
            error_msg TEXT,
            test_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(channel_id) REFERENCES channels(id)
        )
    ''')
    
    # 创建统计表
    c.execute('''
        CREATE TABLE IF NOT EXISTS statistics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total_channels INTEGER,
            valid_channels INTEGER,
            invalid_channels INTEGER,
            avg_response_time_ms REAL,
            success_rate REAL,
            stat_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()
    logger.info(f"Database initialized: {db_path}")


def parse_m3u(m3u_file):
    """解析 M3U 文件"""
    channels = []
    
    if not os.path.exists(m3u_file):
        logger.warning(f"M3U file not found: {m3u_file}")
        return channels
    
    # 检查文件修改时间，避免在文件更新时读取
    file_mtime = os.path.getmtime(m3u_file)
    current_time = time.time()
    time_since_modification = current_time - file_mtime
    
    # 如果文件在最近10秒内被修改，等待10秒再读取
    if time_since_modification < 10:
        logger.info(f"M3U file was recently modified ({time_since_modification:.1f}s ago), waiting 10s to ensure file is stable...")
        time.sleep(10)
    
    try:
        with open(m3u_file, 'r', encoding='utf-8') as f:
            group_name = "未分类"
            for line in f:
                line = line.strip()
                
                if line.startswith('#EXTINF:'):
                    # 解析频道信息
                    parts = line.split(',', 1)
                    if len(parts) == 2:
                        name = parts[1].strip()
                        # 提取分组信息
                        if 'group-title=' in line:
                            group_part = line.split('group-title="')[1].split('"')[0]
                            group_name = group_part
                
                elif line and not line.startswith('#'):
                    # URL 行
                    channels.append({
                        'name': name if 'name' in locals() else '未知频道',
                        'url': line,
                        'group_name': group_name
                    })
        
        logger.info(f"Parsed {len(channels)} channels from {m3u_file}")
    except Exception as e:
        logger.error(f"Error parsing M3U file: {e}")
    
    return channels


def test_channel(url, timeout=5):
    """测速单个频道"""
    try:
        start_time = time.time()
        result = subprocess.run(
            ['curl', '-m', str(timeout), '-o', '/dev/null', '-s', '-w', '%{http_code}', url],
            capture_output=True,
            timeout=timeout + 1
        )
        elapsed_ms = int((time.time() - start_time) * 1000)
        http_code = result.stdout.decode().strip()
        
        # 判断状态：2xx 为有效，其他为无效
        if http_code.startswith('2'):
            return {
                'status': 'valid',
                'response_time_ms': elapsed_ms,
                'error_msg': None
            }
        else:
            return {
                'status': 'invalid',
                'response_time_ms': elapsed_ms,
                'error_msg': f'HTTP {http_code}'
            }
    
    except subprocess.TimeoutExpired:
        return {
            'status': 'timeout',
            'response_time_ms': timeout * 1000,
            'error_msg': 'Connection timeout'
        }
    except Exception as e:
        return {
            'status': 'error',
            'response_time_ms': None,
            'error_msg': str(e)
        }


def save_channel(conn, channel, test_result):
    """保存或更新频道数据"""
    c = conn.cursor()
    
    try:
        # 检查是否已存在
        c.execute('SELECT id FROM channels WHERE url = ?', (channel['url'],))
        existing = c.fetchone()
        
        now = datetime.now().isoformat()
        
        if existing:
            # 更新
            c.execute('''
                UPDATE channels 
                SET name = ?, group_name = ?, status = ?, response_time_ms = ?, last_test_time = ?, updated_at = ?
                WHERE url = ?
            ''', (
                channel['name'],
                channel['group_name'],
                test_result['status'],
                test_result['response_time_ms'],
                now,
                now,
                channel['url']
            ))
            channel_id = existing[0]
        else:
            # 插入
            c.execute('''
                INSERT INTO channels (name, url, group_name, status, response_time_ms, last_test_time, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                channel['name'],
                channel['url'],
                channel['group_name'],
                test_result['status'],
                test_result['response_time_ms'],
                now,
                now,
                now
            ))
            channel_id = c.lastrowid
        
        # 记录测速历史
        c.execute('''
            INSERT INTO speed_test_history (channel_id, response_time_ms, status, error_msg, test_time)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            channel_id,
            test_result['response_time_ms'],
            test_result['status'],
            test_result['error_msg'],
            now
        ))
        
        conn.commit()
        return True
    
    except Exception as e:
        logger.error(f"Error saving channel {channel['url']}: {e}")
        return False


def update_statistics(conn):
    """更新统计数据"""
    c = conn.cursor()
    
    try:
        c.execute('SELECT COUNT(*) FROM channels')
        total = c.fetchone()[0]
        
        c.execute("SELECT COUNT(*) FROM channels WHERE status = 'valid'")
        valid = c.fetchone()[0]
        
        c.execute("SELECT COUNT(*) FROM channels WHERE status != 'valid'")
        invalid = c.fetchone()[0]
        
        c.execute('SELECT AVG(response_time_ms) FROM channels WHERE response_time_ms IS NOT NULL')
        avg_time = c.fetchone()[0] or 0
        
        success_rate = (valid / total * 100) if total > 0 else 0
        
        c.execute('''
            INSERT INTO statistics (total_channels, valid_channels, invalid_channels, avg_response_time_ms, success_rate)
            VALUES (?, ?, ?, ?, ?)
        ''', (total, valid, invalid, avg_time, success_rate))
        
        conn.commit()
        
        logger.info(f"Statistics: total={total}, valid={valid}, invalid={invalid}, avg_time={avg_time:.0f}ms, success_rate={success_rate:.2f}%")
    
    except Exception as e:
        logger.error(f"Error updating statistics: {e}")


def generate_tv_m3u(db_path, tv_m3u_path):
    """生成 tv.m3u 文件，只包含有效频道"""
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # 查询所有有效频道，按分组排序
        c.execute('''
            SELECT name, url, group_name, response_time_ms
            FROM channels
            WHERE status = 'valid'
            ORDER BY group_name, response_time_ms
        ''')
        
        valid_channels = c.fetchall()
        conn.close()
        
        if not valid_channels:
            logger.warning("No valid channels found, skipping tv.m3u generation")
            return False
        
        # 生成 M3U 文件
        with open(tv_m3u_path, 'w', encoding='utf-8') as f:
            f.write('#EXTM3U\n')
            
            current_group = None
            for name, url, group_name, response_time_ms in valid_channels:
                # 添加分组标题
                if group_name != current_group:
                    current_group = group_name
                    f.write(f'\n# ===== {current_group} =====\n')
                
                # 写入频道信息
                extinf = f'#EXTINF:-1 group-title="{group_name}" tvg-name="{name}",{name}'
                f.write(f'{extinf}\n{url}\n')
        
        logger.info(f"Generated tv.m3u with {len(valid_channels)} valid channels: {tv_m3u_path}")
        return True
    
    except Exception as e:
        logger.error(f"Error generating tv.m3u: {e}")
        return False


def run_speedtest(m3u_file, db_path, tv_m3u_path=None, timeout=5):
    """执行完整的测速流程"""
    logger.info("=" * 50)
    logger.info("Starting IPTV speedtest and cleansing")
    logger.info("=" * 50)
    
    # 初始化数据库
    init_database(db_path)
    
    # 解析 M3U
    channels = parse_m3u(m3u_file)
    if not channels:
        logger.warning("No channels found")
        return
    
    # 连接数据库
    conn = sqlite3.connect(db_path)
    
    # 测速和保存
    tested = 0
    valid = 0
    invalid = 0
    
    for idx, channel in enumerate(channels, 1):
        logger.info(f"[{idx}/{len(channels)}] Testing: {channel['name']} - {channel['url'][:60]}")
        
        test_result = test_channel(channel['url'], timeout)
        
        if save_channel(conn, channel, test_result):
            tested += 1
            if test_result['status'] == 'valid':
                valid += 1
            else:
                invalid += 1
        
        # 显示进度
        if idx % 10 == 0:
            logger.info(f"Progress: {idx}/{len(channels)}")
    
    # 更新统计
    update_statistics(conn)
    
    # 生成 tv.m3u 文件（如果指定了路径）
    if tv_m3u_path:
        generate_tv_m3u(db_path, tv_m3u_path)
    
    conn.close()
    
    logger.info("=" * 50)
    logger.info(f"Speedtest completed: {tested} tested, {valid} valid, {invalid} invalid")
    logger.info("=" * 50)


def continuous_loop(m3u_file, db_path, tv_m3u_path=None, interval=3600, timeout=5):
    """连续循环执行测速"""
    logger.info(f"Starting continuous speedtest loop with interval: {interval}s")
    
    while True:
        try:
            run_speedtest(m3u_file, db_path, tv_m3u_path, timeout)
            logger.info(f"Next test in {interval}s...")
            time.sleep(interval)
        except Exception as e:
            logger.error(f"Error in continuous loop: {e}")
            logger.info("Retrying in 60s...")
            time.sleep(60)


if __name__ == '__main__':
    # 配置
    m3u_file = os.getenv('M3U_FILE', '/data/iptv.m3u')
    db_path = os.getenv('DB_PATH', '/data/iptv_speedtest.db')
    tv_m3u_path = os.getenv('TV_M3U_PATH', '/data/tv.m3u')  # tv.m3u 输出路径
    interval = int(os.getenv('TEST_INTERVAL', 3600))  # 默认每小时
    timeout = int(os.getenv('TEST_TIMEOUT', 5))  # 默认超时 5 秒
    
    # 等待 M3U 文件存在
    logger.info(f"Waiting for M3U file: {m3u_file}")
    while not os.path.exists(m3u_file):
        time.sleep(5)
    
    logger.info("M3U file found, starting speedtest")
    
    # 运行连续循环
    continuous_loop(m3u_file, db_path, tv_m3u_path, interval, timeout)
