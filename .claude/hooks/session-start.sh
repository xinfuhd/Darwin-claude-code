#!/bin/bash
# =============================================================
# session-start.sh — 龙虾 Web 会话启动钩子
# 在 Claude Code on the web 中安装依赖，确保工具就绪
# =============================================================
set -euo pipefail

# 只在远程（Web）环境中运行
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# ── 安装 Python 依赖（mag7-report.py 需要） ───────────────────
echo "▶ 安装 Python 依赖（yfinance, pandas）..."
pip install --quiet pandas 2>/dev/null && echo "  ✓ pandas 已就绪" || echo "  ⚠ pandas 安装失败（非致命）"
pip install --quiet --prefer-binary yfinance 2>/dev/null && echo "  ✓ yfinance 已就绪" || echo "  ⚠ yfinance 安装失败（非致命）"

# ── 检查核心工具 ──────────────────────────────────────────────
echo "▶ 检查核心工具..."
for tool in jq curl python3 bash; do
  if command -v "$tool" &>/dev/null; then
    echo "  ✓ $tool"
  else
    echo "  ⚠ 缺少工具：$tool"
  fi
done

# ── 确保脚本可执行 ─────────────────────────────────────────────
SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/scripts"
if [ -d "$SCRIPT_DIR" ]; then
  chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
  echo "  ✓ scripts/ 目录权限已设置"
fi

echo "✅ 龙虾 Web 会话环境准备完成"
