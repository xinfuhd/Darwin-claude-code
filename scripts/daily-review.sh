#!/bin/bash
# =============================================================
# daily-review.sh — 龙虾每日复盘脚本
# 收集过去24小时运行数据，生成复盘报告，触发龙虾自主改进
#
# 调用方：session-start-hook.sh（每24小时自动触发）
# 也可手动执行：~/.claude/scripts/daily-review.sh
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HOOK_LOG="$CLAUDE_DIR/session-hook.log"
LEARNER_LOG="$CLAUDE_DIR/learner.log"
MODEL_LOG="$CLAUDE_DIR/model-log.md"
REVIEW_FILE="$CLAUDE_DIR/daily-review.md"
HANDOVER_FILE="$CLAUDE_DIR/handover.md"
TODAY=$(date '+%Y-%m-%d')

# ── 统计指标 ────────────────────────────────────────────────

count_in_log() {
  local logfile="$1" pattern="$2"
  grep -c "$pattern" "$logfile" 2>/dev/null || echo 0
}

get_recent_lines() {
  local logfile="$1" n="${2:-30}"
  tail -"$n" "$logfile" 2>/dev/null || echo "（无日志）"
}

# ── 收集数据 ─────────────────────────────────────────────────

SESSION_COUNT=$(count_in_log "$HOOK_LOG" "会话启动$")
ERROR_COUNT=$(count_in_log "$HOOK_LOG" "❌\|error\|fail\|Error\|FAIL")
LEARN_COUNT=$(count_in_log "$LEARNER_LOG" "学习完成")

# 从日志中提取最近的错误
RECENT_ERRORS=""
if [ -f "$HOOK_LOG" ]; then
  RECENT_ERRORS=$(grep -i "❌\|error\|fail" "$HOOK_LOG" 2>/dev/null | tail -10 || echo "")
fi
if [ -f "$LEARNER_LOG" ]; then
  LEARNER_ERRORS=$(grep -i "❌\|error\|fail" "$LEARNER_LOG" 2>/dev/null | tail -10 || echo "")
  [ -n "$LEARNER_ERRORS" ] && RECENT_ERRORS="$RECENT_ERRORS
$LEARNER_ERRORS"
fi

# 模型限流记录
MODEL_EVENTS=""
if [ -f "$MODEL_LOG" ]; then
  MODEL_EVENTS=$(tail -20 "$MODEL_LOG" 2>/dev/null || echo "")
fi

# 未完成任务数
PENDING_TASKS=0
if [ -f "$HANDOVER_FILE" ]; then
  PENDING_TASKS=$(grep -c '^\- \[ \]' "$HANDOVER_FILE" 2>/dev/null || echo 0)
fi

# ── 写入复盘报告 ────────────────────────────────────────────

cat > "$REVIEW_FILE" << REPORT_EOF
# 龙虾每日复盘报告 — $TODAY

## 今日运行数据
| 指标 | 数值 |
|------|------|
| 会话次数 | $SESSION_COUNT |
| 错误次数 | $ERROR_COUNT |
| 仓库学习 | $LEARN_COUNT 个 |
| 未完成任务 | $PENDING_TASKS 个 |

## 近期错误记录
${RECENT_ERRORS:-（无错误，运行正常）}

## 模型限流/降级事件
${MODEL_EVENTS:-（无限流事件）}

## 系统日志（最近30条）
$(get_recent_lines "$HOOK_LOG" 30)

---
*报告生成时间：$(date '+%Y-%m-%d %H:%M:%S')，由 daily-review.sh 自动生成*
REPORT_EOF

# ── 输出给龙虾的复盘指令 ────────────────────────────────────

echo ""
echo "📊 【每日复盘】$(date '+%Y-%m-%d') — 已收集今日运行数据"
echo "   错误次数：$ERROR_COUNT | 会话次数：$SESSION_COUNT | 未完成任务：$PENDING_TASKS 个"
echo ""
echo "请执行以下复盘流程："
echo "  1. cat ~/.claude/daily-review.md   （查看详细数据）"
echo "  2. 分析常见错误和 token 浪费点"
echo "  3. 提出改进方案（需修改配置的必须请示用户）"
echo "  4. 将改进记录追加到 ~/.claude/CLAUDE.md 的"改进日志"区域"
