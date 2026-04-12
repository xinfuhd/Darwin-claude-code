#!/bin/bash
# =============================================================
# 龙虾自主学习系统 — 一键安装脚本
# =============================================================
set -e

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"

# 记录本次选择的认证方式，供后续步骤使用
AUTH_MODE=""   # oauth | anthropic_key | openrouter_key | managed | skip

echo "============================================"
echo "  龙虾自主学习系统 — 安装中..."
echo "============================================"

# ── 1. 安装 MCP GitHub 服务 ──────────────────────────────────
echo ""
echo "▶ [1/6] 安装 MCP GitHub 服务..."
npm install -g @modelcontextprotocol/server-github 2>/dev/null || \
  npm install -g @modelcontextprotocol/server-github --legacy-peer-deps
echo "   ✓ MCP GitHub 服务已安装"

# ── 2. 配置 Claude 认证 ───────────────────────────────────────
echo ""
echo "▶ [2/6] 配置 Claude 认证..."

if [ -n "$CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST" ]; then
  # claude.ai/code 云端容器：认证由平台托管，无需任何操作
  echo "   ✓ 平台托管认证（claude.ai/code 云端），跳过"
  AUTH_MODE="managed"

elif [ -n "$ANTHROPIC_API_KEY" ]; then
  echo "   ✓ 检测到 ANTHROPIC_API_KEY，使用 Anthropic 直连"
  if ! grep -q "ANTHROPIC_API_KEY" "$SHELL_RC" 2>/dev/null; then
    echo "export ANTHROPIC_API_KEY='$ANTHROPIC_API_KEY'" >> "$SHELL_RC"
  fi
  AUTH_MODE="anthropic_key"

elif [ -n "$OPENROUTER_API_KEY" ]; then
  echo "   ✓ 检测到 OPENROUTER_API_KEY，使用 OpenRouter"
  if ! grep -q "OPENROUTER_API_KEY" "$SHELL_RC" 2>/dev/null; then
    echo "export OPENROUTER_API_KEY='$OPENROUTER_API_KEY'" >> "$SHELL_RC"
  fi
  AUTH_MODE="openrouter_key"

else
  echo ""
  echo "   请选择 Claude 认证方式："
  echo "   1) claude.ai OAuth 登录（推荐，有 claude.ai Pro/Team 订阅）"
  echo "   2) Anthropic API Key（sk-ant-...，在 console.anthropic.com 生成）"
  echo "   3) OpenRouter API Key（sk-or-...，通过 openrouter.ai 路由）"
  echo "   4) 跳过（稍后手动配置）"
  echo ""
  read -p "   请输入选项 [1/2/3/4]: " AUTH_CHOICE

  case "$AUTH_CHOICE" in
    1)
      AUTH_MODE="oauth"
      echo ""
      echo "   ── Claude OAuth 登录 ──"
      echo "   即将启动 OAuth 登录流程..."
      echo "   claude 会输出一个 URL，请在浏览器中打开并用 claude.ai 账号授权"
      echo ""
      # 启动 claude 做 OAuth 登录（非交互模式只做 auth）
      if command -v claude &>/dev/null; then
        claude auth login 2>/dev/null || \
          ( echo "   尝试另一种登录方式..."; claude login 2>/dev/null ) || \
          ( echo "   请手动运行：claude  然后按提示完成浏览器授权" )
      else
        echo "   ⚠ 未找到 claude 命令，请先安装 Claude Code："
        echo "     npm install -g @anthropic-ai/claude-code"
        echo "   安装后运行：claude  按提示完成 OAuth 授权"
      fi
      ;;
    2)
      AUTH_MODE="anthropic_key"
      read -p "   请输入 Anthropic API Key: " INPUT_KEY
      if [ -n "$INPUT_KEY" ]; then
        export ANTHROPIC_API_KEY="$INPUT_KEY"
        if ! grep -q "ANTHROPIC_API_KEY" "$SHELL_RC" 2>/dev/null; then
          echo "export ANTHROPIC_API_KEY='$INPUT_KEY'" >> "$SHELL_RC"
        fi
        echo "   ✓ Anthropic API Key 已写入 $SHELL_RC"
      fi
      ;;
    3)
      AUTH_MODE="openrouter_key"
      read -p "   请输入 OpenRouter API Key: " INPUT_KEY
      if [ -n "$INPUT_KEY" ]; then
        export OPENROUTER_API_KEY="$INPUT_KEY"
        if ! grep -q "OPENROUTER_API_KEY" "$SHELL_RC" 2>/dev/null; then
          echo "export OPENROUTER_API_KEY='$INPUT_KEY'" >> "$SHELL_RC"
        fi
        echo "   ✓ OpenRouter API Key 已写入 $SHELL_RC"
      fi
      ;;
    *)
      AUTH_MODE="skip"
      echo "   - 跳过认证配置"
      ;;
  esac
