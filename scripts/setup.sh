#!/bin/bash
# =============================================================
# 龙虾自主学习系统 — 一键安装脚本
# =============================================================
set -e

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================"
echo "  龙虾自主学习系统 — 安装中..."
echo "============================================"

# ── 1. 安装 MCP GitHub 服务 ──────────────────────────────────
echo ""
echo "▶ [1/5] 安装 MCP GitHub 服务..."
npm install -g @modelcontextprotocol/server-github 2>/dev/null || \
  npm install -g @modelcontextprotocol/server-github --legacy-peer-deps
echo "   ✓ MCP GitHub 服务已安装"

# ── 2. 配置 GitHub Token ─────────────────────────────────────
echo ""
echo "▶ [2/5] 配置 GitHub Token..."
if [ -z "$GITHUB_TOKEN" ]; then
  echo ""
  echo "   请前往 https://github.com/settings/tokens/new 创建 Token"
  echo "   权限勾选：repo (read), search (read)"
  echo ""
  read -p "   请输入你的 GitHub Token: " GITHUB_TOKEN
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "   ⚠ 未输入 Token，MCP GitHub 将以匿名模式运行（限速 60次/小时）"
  fi
fi

# 写入 shell 配置
SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
if ! grep -q "GITHUB_TOKEN" "$SHELL_RC" 2>/dev/null; then
  echo "export GITHUB_TOKEN='$GITHUB_TOKEN'" >> "$SHELL_RC"
  echo "   ✓ Token 已写入 $SHELL_RC"
fi
export GITHUB_TOKEN="$GITHUB_TOKEN"

# ── 3. 复制脚本到 ~/.claude ───────────────────────────────────
echo ""
echo "▶ [3/5] 安装学习脚本..."
mkdir -p "$CLAUDE_DIR/scripts"
cp "$REPO_DIR/scripts/repo-learner.sh"       "$CLAUDE_DIR/scripts/"
cp "$REPO_DIR/scripts/session-start-hook.sh"  "$CLAUDE_DIR/scripts/"
cp "$REPO_DIR/scripts/daily-review.sh"        "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*.sh
echo "   ✓ 脚本已安装到 $CLAUDE_DIR/scripts/"

# 初始化状态文件（避免第一次启动就触发复盘）
touch "$CLAUDE_DIR/last-daily-review" 2>/dev/null || true

# ── 4. 安装 repo 观察列表 ─────────────────────────────────────
echo ""
echo "▶ [4/5] 初始化仓库观察列表..."
if [ ! -f "$CLAUDE_DIR/repo-watchlist.txt" ]; then
  cp "$REPO_DIR/config/repo-watchlist.txt" "$CLAUDE_DIR/"
  echo "   ✓ 观察列表已创建：$CLAUDE_DIR/repo-watchlist.txt"
else
  echo "   - 观察列表已存在，跳过（不覆盖）"
fi

# ── 5. 更新 settings.json ──────────────────────────────────────
echo ""
echo "▶ [5/5] 更新 Claude 配置 (settings.json + hooks)..."
python3 "$REPO_DIR/scripts/update-settings.py" \
  "$CLAUDE_DIR/settings.json" \
  "$CLAUDE_DIR/scripts/session-start-hook.sh"
echo "   ✓ settings.json 已更新"

# ── 完成 ─────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ 安装完成！"
echo "============================================"
echo ""
echo "下一步："
echo "  1. 编辑仓库观察列表：$CLAUDE_DIR/repo-watchlist.txt"
echo "  2. 重启 claude（或新开会话）"
echo "  3. 对龙虾说：'去学习观察列表里的仓库'"
echo ""
echo "手动触发学习："
echo "  $CLAUDE_DIR/scripts/repo-learner.sh learn <repo-url>"
echo "  $CLAUDE_DIR/scripts/repo-learner.sh search '关键词'"
echo ""
echo "手动触发每日复盘："
echo "  $CLAUDE_DIR/scripts/daily-review.sh"
