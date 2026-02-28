#!/bin/bash
# =============================================================
# model-router.sh — 龙虾智能模型路由器
# 根据任务复杂度和API可用性推荐最合适的大模型
#
# 用法：
#   model-router.sh analyze "<任务描述>"       分析并推荐模型
#   model-router.sh recommend <复杂度>         按复杂度推荐
#   model-router.sh mark <模型名> <状态>       标记模型可用性
#   model-router.sh status                    显示所有模型状态
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CONFIG_FILE="$CLAUDE_DIR/model-config.json"
STATUS_FILE="$CLAUDE_DIR/model-status.json"
LOG="$CLAUDE_DIR/model-router.log"

# 默认模型层级（按复杂度）
DEFAULT_SIMPLE="claude-haiku-4-5-20251001"
DEFAULT_MEDIUM="claude-sonnet-4-6"
DEFAULT_COMPLEX="claude-opus-4-6"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>&1; }

# 加载自定义模型配置
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    local cfg_simple cfg_medium cfg_complex
    cfg_simple=$(jq -r '.simple // empty' "$CONFIG_FILE" 2>/dev/null)
    cfg_medium=$(jq -r '.medium // empty' "$CONFIG_FILE" 2>/dev/null)
    cfg_complex=$(jq -r '.complex // empty' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$cfg_simple" ] && DEFAULT_SIMPLE="$cfg_simple"
    [ -n "$cfg_medium" ] && DEFAULT_MEDIUM="$cfg_medium"
    [ -n "$cfg_complex" ] && DEFAULT_COMPLEX="$cfg_complex"
  fi
}

# ── 复杂度分析 ───────────────────────────────────────────────
# 返回: simple / medium / complex
analyze_complexity() {
  local task="$1"
  local task_lower
  task_lower=$(echo "$task" | tr '[:upper:]' '[:lower:]')

  local simple_score=0
  local complex_score=0

  # 简单任务特征词（查询、展示、小修改）
  local simple_kws=(
    "查" "看" "显示" "列出" "什么是" "解释" "翻译" "格式化"
    "查一下" "找一下" "小改" "改个" "简单" "quick" "find"
    "show" "list" "what" "how" "help" "简介" "介绍"
  )
  # 复杂任务特征词（架构、设计、大型实现）
  local complex_kws=(
    "架构" "设计" "重构" "从零开始" "完整实现" "深入研究"
    "优化整个" "全面分析" "系统设计" "architecture" "design"
    "comprehensive" "refactor" "rewrite" "从头" "完整的"
  )

  for kw in "${simple_kws[@]}"; do
    echo "$task_lower" | grep -qF "$kw" && simple_score=$((simple_score + 1))
  done

  for kw in "${complex_kws[@]}"; do
    echo "$task_lower" | grep -qF "$kw" && complex_score=$((complex_score + 1))
  done

  # 字符长度作为复杂度参考
  local char_count=${#task}
  if [ "$char_count" -gt 500 ]; then
    complex_score=$((complex_score + 2))
  elif [ "$char_count" -gt 200 ]; then
    complex_score=$((complex_score + 1))
  elif [ "$char_count" -lt 50 ]; then
    simple_score=$((simple_score + 1))
  fi

  # 代码行数/文件数作为参考（任务中提到多个文件）
  local file_mentions
  file_mentions=$(echo "$task" | grep -oE '\b\w+\.(py|js|ts|go|sh|rs|java|cpp)\b' | wc -l)
  [ "$file_mentions" -ge 3 ] && complex_score=$((complex_score + 1))

  # 最终判断
  if [ "$complex_score" -ge 2 ]; then
    echo "complex"
  elif [ "$simple_score" -ge 2 ] && [ "$complex_score" -eq 0 ]; then
    echo "simple"
  else
    echo "medium"
  fi
}

# ── 可用性检查 ───────────────────────────────────────────────
# 通过状态文件判断模型是否可用（用户或系统手动标记）
check_model_available() {
  local model="$1"
  [ ! -f "$STATUS_FILE" ] && return 0   # 无状态文件 = 默认全部可用

  local status last_check now
  status=$(jq -r --arg m "$model" '.[$m].available // "unknown"' "$STATUS_FILE" 2>/dev/null)
  last_check=$(jq -r --arg m "$model" '.[$m].last_check // 0' "$STATUS_FILE" 2>/dev/null)
  now=$(date +%s)

  # 不可用标记超过1小时自动恢复（防止永久锁定）
  if [ "$status" = "unavailable" ]; then
    if [ $((now - last_check)) -gt 3600 ]; then
      log "模型 $model 不可用标记已超时，自动恢复"
      return 0
    fi
    return 1
  fi
  return 0
}

# 标记模型可用性（供用户在 API 受限时手动调用）
mark_model_status() {
  local model="$1"
  local status="$2"   # available / unavailable
  local now
  now=$(date +%s)

  [ ! -f "$STATUS_FILE" ] && echo "{}" > "$STATUS_FILE"

  local tmp
  tmp=$(mktemp)
  jq --arg m "$model" --arg s "$status" --argjson t "$now" \
    '.[$m] = {"available": $s, "last_check": $t}' \
    "$STATUS_FILE" > "$tmp" && mv "$tmp" "$STATUS_FILE"

  log "模型状态更新: $model → $status"
  echo "✅ 已标记 $model 状态: $status"
  echo "   (不可用标记1小时后自动恢复)"
}

# ── 推荐逻辑 ────────────────────────────────────────────────
recommend_model() {
  local complexity="$1"
  local preferred

  case "$complexity" in
    simple)  preferred="$DEFAULT_SIMPLE" ;;
    complex) preferred="$DEFAULT_COMPLEX" ;;
    *)       preferred="$DEFAULT_MEDIUM" ;;
  esac

  # 首选可用则直接返回
  if check_model_available "$preferred"; then
    echo "$preferred"
    return 0
  fi

  log "首选模型 $preferred 不可用，尝试降级..."

  # 降级链：尽量用够用的，不要浪费最强资源
  local fallbacks
  case "$complexity" in
    complex) fallbacks=("$DEFAULT_MEDIUM" "$DEFAULT_SIMPLE") ;;
    medium)  fallbacks=("$DEFAULT_SIMPLE" "$DEFAULT_COMPLEX") ;;
    simple)  fallbacks=("$DEFAULT_MEDIUM") ;;
  esac

  for fb in "${fallbacks[@]}"; do
    if check_model_available "$fb"; then
      log "降级使用: $fb (原为 $preferred)"
      echo "$fb"
      return 0
    fi
  done

  # 兜底：最轻的模型
  log "所有首选模型不可用，兜底使用: $DEFAULT_SIMPLE"
  echo "$DEFAULT_SIMPLE"
}