fi

# ── 3. 配置 GitHub Token ──────────────────────────────────────
echo ""
echo "▶ [3/6] 配置 GitHub Token（用于 MCP GitHub 服务）..."
if [ -z "$GITHUB_TOKEN" ]; then
  read -p "   请输入 GitHub Token（回车跳过）: " GITHUB_TOKEN
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "   ⚠ 跳过，MCP GitHub 将以匿名模式运行（限速 60次/小时）"
  fi
fi
if [ -n "$GITHUB_TOKEN" ] && ! grep -q "GITHUB_TOKEN" "$SHELL_RC" 2>/dev/null; then
  echo "export GITHUB_TOKEN='$GITHUB_TOKEN'" >> "$SHELL_RC"
  echo "   ✓ GitHub Token 已写入 $SHELL_RC"
fi
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ── 4. 复制脚本到 ~/.claude ───────────────────────────────────
echo ""
echo "▶ [4/6] 安装学习脚本..."
mkdir -p "$CLAUDE_DIR/scripts"
cp "$REPO_DIR/scripts/repo-learner.sh"       "$CLAUDE_DIR/scripts/"
cp "$REPO_DIR/scripts/session-start-hook.sh"  "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*.sh
echo "   ✓ 脚本已安装到 $CLAUDE_DIR/scripts/"

# ── 5. 安装 repo 观察列表 ─────────────────────────────────────
echo ""
echo "▶ [5/6] 初始化仓库观察列表..."
if [ ! -f "$CLAUDE_DIR/repo-watchlist.txt" ]; then
  cp "$REPO_DIR/config/repo-watchlist.txt" "$CLAUDE_DIR/"
  echo "   ✓ 观察列表已创建：$CLAUDE_DIR/repo-watchlist.txt"
else
  echo "   - 观察列表已存在，跳过（不覆盖）"
fi

# ── 6. 更新 settings.json ─────────────────────────────────────
echo ""
echo "▶ [6/6] 更新 Claude 配置 (settings.json + hooks)..."

# 根据认证方式传递 provider 参数
PROVIDER_ARG=""
case "$AUTH_MODE" in
  oauth|anthropic_key|managed)
    PROVIDER_ARG="anthropic"
    ;;
  openrouter_key)
    PROVIDER_ARG="openrouter"
    ;;
esac

python3 "$REPO_DIR/scripts/update-settings.py" \
  "$CLAUDE_DIR/settings.json" \
  "$CLAUDE_DIR/scripts/session-start-hook.sh" \
  "$PROVIDER_ARG"
echo "   ✓ settings.json 已更新"

# ── 完成 ─────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ 安装完成！"
echo "============================================"
echo ""

# 根据认证方式给出下一步提示
case "$AUTH_MODE" in
  oauth)
    echo "认证方式：Claude OAuth（claude.ai 账号）"
    echo ""
    if ! command -v claude &>/dev/null; then
      echo "  ⚠ 请先安装 Claude Code："
      echo "    npm install -g @anthropic-ai/claude-code"
      echo "  然后运行 claude 完成 OAuth 授权"
    else
      echo "  下一步：重新启动 claude，确认 /model 显示 Provider: Anthropic"
    fi
    ;;
  anthropic_key)
    echo "认证方式：Anthropic API Key（直连 api.anthropic.com）"
    ;;
  openrouter_key)
    echo "认证方式：OpenRouter API Key"
    ;;
  managed)
    echo "认证方式：平台托管（claude.ai/code 云端）"
    ;;
  *)
    echo "  ⚠ 认证方式未配置，请运行 claude 并完成登录"
    ;;
esac
echo ""
echo "其他步骤："
echo "  1. 编辑仓库观察列表：$CLAUDE_DIR/repo-watchlist.txt"
echo "  2. 重启 claude（或新开会话）"
echo "  3. 对龙虾说：'去学习观察列表里的仓库'"
echo ""
echo "手动触发学习："
echo "  $CLAUDE_DIR/scripts/repo-learner.sh learn <repo-url>"
echo "  $CLAUDE_DIR/scripts/repo-learner.sh search '关键词'"
