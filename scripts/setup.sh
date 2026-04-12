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

# ── 2. 配置认证 Key ──────────────────────────────────────────
echo ""
echo "▶ [2/5] 配置认证 Key..."

SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"

# 检测当前认证环境
if [ -n "$CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST" ]; then
  echo "   ✓ 检测到平台托管认证（claude.ai/code 云端环境），跳过 Key 配置"
else
  # 配置 GitHub Token
  if [ -z "$GITHUB_TOKEN" ]; then
    echo ""
    echo "   请前往 https://github.com/settings/tokens/new 创建 Token"
    echo "   权限勾选：repo (read), search (read)"
    echo ""
    read -p "   请输入你的 GitHub Token（回车跳过）: " GITHUB_TOKEN
    if [ -z "$GITHUB_TOKEN" ]; then
      echo "   ⚠ 未输入 Token，MCP GitHub 将以匿名模式运行（限速 60次/小时）"
    fi
  fi
  if [ -n "$GITHUB_TOKEN" ] && ! grep -q "GITHUB_TOKEN" "$SHELL_RC" 2>/dev/null; then
    echo "export GITHUB_TOKEN='$GITHUB_TOKEN'" >> "$SHELL_RC"
    echo "   ✓ GitHub Token 已写入 $SHELL_RC"
  fi
  export GITHUB_TOKEN="$GITHUB_TOKEN"

  # 配置 LLM API Key（Anthropic 或 OpenRouter 二选一）
  echo ""
  if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$OPENROUTER_API_KEY" ]; then
    echo "   未检测到 LLM API Key，请选择认证方式："
    echo "   1) Anthropic API Key（直连 api.anthropic.com）"
    echo "   2) OpenRouter API Key（通过 openrouter.ai 路由，支持 Hermes 等服务）"
    echo "   3) 跳过（已有其他配置）"
    read -p "   请输入选项 [1/2/3]: " LLM_CHOICE
    case "$LLM_CHOICE" in
      1)
        read -p "   请输入 Anthropic API Key (sk-ant-...): " ANTHROPIC_API_KEY
        if [ -n "$ANTHROPIC_API_KEY" ] && ! grep -q "ANTHROPIC_API_KEY" "$SHELL_RC" 2>/dev/null; then
          echo "export ANTHROPIC_API_KEY='$ANTHROPIC_API_KEY'" >> "$SHELL_RC"
          echo "   ✓ Anthropic API Key 已写入 $SHELL_RC"
        fi
        export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
        ;;
      2)
        read -p "   请输入 OpenRouter API Key (sk-or-...): " OPENROUTER_API_KEY
        if [ -n "$OPENROUTER_API_KEY" ] && ! grep -q "OPENROUTER_API_KEY" "$SHELL_RC" 2>/dev/null; then
          echo "export OPENROUTER_API_KEY='$OPENROUTER_API_KEY'" >> "$SHELL_RC"
          echo "   ✓ OpenRouter API Key 已写入 $SHELL_RC"
        fi
        export OPENROUTER_API_KEY="$OPENROUTER_API_KEY"
        ;;
      *)
        echo "   - 跳过 LLM API Key 配置"
        ;;
    esac
  elif [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "   ✓ 检测到 ANTHROPIC_API_KEY，跳过"
    if ! grep -q "ANTHROPIC_API_KEY" "$SHELL_RC" 2>/dev/null; then
      echo "export ANTHROPIC_API_KEY='$ANTHROPIC_API_KEY'" >> "$SHELL_RC"
    fi
  elif [ -n "$OPENROUTER_API_KEY" ]; then
    echo "   ✓ 检测到 OPENROUTER_API_KEY，跳过"
    if ! grep -q "OPENROUTER_API_KEY" "$SHELL_RC" 2>/dev/null; then
      echo "export OPENROUTER_API_KEY='$OPENROUTER_API_KEY'" >> "$SHELL_RC"
    fi
  fi
fi

# ── 3. 复制脚本到 ~/.claude ───────────────────────────────────
echo ""
echo "▶ [3/5] 安装学习脚本..."
mkdir -p "$CLAUDE_DIR/scripts"
cp "$REPO_DIR/scripts/repo-learner.sh"       "$CLAUDE_DIR/scripts/"
cp "$REPO_DIR/scripts/session-start-hook.sh"  "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*.sh
echo "   ✓ 脚本已安装到 $CLAUDE_DIR/scripts/"

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