# ── 显示当前状态 ─────────────────────────────────────────────
show_status() {
  load_config
  echo "=== 龙虾模型路由状态 ==="
  echo ""
  echo "模型层级配置："
  printf "  简单任务 → %s\n" "$DEFAULT_SIMPLE"
  printf "  中等任务 → %s\n" "$DEFAULT_MEDIUM"
  printf "  复杂任务 → %s\n" "$DEFAULT_COMPLEX"
  echo ""
  echo "当前可用性："
  for model in "$DEFAULT_SIMPLE" "$DEFAULT_MEDIUM" "$DEFAULT_COMPLEX"; do
    if check_model_available "$model"; then
      printf "  ✅ %s\n" "$model"
    else
      printf "  ❌ %s (受限，1小时后自动恢复)\n" "$model"
    fi
  done
  echo ""
  if [ -f "$STATUS_FILE" ]; then
    echo "状态文件: $STATUS_FILE"
  else
    echo "（无限制记录，所有模型默认可用）"
  fi
}

# ── 主入口 ──────────────────────────────────────────────────
usage() {
  cat << 'EOF'
龙虾智能模型路由器 — 用法：

  model-router.sh analyze "<任务描述>"          分析任务并推荐最合适的模型
  model-router.sh recommend <simple|medium|complex>  按复杂度直接推荐
  model-router.sh mark <模型名> <available|unavailable>  手动标记模型状态
  model-router.sh status                         显示所有模型当前状态

示例：
  # 分析任务并推荐
  model-router.sh analyze "帮我查一下这个函数的用法"
  model-router.sh analyze "重构整个认证系统，设计新架构"

  # 手动标记 Gemini API 受限
  model-router.sh mark gemini/gemini-pro unavailable

  # 查看状态
  model-router.sh status

模型层级（可通过 ~/.claude/model-config.json 自定义）：
  simple  → claude-haiku（快速轻量，适合查询/小改）
  medium  → claude-sonnet（均衡，适合大多数任务）
  complex → claude-opus（最强，适合架构/研究）

降级策略：
  当复杂模型不可用时，自动降级到中等模型
  当中等模型不可用时，降级到轻量模型
  不可用标记1小时后自动恢复（防止永久锁定）
EOF
}

case "${1:-help}" in
  analyze)
    [ -z "${2:-}" ] && { echo "用法: $0 analyze \"<任务描述>\""; exit 1; }
    load_config
    complexity=$(analyze_complexity "$2")
    model=$(recommend_model "$complexity")
    echo "任务复杂度: $complexity"
    echo "推荐模型:   $model"
    log "分析: 复杂度=$complexity 推荐=$model 片段=\"${2:0:60}\""
    ;;
  recommend)
    load_config
    model=$(recommend_model "${2:-medium}")
    echo "$model"
    ;;
  mark)
    [ -z "${2:-}" ] || [ -z "${3:-}" ] && {
      echo "用法: $0 mark <模型名> <available|unavailable>"
      exit 1
    }
    mark_model_status "$2" "$3"
    ;;
  status)
    show_status
    ;;
  help|*)
    usage
    ;;
esac
