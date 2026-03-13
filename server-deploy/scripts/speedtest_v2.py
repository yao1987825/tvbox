#!/usr/bin/env python3
"""
IPTV 直播源测速清洗脚本 V2
- 每3分钟测速 iptv.m3u，生成 tv.m3u 和 tvbox.m3u
- 每小时重新从GitHub获取数据
"""

import subprocess
import os
import time
import re
import logging
import signal
import urllib.request
import shutil

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

running = True


def signal_handler(signum, frame):
    global running
    logger.info("Received shutdown signal")
    running = False


signal.signal(signal.SIGTERM, signal_handler)


M3U_URL = "https://gh-proxy.com/https://raw.githubusercontent.com/yaojiwei520/IPTV/refs/heads/main/iptv.m3u"
FETCH_INTERVAL = 3600


def fetch_m3u(url, output_file):
    """从GitHub获取M3U文件"""
    logger.info(f"Fetching M3U from: {url}")
    try:
        temp_file = output_file + ".tmp"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as response:
            with open(temp_file, "wb") as f:
                shutil.copyfileobj(response, f)
        os.replace(temp_file, output_file)
        logger.info(f"M3U updated: {output_file}")
        return True
    except Exception as e:
        logger.error(f"Failed to fetch M3U: {e}")
        return False


def parse_m3u(m3u_file):
    """解析M3U文件"""
    channels = []

    if not os.path.exists(m3u_file):
        logger.warning(f"M3U file not found: {m3u_file}")
        return channels

    try:
        with open(m3u_file, "r", encoding="utf-8") as f:
            group_name = ""
            for line in f:
                line = line.strip()

                if line.startswith("#EXTINF:"):
                    if "group-title=" in line:
                        try:
                            group_name = line.split('group-title="')[1].split('"')[0]
                        except:
                            group_name = ""
                    if "," in line:
                        name = line.split(",")[-1]

                elif line and not line.startswith("#") and line.startswith("http"):
                    channels.append(
                        {"name": name, "url": line, "group_name": group_name}
                    )

        logger.info(f"Parsed {len(channels)} channels from {m3u_file}")
    except Exception as e:
        logger.error(f"Error parsing M3U: {e}")

    return channels


def test_channel(url, timeout=5):
    """测速单个频道"""
    try:
        start_time = time.time()

        result = subprocess.run(
            ["curl", "-m", str(timeout), "-s", "-w", "\nHTTP_CODE:%{http_code}", url],
            capture_output=True,
            timeout=timeout + 1,
            text=True,
        )

        elapsed_ms = int((time.time() - start_time) * 1000)
        content = result.stdout

        http_code = None
        for line in content.split("\n"):
            if line.startswith("HTTP_CODE:"):
                http_code = line.replace("HTTP_CODE:", "")
                break

        content_lines = [
            line for line in content.split("\n") if not line.startswith("HTTP_CODE:")
        ]
        content = "\n".join(content_lines)

        if not http_code or not http_code.startswith("2"):
            return {
                "valid": False,
                "response_time_ms": elapsed_ms,
                "error": f"HTTP {http_code or '000'}",
            }

        if ".m3u8" in url.lower():
            if "#EXTM3U" not in content:
                return {
                    "valid": False,
                    "response_time_ms": elapsed_ms,
                    "error": "Invalid m3u8",
                }
            if "#EXTINF" not in content and ".ts" not in content:
                return {
                    "valid": False,
                    "response_time_ms": elapsed_ms,
                    "error": "No media segments",
                }

        return {"valid": True, "response_time_ms": elapsed_ms, "error": None}

    except subprocess.TimeoutExpired:
        return {"valid": False, "response_time_ms": timeout * 1000, "error": "Timeout"}
    except Exception as e:
        return {"valid": False, "response_time_ms": None, "error": str(e)}


def generate_m3u(channels, output_file, tvbox_format=False):
    """生成M3U文件"""
    if not channels:
        logger.warning(f"No valid channels, skipping {output_file}")
        try:
            os.remove(output_file)
        except:
            pass
        return False

    try:
        with open(output_file, "w", encoding="utf-8") as f:
            if tvbox_format:
                f.write(
                    '#EXTM3U x-tvg-url="https://epg.51zmt.top:8080/api/diyp/epg.xml"\n'
                )
            else:
                f.write("#EXTM3U\n")

            for ch in channels:
                extinf = f'#EXTINF:-1 group-title="{ch["group_name"]}" tvg-name="{ch["name"]}",{ch["name"]}'
                f.write(f"{extinf}\n{ch['url']}\n")

        logger.info(f"Generated {output_file} with {len(channels)} channels")
        return True
    except Exception as e:
        logger.error(f"Error generating {output_file}: {e}")
        return False


def run_speedtest(m3u_file, tv_m3u_file, tvbox_m3u_file, timeout=5):
    """执行测速并生成文件"""
    logger.info("-" * 40)
    logger.info("Starting speedtest")

    channels = parse_m3u(m3u_file)
    if not channels:
        logger.warning("No channels found in iptv.m3u")
        return

    valid_channels = []

    for idx, ch in enumerate(channels, 1):
        logger.info(f"[{idx}/{len(channels)}] Testing: {ch['name']}")

        result = test_channel(ch["url"], timeout)

        if result["valid"]:
            valid_channels.append(ch)

        if idx % 10 == 0:
            logger.info(f"Progress: {idx}/{len(channels)}")

    total = len(channels)
    success_rate = (len(valid_channels) / total * 100) if total > 0 else 0

    logger.info(
        f"Result: {total} total, {len(valid_channels)} valid, {success_rate:.1f}% success"
    )

    generate_m3u(valid_channels, tv_m3u_file)
    generate_m3u(valid_channels, tvbox_m3u_file, tvbox_format=True)


def main():
    """主循环"""
    m3u_file = os.getenv("M3U_FILE", "/data/iptv.m3u")
    tv_m3u_file = os.getenv("TV_M3U_PATH", "/data/tv.m3u")
    tvbox_m3u_file = os.getenv("TVBOX_M3U_PATH", "/data/tvbox.m3u")
    test_interval = int(os.getenv("TEST_INTERVAL", 180))
    timeout = int(os.getenv("TEST_TIMEOUT", 5))

    logger.info("=" * 60)
    logger.info("IPTV Speedtest Service V2 Starting")
    logger.info("=" * 60)
    logger.info(f"M3U_FILE: {m3u_file}")
    logger.info(f"TV_M3U: {tv_m3u_file}")
    logger.info(f"TVBOX_M3U: {tvbox_m3u_file}")
    logger.info(f"TEST_INTERVAL: {test_interval}s")
    logger.info(f"TEST_TIMEOUT: {timeout}s")
    logger.info(f"FETCH_INTERVAL: {FETCH_INTERVAL}s")

    fetch_countdown = FETCH_INTERVAL

    while running:
        try:
            if not os.path.exists(m3u_file) or fetch_countdown <= 0:
                if fetch_m3u(M3U_URL, m3u_file):
                    fetch_countdown = FETCH_INTERVAL

            if os.path.exists(m3u_file):
                run_speedtest(m3u_file, tv_m3u_file, tvbox_m3u_file, timeout)
            else:
                logger.warning(f"Waiting for {m3u_file}...")

            for _ in range(test_interval):
                if not running:
                    break
                time.sleep(1)
            fetch_countdown -= test_interval

        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(60)

    logger.info("Service stopped")


if __name__ == "__main__":
    main()
