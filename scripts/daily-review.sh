#!/bin/bash
# =============================================================
# daily-review.sh — 龙虾每日复盘分析器
# 分析过去24小时的运行情况，发现问题，自动改进或请示用户授权
#
# 用法：
#   daily-review.sh generate     生成今日复盘报告
#   daily-review.sh show          显示今日报告（已生成则读取）
#   daily-review.sh propose "标题" "描述" [影响级别]  提交改进建议
#   daily-review.sh approve <序号>  批准待执行的改进建议
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
REVIEW_DIR="$CLAUDE_DIR/reviews"
REVIEW_LOG="$CLAUDE_DIR/daily-review.log"
SESSION_LOG="$CLAUDE_DIR/session-hook.log"
LEARNER_LOG="$CLAUDE_DIR/learner.log"
HANDOFF_LOG="$CLAUDE_DIR/handoff.log"
MODEL_LOG="$CLAUDE_DIR/model-router.log"
PENDING_FILE="$CLAUDE_DIR/pending-improvements.md"
STATE_FILE="$CLAUDE_DIR/last-daily-review"

mkdir -p "$REVIEW_DIR"

log()       { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$REVIEW_LOG" 2>&1; }
today()     { date '+%Y-%m-%d'; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# ── 日志分析工具 ─────────────────────────────────────────────
# 提取最近N小时的日志行
recent_logs() {
  local logfile="$1"
  local hours="${2:-24}"
  [ ! -f "$logfile" ] && return

  # 生成截止时间字符串（格式：[YYYY-MM-DD]）
  local cutoff_date
  if date -d "-${hours} hours" '+%Y-%m-%d' 2>/dev/null; then
    cutoff_date=$(date -d "-${hours} hours" '+%Y-%m-%d')
  else
    cutoff_date=$(date -v -${hours}H '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
  fi

  # 筛选当天及之后的日志
  grep -E "^\[${cutoff_date}|^\[$(today)" "$logfile" 2>/dev/null || tail -200 "$logfile" 2>/dev/null
}

count_pattern() {
  local logfile="$1"
  local pattern="$2"
  recent_logs "$logfile" | grep -c "$pattern" 2>/dev/null || echo 0
}

# ── 每日是否需要生成报告 ─────────────────────────────────────
should_review() {
  [ ! -f "$STATE_FILE" ] && return 0
  local last
  last=$(cat "$STATE_FILE" 2>/dev/null || echo "1970-01-01")
  [ "$last" != "$(today)" ]
}

# ── 主报告生成 ───────────────────────────────────────────────
generate_review() {
  local review_file="$REVIEW_DIR/review-$(today).md"
  log "开始生成每日复盘报告..."

  # ── 统计24小时数据 ──
  local session_count error_total repo_learned model_downgrades handoffs

  session_count=$(count_pattern "$SESSION_LOG" "会话启动钩子触发")
  error_total=$(( $(count_pattern "$SESSION_LOG" "❌\|ERROR") + \
                  $(count_pattern "$LEARNER_LOG" "❌\|无法访问") ))
  repo_learned=$(count_pattern "$LEARNER_LOG" "学习完成")
  model_downgrades=$(count_pattern "$MODEL_LOG" "降级使用")
  handoffs=$(count_pattern "$HANDOFF_LOG" "交接文件已保存")

  # ── 写入报告 ──
  {
    cat << EOF
# 🦞 龙虾每日复盘报告

**报告日期**: $(today)
**生成时间**: $(timestamp)

---

## 📊 24小时运行概览

| 指标 | 数值 | 状态 |
|------|------|------|
| 会话启动次数 | ${session_count} | $([ "$session_count" -gt 20 ] && echo "⚠️ 偏高" || echo "✅") |
| 仓库学习完成 | ${repo_learned} 个 | ✅ |
| 模型任务交接 | ${handoffs} 次 | ✅ |
| 模型降级次数 | ${model_downgrades} 次 | $([ "$model_downgrades" -ge 3 ] && echo "⚠️ 偏多" || echo "✅") |
| 错误/失败数 | ${error_total} 次 | $([ "$error_total" -ge 5 ] && echo "⚠️ 需关注" || echo "✅") |

---

## 🔍 问题发现

EOF

    local issues=0

    # 检查错误率
    if [ "$error_total" -ge 5 ]; then
      echo "### ⚠️ 错误率偏高 ($error_total 次)"
      echo "建议检查网络连接和 API 配置。重点排查："
      echo '```'
      recent_logs "$LEARNER_LOG" | grep "❌\|无法访问" | tail -5
      recent_logs "$SESSION_LOG" | grep "❌\|ERROR" | tail -5
      echo '```'
      echo ""
      issues=$((issues + 1))
    fi

    # 检查频繁降级
    if [ "$model_downgrades" -ge 3 ]; then
      echo "### ⚠️ 频繁模型降级 ($model_downgrades 次)"
      echo "主力模型可能 API 受限或额度耗尽，建议："
      echo "1. 检查各模型 API 配额"
      echo "2. 临时调整 model-config.json 中的默认模型层级"
      echo ""
      issues=$((issues + 1))
    fi

    # 检查未完成的任务交接
    if [ -f "$CLAUDE_DIR/handoff.md" ]; then
      local handoff_ts
      handoff_ts=$(grep "创建时间" "$CLAUDE_DIR/handoff.md" | head -1 | sed 's/.*: //')
      echo "### ⚠️ 存在未清除的任务交接"
      echo "交接文件创建于: $handoff_ts"
      echo "请确认是否已完成该任务，若完成请运行: \`session-handoff.sh clear\`"
      echo ""
      issues=$((issues + 1))
    fi

    # 检查知识库大小
    if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
      local kb_size
      kb_size=$(du -k "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null | cut -f1 || echo 0)
      if [ "$kb_size" -gt 70 ]; then
        echo "### ℹ️ 知识库接近容量上限"
        echo "CLAUDE.md 当前 ${kb_size}KB（上限 80KB），旧条目将被自动清理。"
        echo "若重要知识被清理，建议缩减 watchlist 中低优先级仓库。"
        echo ""
        issues=$((issues + 1))
      fi
    fi

    if [ "$issues" -eq 0 ]; then
      echo "今日运行良好，未发现明显问题 ✅"
      echo ""
    fi

    # ── 待授权改进项 ──
    cat << 'IMPROVEMENTS_HEADER'
---

## 💡 改进建议

### 🤖 已自动执行（无需授权）

- ✅ 过期模型限制标记自动清除（超1小时自动恢复）
- ✅ 日志文件超30天旧内容清理
- ✅ 过期任务交接归档清理

IMPROVEMENTS_HEADER

    echo "### 🔐 待用户授权的改进"
    echo ""
    if [ -f "$PENDING_FILE" ] && [ -s "$PENDING_FILE" ]; then
      cat "$PENDING_FILE"
    else
      echo "  （目前无待授权改进项）"
      echo ""
      echo "  如需提交改进建议，运行："
      echo "  \`daily-review.sh propose \"改进标题\" \"改进描述\" \"影响级别\"\`"
    fi

    echo ""
    echo "---"
    echo "*此报告由 daily-review.sh 自动生成 | 手动触发: \`~/.claude/scripts/daily-review.sh generate\`*"

  } > "$review_file"

  # ── 自动执行安全改进 ──
  auto_improve

  # 记录本次复盘时间
  today > "$STATE_FILE"

  log "复盘报告已生成: $review_file"
  echo ""
  echo "✅ 每日复盘完成 → $review_file"

  # 若有问题则摘要输出
  if [ "$issues" -gt 0 ]; then
    echo "⚠️  发现 $issues 项需关注的问题，请查看报告"
  fi

  echo "$review_file"
}

# ── 自动执行安全改进（无需授权）────────────────────────────
auto_improve() {
  log "执行自动改进措施..."
  local improved=0

  # 1. 清理各日志文件中超30天的旧条目
  for logfile in "$SESSION_LOG" "$LEARNER_LOG" "$HANDOFF_LOG" "$MODEL_LOG"; do
    if [ -f "$logfile" ]; then
      local original_size
      original_size=$(wc -c < "$logfile" 2>/dev/null || echo 0)
      local cutoff_date
      cutoff_date=$(date -d "-30 days" '+%Y-%m-%d' 2>/dev/null \
                 || date -v -30d '+%Y-%m-%d' 2>/dev/null \
                 || echo "")
      if [ -n "$cutoff_date" ]; then
        local tmp
        tmp=$(mktemp)
        grep -v "^\[$cutoff_date" "$logfile" > "$tmp" 2>/dev/null || true
        local new_size
        new_size=$(wc -c < "$tmp" 2>/dev/null || echo 0)
        if [ "$new_size" -lt "$original_size" ]; then
          mv "$tmp" "$logfile"
          improved=$((improved + 1))
        else
          rm -f "$tmp"
        fi
      fi
    fi
  done

  # 2. 清理超过30天的任务交接归档
  if [ -d "$CLAUDE_DIR/handoff-archive" ]; then
    local deleted
    deleted=$(find "$CLAUDE_DIR/handoff-archive" -name "*.md" -mtime +30 -delete -print 2>/dev/null | wc -l)
    [ "$deleted" -gt 0 ] && log "清理了 $deleted 条过期交接归档"
  fi

  # 3. 清理超过30天的复盘报告
  find "$REVIEW_DIR" -name "review-*.md" -mtime +30 -delete 2>/dev/null

  [ "$improved" -gt 0 ] && log "自动改进完成，清理了 $improved 个日志文件"
}

# ── 显示今日报告 ─────────────────────────────────────────────
show_today() {
  local review_file="$REVIEW_DIR/review-$(today).md"
  if [ -f "$review_file" ]; then
    cat "$review_file"
  else
    echo "ℹ️  今日复盘报告尚未生成"
    echo "   运行: daily-review.sh generate"
  fi
}

# ── 提交需授权的改进建议 ─────────────────────────────────────
propose_improvement() {
  local title="$1"
  local description="${2:-（无详细描述）}"
  local impact="${3:-低}"

  local entry_num
  entry_num=$(grep -c "^#### " "$PENDING_FILE" 2>/dev/null || echo 0)
  entry_num=$((entry_num + 1))

  {
    echo "#### #${entry_num} $title"
    echo "- **影响级别**: $impact"
    echo "- **描述**: $description"
    echo "- **提交时间**: $(timestamp)"
    echo "- **状态**: 🟡 待授权"
    echo ""
  } >> "$PENDING_FILE"

  log "新改进建议 #${entry_num}: $title"
  echo "✅ 改进建议 #${entry_num} 已记录"
  echo "   将在下次复盘报告中展示"
  echo "   用户批准后运行: daily-review.sh approve $entry_num"
}

# ── 批准并标记改进项 ─────────────────────────────────────────
approve_improvement() {
  local num="$1"
  if [ ! -f "$PENDING_FILE" ]; then
    echo "❌ 没有待授权的改进项"
    return 1
  fi
  # 用 sed 更新对应条目的状态
  local tmp
  tmp=$(mktemp)
  # 找到第 $num 个条目并更新其状态行
  awk -v num="#${num} " '
    /^#### / { in_entry = ($0 ~ num) }
    in_entry && /^- \*\*状态\*\*:/ { sub(/🟡 待授权/, "✅ 已授权 ('"$(today)"')") }
    { print }
  ' "$PENDING_FILE" > "$tmp" && mv "$tmp" "$PENDING_FILE"

  log "改进建议 #${num} 已获用户授权"
  echo "✅ 改进建议 #${num} 已批准"
  echo "   请查看 $PENDING_FILE 中的执行说明并手动实施"
}

# ── 主入口 ──────────────────────────────────────────────────
usage() {
  cat << 'EOF'
龙虾每日复盘分析器 — 用法：

  daily-review.sh generate               生成今日复盘报告（含自动改进）
  daily-review.sh show                   显示今日复盘报告
  daily-review.sh propose "标题" "描述" [影响]  提交改进建议（需授权）
  daily-review.sh approve <序号>         批准指定的改进建议

功能说明：
  - 自动分析过去24小时的运行日志
  - 识别高错误率、频繁降级、未完成任务等问题
  - 自动执行安全改进（日志清理、缓存重置）
  - 需要授权的改进记录在 ~/.claude/pending-improvements.md
  - 报告保存在 ~/.claude/reviews/ 目录

示例：
  daily-review.sh generate
  daily-review.sh propose "减少仓库学习频率" "改为每3天而不是每天" "低"
  daily-review.sh approve 1
EOF
}

case "${1:-help}" in
  generate)
    generate_review
    ;;
  show)
    show_today
    ;;
  propose)
    [ -z "${2:-}" ] && { echo "用法: $0 propose \"标题\" \"描述\" [影响级别]"; exit 1; }
    propose_improvement "$2" "${3:-}" "${4:-低}"
    ;;
  approve)
    [ -z "${2:-}" ] && { echo "用法: $0 approve <序号>"; exit 1; }
    approve_improvement "$2"
    ;;
  help|*)
    usage
    ;;
esac
