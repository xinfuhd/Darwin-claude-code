#!/bin/bash
# =============================================================
# session-start.sh — 龙虾学习系统依赖安装钩子
# 仅在 Claude Code 远程环境（web）中运行
# =============================================================
set -euo pipefail

# 仅在远程环境中执行
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo "▶ 安装龙虾学习系统依赖..."

# ── 1. 安装 MCP GitHub 服务（npm 全局包）────────────────────
if ! command -v mcp-server-github &>/dev/null; then
  echo "  安装 @modelcontextprotocol/server-github..."
  npm install -g @modelcontextprotocol/server-github
else
  echo "  ✓ mcp-server-github 已就绪"
fi

# ── 2. 安装 Python 依赖（mag7-report.py 使用）───────────────
echo "  安装 Python 依赖（yfinance、pandas）..."
pip install --quiet --prefer-binary yfinance pandas

# ── 3. 确保学习脚本可执行 ───────────────────────────────────
SCRIPTS_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
  chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
  echo "  ✓ 脚本权限已设置"
fi

echo "✅ 依赖安装完成，龙虾准备就绪"
