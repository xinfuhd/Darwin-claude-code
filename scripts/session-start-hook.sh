#!/bin/bash
# =============================================================
# session-start-hook.sh — 龙虾会话启动钩子 v2
# 每次 claude 会话开始时自动执行
#
# 改进 v2：
#   - 自动检测并加载任务交接文件（模型切换记忆）
#   - 每日首次启动触发复盘分析（后台）
#   - 精简输出，避免冗余汇报浪费 token
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
LEARNER="$SCRIPTS_DIR/repo-learner.sh"
HANDOFF_SCRIPT="$SCRIPTS_DIR/session-handoff.sh"
REVIEW_SCRIPT="$SCRIPTS_DIR/daily-review.sh"
WATCHLIST="$CLAUDE_DIR/repo-watchlist.txt"
STATE_FILE="$CLAUDE_DIR/last-watchlist-update"
REVIEW_STATE="$CLAUDE_DIR/last-daily-review"
HANDOFF_FILE="$CLAUDE_DIR/handoff.md"
LOG="$CLAUDE_DIR/session-hook.log"

# 学习间隔：24小时（秒）
UPDATE_INTERVAL=86400

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>&1; }
today() { date '+%Y-%m-%d'; }

# ── 工具：确保脚本可执行 ─────────────────────────────────────
ensure_executable() {
  local script="$1"
  [ -f "$script" ] && chmod +x "$script"
}

# ── 检查是否需要更新知识库 ───────────────────────────────────
should_update_knowledge() {
  [ ! -f "$STATE_FILE" ] && return 0
  local last_update now
  last_update=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  [ $((now - last_update)) -gt $UPDATE_INTERVAL ]
}

# ── 检查是否需要每日复盘 ─────────────────────────────────────
should_daily_review() {
  [ ! -f "$REVIEW_STATE" ] && return 0
  local last_review
  last_review=$(cat "$REVIEW_STATE" 2>/dev/null || echo "1970-01-01")
  [ "$last_review" != "$(today)" ]
}

# ── 加载任务交接（若存在）────────────────────────────────────
load_handoff_if_exists() {
  [ ! -f "$HANDOFF_FILE" ] && return 0

  local created_time task_line
  created_time=$(grep "创建时间" "$HANDOFF_FILE" 2>/dev/null | head -1 | sed 's/.*: //')
  task_line=$(grep -A1 "^## 📋 当前任务" "$HANDOFF_FILE" 2>/dev/null | tail -1 | cut -c1-60)

  echo ""
  echo "╔═══════════════════════════════════════════════════╗"
  echo "║  🦞 检测到任务交接（$created_time）  ║"
  echo "╚═══════════════════════════════════════════════════╝"
  echo "   任务: $task_line"
  echo "   运行 \`session-handoff.sh load\` 查看完整上下文"
  echo ""

  log "检测到待加载的任务交接文件"
}

# ── 主流程 ───────────────────────────────────────────────────
main() {
  log "会话启动"

  # 确保各脚本可执行
  ensure_executable "$LEARNER"
  ensure_executable "$HANDOFF_SCRIPT"
  ensure_executable "$REVIEW_SCRIPT"

  # ── 步骤1：初始化知识库（首次）──
  if [ -f "$LEARNER" ]; then
    "$LEARNER" init >> "$LOG" 2>&1
  fi

  # ── 步骤2：任务交接提示（精简，不展开全文）──
  load_handoff_if_exists

  # ── 步骤3：每日复盘（后台，每天首次触发）──
  if should_daily_review && [ -f "$REVIEW_SCRIPT" ]; then
    log "触发每日复盘（后台）..."
    (
      "$REVIEW_SCRIPT" generate >> "$LOG" 2>&1
      today > "$REVIEW_STATE"
      log "每日复盘完成"
    ) &
    echo "📋 今日复盘已在后台启动"
  fi

  # ── 步骤4：知识库学习（24小时间隔，后台）──
  if [ -f "$WATCHLIST" ] && should_update_knowledge && [ -f "$LEARNER" ]; then
    log "触发知识库更新（后台）..."
    (
      "$LEARNER" watchlist >> "$LOG" 2>&1
      date +%s > "$STATE_FILE"
      log "知识库更新完成"
    ) &
    echo "📚 知识库更新已在后台启动"
  fi

  # ── 步骤5：简洁状态摘要（仅一行，不废话）──
  local kb_size="N/A"
  [ -f "$CLAUDE_DIR/CLAUDE.md" ] && kb_size=$(du -k "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null | cut -f1 || echo "?")

  local last_learn_ago="未知"
  if [ -f "$STATE_FILE" ]; then
    local last_ts now diff_h
    last_ts=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    diff_h=$(( (now - last_ts) / 3600 ))
    last_learn_ago="${diff_h}h前"
  fi

  echo "[龙虾] 知识库: ${kb_size}KB | 上次学习: $last_learn_ago | 就绪 ✅"
  echo ""

  log "会话启动完成"
}

main
exit 0
