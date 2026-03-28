#!/bin/bash
# =============================================================
# stock-push.sh — 抓取科技股数据，用 Claude 分析后推送到 Telegram
#
# 用法：
#   ./scripts/stock-push.sh              # 分析 Mag7+TSM（默认）
#   ./scripts/stock-push.sh NVDA TSLA    # 只分析指定股票
#
# 依赖：
#   - claude CLI（已登录 claude.ai 账号）
#   - python3 + yfinance + pandas
#   - curl
#
# 配置：
#   cp scripts/.env.example scripts/.env
#   填入 TG_BOT_TOKEN 和 TG_CHAT_ID
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── 加载环境变量 ──────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ 找不到 $ENV_FILE，请先执行：cp scripts/.env.example scripts/.env 并填入配置"
    exit 1
fi
source "$ENV_FILE"

: "${TG_BOT_TOKEN:?'请在 .env 中设置 TG_BOT_TOKEN'}"
: "${TG_CHAT_ID:?'请在 .env 中设置 TG_CHAT_ID'}"

# ── 发送 Telegram 消息（自动分段，单段上限 4000 字符）──────────
tg_send() {
    local text="$1"
    local max_len=4000
    local total=${#text}
    local offset=0

    while [ $offset -lt $total ]; do
        local chunk="${text:$offset:$max_len}"
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TG_CHAT_ID}" \
            --data-urlencode "text=${chunk}" \
            -d parse_mode="Markdown" \
            > /dev/null
        offset=$((offset + max_len))
        [ $offset -lt $total ] && sleep 1
    done
}

# ── 推送纯文本通知（用于状态/错误提示）────────────────────────
tg_notify() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        --data-urlencode "text=$1" \
        > /dev/null
}

# ── 主流程 ────────────────────────────────────────────────────
TICKERS="${*:-}"  # 命令行参数，为空则分析全部

echo "📡 抓取股票数据..."
if [ -n "$TICKERS" ]; then
    RAW_DATA=$(python3 "$SCRIPT_DIR/mag7-report.py" --watch $TICKERS 2>/dev/null) || {
        tg_notify "❌ 数据抓取失败，请检查 VPS 网络连接"
        exit 1
    }
else
    RAW_DATA=$(python3 "$SCRIPT_DIR/mag7-report.py" 2>/dev/null) || {
        tg_notify "❌ 数据抓取失败，请检查 VPS 网络连接"
        exit 1
    }
fi

echo "🤖 Claude 分析中..."
ANALYSIS=$(echo "$RAW_DATA" | claude -p "
你是美股价值投资助手。以下是今日科技股财报数据，请做简洁的中文分析。

要求：
1. 先列出 3 个最值得关注的亮点（涨幅/低估/成长加速）
2. 再列出 2 个主要风险
3. 给出今日「最值得关注」的 1-2 只股票及简要理由
4. 结尾一句风险提示
5. 全文控制在 600 字以内，用 Markdown 格式

数据如下：
$RAW_DATA
" --output-format text 2>/dev/null) || {
    tg_notify "❌ Claude 分析失败，原始数据已生成但未能分析"
    # 失败时推送原始数据（截取前 3000 字）
    tg_send "📊 *今日科技股数据*（Claude 分析失败，推送原始数据）

\`\`\`
${RAW_DATA:0:3000}
\`\`\`"
    exit 1
}

echo "📬 推送到 Telegram..."
DATE=$(date "+%Y-%m-%d %H:%M")
tg_send "📈 *美股每日简报 | ${DATE}*

${ANALYSIS}

---
_数据来源：Yahoo Finance（15min延迟）_
_⚠️ 仅供参考，不构成投资建议_"

echo "✅ 已推送到 Telegram"
