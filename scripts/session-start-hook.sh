#!/bin/bash
# =============================================================
# session-start-hook.sh — 龙虾会话启动钩子
# 每次 claude 会话开始时自动执行
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
LEARNER="$CLAUDE_DIR/scripts/repo-learner.sh"
WATCHLIST="$CLAUDE_DIR/repo-watchlist.txt"
STATE_FILE="$CLAUDE_DIR/last-watchlist-update"
REVIEW_SCRIPT="$CLAUDE_DIR/scripts/daily-review.sh"
REVIEW_FILE="$CLAUDE_DIR/daily-review.md"
TASK_FILE="$CLAUDE_DIR/current-task.md"
LOG="$CLAUDE_DIR/session-hook.log"

# 知识库更新间隔：72小时（问题2：降低频率）
UPDATE_INTERVAL=259200

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>&1; }

should_update() {
  [ ! -f "$STATE_FILE" ] && return 0
  local last_update
  last_update=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  local now
  now=$(date +%s)
  [ $((now - last_update)) -gt $UPDATE_INTERVAL ]
}

should_daily_review() {
  local review_state="$CLAUDE_DIR/last-daily-review"
  [ ! -f "$review_state" ] && return 0
  local last
  last=$(cat "$review_state" 2>/dev/null || echo 0)
  local now
  now=$(date +%s)
  [ $((now - last)) -gt 86400 ]
}

main() {
  log "会话启动"

  [ -f "$LEARNER" ] && chmod +x "$LEARNER"

  if [ -f "$LEARNER" ]; then
    "$LEARNER" init >> "$LOG" 2>&1
  fi

  # ── 问题4：展示当前任务日志（模型切换后恢复上下文）────────
  if [ -f "$TASK_FILE" ] && [ -s "$TASK_FILE" ]; then
    echo "━━━ 上次任务状态 ━━━"
    cat "$TASK_FILE"
    echo "━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi

  # ── 问题5：每日复盘（后台生成，下次会话展示）───────────────
  if should_daily_review && [ -f "$REVIEW_SCRIPT" ]; then
    (
      bash "$REVIEW_SCRIPT" > "$REVIEW_FILE" 2>/dev/null
      date +%s > "$CLAUDE_DIR/last-daily-review"
      log "每日复盘已生成"
    ) &
  elif [ -f "$REVIEW_FILE" ] && [ -s "$REVIEW_FILE" ]; then
    # 展示最近的复盘报告
    local review_age=$(( $(date +%s) - $(stat -c %Y "$REVIEW_FILE" 2>/dev/null || echo 0) ))
    if [ "$review_age" -lt 172800 ]; then  # 48小时内的复盘才展示
      echo "━━━ 昨日复盘 ━━━"
      cat "$REVIEW_FILE"
      echo "━━━━━━━━━━━━━━━━"
      echo ""
    fi
  fi

  # ── 问题2：知识库更新（72小时一次，后台静默）────────────────
  if [ -f "$WATCHLIST" ] && should_update && [ -f "$LEARNER" ]; then
    log "后台更新知识库..."
    (
      "$LEARNER" watchlist >> "$LOG" 2>&1
      date +%s > "$STATE_FILE"
      log "知识库更新完成"
    ) &
    # 只输出一行，不刷屏
    echo "🦞 知识库后台更新中（72h 一次）"
  fi

  log "启动钩子完成"
}

main
exit 0
