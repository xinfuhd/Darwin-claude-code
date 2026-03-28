#!/usr/bin/env python3
# =============================================================
# tg-bot.py — Telegram 双向对话 Bot
#
# 用法：python3 scripts/tg-bot.py
#
# 功能：
#   - 接收 Telegram 消息，转发给 Claude 处理
#   - 只响应 .env 中配置的 TG_CHAT_ID（防止他人使用）
#   - 内置美股投资助手上下文
#   - 支持特殊命令：/report /help /start
#
# 依赖：pip install requests
# =============================================================

import os
import sys
import time
import subprocess
import requests
import logging
from pathlib import Path

# ── 加载 .env ──────────────────────────────────────────────────
ENV_FILE = Path(__file__).parent / ".env"
if not ENV_FILE.exists():
    print(f"❌ 找不到 {ENV_FILE}，请先配置")
    sys.exit(1)

for line in ENV_FILE.read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        os.environ[k.strip()] = v.strip()

TG_TOKEN = os.environ.get("TG_BOT_TOKEN", "")
TG_CHAT_ID = str(os.environ.get("TG_CHAT_ID", ""))

if not TG_TOKEN or not TG_CHAT_ID:
    print("❌ 请在 .env 中设置 TG_BOT_TOKEN 和 TG_CHAT_ID")
    sys.exit(1)

BASE_URL = f"https://api.telegram.org/bot{TG_TOKEN}"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler()]
)
log = logging.getLogger(__name__)

SYSTEM_PROMPT = """你是一个专业的美股投资助手，帮助用户分析股票。

核心能力：
- 分析个股技术面和基本面
- 估值判断（PE/PB/ROE/自由现金流/格雷厄姆公式）
- 市场趋势和投资策略建议
- 风险评估和止损建议

回复要求：
- 使用中文回复
- 简洁直接，重点突出
- 每次分析必须附风险提示
- 不预测具体价格，不保证收益
- 如需实时数据，提示用户当前无法联网查询

当用户问股票分析时，提供技术面+基本面双维度分析框架。"""


# ── Telegram API 封装 ──────────────────────────────────────────
def tg_send(chat_id: str, text: str):
    """发送消息，自动分段（Telegram 单条上限 4096 字符）"""
    max_len = 4000
    chunks = [text[i:i+max_len] for i in range(0, len(text), max_len)]
    for chunk in chunks:
        try:
            requests.post(f"{BASE_URL}/sendMessage", json={
                "chat_id": chat_id,
                "text": chunk,
                "parse_mode": "Markdown"
            }, timeout=10)
        except Exception as e:
            log.error(f"发送消息失败: {e}")
        if len(chunks) > 1:
            time.sleep(0.5)


def tg_send_typing(chat_id: str):
    """发送"正在输入"状态"""
    try:
        requests.post(f"{BASE_URL}/sendChatAction", json={
            "chat_id": chat_id,
            "action": "typing"
        }, timeout=5)
    except Exception:
        pass


def get_updates(offset: int = 0) -> list:
    try:
        resp = requests.get(f"{BASE_URL}/getUpdates", params={
            "offset": offset,
            "timeout": 30,
            "allowed_updates": ["message"]
        }, timeout=35)
        return resp.json().get("result", [])
    except Exception as e:
        log.error(f"获取消息失败: {e}")
        return []


# ── Claude 处理 ────────────────────────────────────────────────
def ask_claude(user_msg: str) -> str:
    prompt = f"{SYSTEM_PROMPT}\n\n用户问题：{user_msg}"
    try:
        result = subprocess.run(
            ["claude", "-p", prompt, "--output-format", "text"],
            capture_output=True,
            text=True,
            timeout=120
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        else:
            log.error(f"Claude 错误: {result.stderr}")
            return "❌ Claude 处理失败，请稍后重试"
    except subprocess.TimeoutExpired:
        return "⏱ Claude 响应超时（120s），请简化问题后重试"
    except FileNotFoundError:
        return "❌ 找不到 claude 命令，请确认 Claude Code 已安装并登录"
    except Exception as e:
        return f"❌ 出错了：{str(e)}"


# ── 特殊命令处理 ───────────────────────────────────────────────
def handle_command(cmd: str, chat_id: str):
    cmd = cmd.lower().split()[0]

    if cmd in ("/start", "/help"):
        tg_send(chat_id, """👋 *美股投资助手已就绪*

*直接发送你的问题，例如：*
• 帮我分析 NVDA
• MSFT 现在估值贵吗？
• 科技股现在能买吗？
• 解释一下 PEG ratio

*特殊命令：*
/report — 推送今日 Mag7 简报
/help — 显示帮助

⚠️ 所有分析仅供参考，不构成投资建议""")

    elif cmd == "/report":
        tg_send(chat_id, "📡 正在生成今日简报，请稍候（约30秒）...")
        script = Path(__file__).parent / "stock-push.sh"
        try:
            result = subprocess.run(
                ["bash", str(script)],
                capture_output=True, text=True, timeout=180,
                cwd=str(script.parent.parent)
            )
            if result.returncode != 0:
                tg_send(chat_id, f"❌ 简报生成失败：{result.stderr[:200]}")
        except subprocess.TimeoutExpired:
            tg_send(chat_id, "⏱ 简报生成超时，请稍后重试")
        except Exception as e:
            tg_send(chat_id, f"❌ 出错：{str(e)}")
    else:
        tg_send(chat_id, "❓ 未知命令，发送 /help 查看帮助")


# ── 主循环 ────────────────────────────────────────────────────
def main():
    log.info(f"🤖 Bot 启动，只响应 Chat ID: {TG_CHAT_ID}")
    tg_send(TG_CHAT_ID, "✅ *投资助手已上线*，发送 /help 查看用法")

    offset = 0
    while True:
        updates = get_updates(offset)

        for update in updates:
            offset = update["update_id"] + 1
            msg = update.get("message", {})
            chat_id = str(msg.get("chat", {}).get("id", ""))
            text = msg.get("text", "").strip()

            if not text or not chat_id:
                continue

            # 安全过滤：只响应配置的 Chat ID
            if chat_id != TG_CHAT_ID:
                log.warning(f"拒绝来自未授权用户的消息: {chat_id}")
                continue

            log.info(f"收到消息: {text[:50]}")

            # 特殊命令
            if text.startswith("/"):
                handle_command(text, chat_id)
                continue

            # 普通消息 → Claude
            tg_send_typing(chat_id)
            reply = ask_claude(text)
            tg_send(chat_id, reply)

        if not updates:
            time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Bot 已停止")
