#!/bin/bash
# =============================================================
# session-start-hook.sh — 龙虾会话启动钩子
# 每次 claude 会话开始时自动执行
# 改进：减少噪音输出、读取任务交接、触发每日复盘
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
LEARNER="$CLAUDE_DIR/scripts/repo-learner.sh"
DAILY_REVIEW="$CLAUDE_DIR/scripts/daily-review.sh"
WATCHLIST="$CLAUDE_DIR/repo-watchlist.txt"
HANDOVER_FILE="$CLAUDE_DIR/handover.md"
STATE_FILE="$CLAUDE_DIR/last-watchlist-update"
REVIEW_STATE="$CLAUDE_DIR/last-daily-review"
LOG="$CLAUDE_DIR/session-hook.log"

# 学习间隔：24小时（秒）
UPDATE_INTERVAL=86400
# 复盘间隔：24小时
REVIEW_INTERVAL=86400

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>&1; }

# 检查距上次操作是否已超过指定间隔
should_run() {
  local state_file="$1"
  local interval="${2:-$UPDATE_INTERVAL}"
  [ ! -f "$state_file" ] && return 0
  local last
  last=$(cat "$state_file" 2>/dev/null || echo 0)
  # 验证读取到的是合法的数字时间戳，防止文件损坏导致算术错误
  if ! [[ "$last" =~ ^[0-9]+$ ]]; then
    last=0
  fi
  local now
  now=$(date +%s)
  [ $((now - last)) -gt "$interval" ]
}

# ── 读取并展示任务交接信息 ──────────────────────────────────
show_handover() {
  if [ ! -f "$HANDOVER_FILE" ]; then
    return 0
  fi

  # 检查是否有未完成任务
  local pending
  pending=$(grep -c '^\- \[ \]' "$HANDOVER_FILE" 2>/dev/null || echo 0)

  if [ "$pending" -gt 0 ]; then
    echo ""
    echo "📋 【任务交接】发现 $pending 个未完成任务，请执行：cat ~/.claude/handover.md"
  fi
}

# ── 触发每日复盘 ──────────────────────────────────────────
trigger_daily_review() {
  if ! should_run "$REVIEW_STATE" "$REVIEW_INTERVAL"; then
    return 0
  fi

  if [ -f "$DAILY_REVIEW" ]; then
    log "触发每日复盘..."
    bash "$DAILY_REVIEW" >> "$LOG" 2>&1
    date +%s > "$REVIEW_STATE"
  fi
}

# ── 后台更新仓库知识库 ──────────────────────────────────
update_watchlist() {
  if [ ! -f "$WATCHLIST" ] || ! should_run "$STATE_FILE"; then
    return 0
  fi

  if [ ! -f "$LEARNER" ]; then
    return 0
  fi

  log "开始后台更新仓库知识库..."
  (
    "$LEARNER" watchlist >> "$LOG" 2>&1
    date +%s > "$STATE_FILE"
    log "仓库知识库更新完成"
  ) &
  # disown 确保父会话退出时后台子进程不被 SIGHUP 终止
  disown $!

  # 仅输出一行，不输出详细日志
  echo "🦞 知识库后台更新中（不影响当前会话）"
}

main() {
  log "会话启动"

  # 确保脚本可执行
  [ -f "$LEARNER" ] && chmod +x "$LEARNER"
  [ -f "$DAILY_REVIEW" ] && chmod +x "$DAILY_REVIEW"

  # 初始化知识库（如不存在）
  if [ -f "$LEARNER" ]; then
    "$LEARNER" init >> "$LOG" 2>&1
  fi

  # 展示任务交接（有未完成任务时才输出）
  show_handover

  # 触发每日复盘（如到时间）
  trigger_daily_review

  # 后台更新仓库知识库（如到时间）
  update_watchlist

  log "会话启动完成"
}

main
exit 0
