#!/bin/bash
# =============================================================
# session-start-hook.sh — 龙虾会话启动钩子
# 每次 claude 会话开始时自动执行
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
LEARNER="$CLAUDE_DIR/scripts/repo-learner.sh"
WATCHLIST="$CLAUDE_DIR/repo-watchlist.txt"
STATE_FILE="$CLAUDE_DIR/last-watchlist-update"
LOG="$CLAUDE_DIR/session-hook.log"

# 学习间隔：24小时（秒）
UPDATE_INTERVAL=86400

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>&1; }

# ── 只在间隔时间后才重新学习，避免每次启动都慢 ──────────────
should_update() {
  [ ! -f "$STATE_FILE" ] && return 0   # 从未更新过
  local last_update
  last_update=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  local now
  now=$(date +%s)
  [ $((now - last_update)) -gt $UPDATE_INTERVAL ]
}

check_auth_env() {
  if [ -n "$CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST" ]; then
    # claude.ai/code 云端环境：认证由平台托管
    log "检测到平台托管认证环境（CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1）"
  elif [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$OPENROUTER_API_KEY" ]; then
    # 没有任何 API Key 配置
    log "警告：未找到 LLM API Key（ANTHROPIC_API_KEY 和 OPENROUTER_API_KEY 均未设置）"
    echo "⚠ 未找到 LLM API Key，Claude Code 可能无法正常使用"
    echo "  → 如使用 Hermes/OpenRouter：export OPENROUTER_API_KEY='sk-or-v1-xxx'"
    echo "  → 如直连 Anthropic：        export ANTHROPIC_API_KEY='sk-ant-xxx'"
    echo "  → 运行安装脚本重新配置：    ~/.claude/scripts/setup.sh"
  fi
}

main() {
  log "会话启动钩子触发"

  # 检测认证环境，提前提示
  check_auth_env

  # 确保脚本可执行
  [ -f "$LEARNER" ] && chmod +x "$LEARNER"

  # 初始化知识库（如不存在）
  if [ -f "$LEARNER" ]; then
    "$LEARNER" init >> "$LOG" 2>&1
  fi

  # 检查是否需要更新观察列表
  if [ -f "$WATCHLIST" ] && should_update && [ -f "$LEARNER" ]; then
    log "开始后台更新仓库知识库..."

    # 后台执行，不阻塞会话启动
    (
      "$LEARNER" watchlist >> "$LOG" 2>&1
      date +%s > "$STATE_FILE"
      log "仓库知识库更新完成"
    ) &

    # 输出到 claude（会话启动消息）
    echo "🦞 知识库更新已在后台启动，不影响当前会话"
  else
    local last_update
    last_update=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    if [ "$last_update" -gt 0 ] 2>/dev/null; then
      log "知识库在 24 小时内已更新，跳过"
    fi
  fi

  log "会话启动钩子完成"
}

main
exit 0
