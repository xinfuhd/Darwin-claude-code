#!/bin/bash
# =============================================================
# session-handoff.sh — 龙虾任务交接管理器
# 解决模型切换前后记忆/任务衔接不足的问题
#
# 用法：
#   session-handoff.sh save ["任务"] ["进度"] ["下一步"]  保存状态
#   session-handoff.sh load                              加载并显示上下文
#   session-handoff.sh clear                             清除已完成的交接
#   session-handoff.sh history                           查看历史记录
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HANDOFF_FILE="$CLAUDE_DIR/handoff.md"
ARCHIVE_DIR="$CLAUDE_DIR/handoff-archive"
LOG="$CLAUDE_DIR/handoff.log"

mkdir -p "$ARCHIVE_DIR"

log()       { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>&1; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# ── 获取当前模型 ─────────────────────────────────────────────
current_model() {
  local settings="$CLAUDE_DIR/settings.json"
  if [ -f "$settings" ]; then
    jq -r '.model // "未知"' "$settings" 2>/dev/null || echo "未知"
  else
    echo "未知"
  fi
}

# ── 保存交接文件 ─────────────────────────────────────────────
save_handoff() {
  local task="${1:-（请描述当前任务）}"
  local progress="${2:-（请描述已完成的内容）}"
  local next_steps="${3:-（请描述切换后需要继续的步骤）}"
  local model
  model=$(current_model)

  # 归档旧的交接文件
  if [ -f "$HANDOFF_FILE" ]; then
    local archive_name="handoff-$(date '+%Y%m%d-%H%M%S').md"
    cp "$HANDOFF_FILE" "$ARCHIVE_DIR/$archive_name"
    log "旧交接文件已归档: $archive_name"
  fi

  cat > "$HANDOFF_FILE" << EOF
# 🦞 龙虾任务交接文件

**创建时间**: $(timestamp)
**发起模型**: $model

---

## 📋 当前任务
$task

## ✅ 已完成进度
$progress

## ➡️ 下一步（新模型继续）
$next_steps

## 🗒️ 重要上下文
（可手动追加：关键文件路径、变量名、决策原因、注意事项等）

---
*新会话启动时会自动提示此文件，或运行 \`session-handoff.sh load\` 手动加载*
EOF

  log "交接文件已保存: $HANDOFF_FILE | 任务: ${task:0:50}"
  echo ""
  echo "✅ 任务交接文件已保存"
  echo "   文件: $HANDOFF_FILE"
  echo ""
  echo "📌 切换模型后，在新会话中运行："
  echo "   ~/.claude/scripts/session-handoff.sh load"
}

# ── 加载并展示交接上下文 ─────────────────────────────────────
load_handoff() {
  if [ ! -f "$HANDOFF_FILE" ]; then
    echo "ℹ️  没有待加载的任务交接文件"
    return 0
  fi

  local created_time
  created_time=$(grep "创建时间" "$HANDOFF_FILE" | head -1 | sed 's/.*: //')

  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║  🦞 任务交接（创建于 $created_time）  ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
  # 只显示核心内容，跳过文件头和注脚
  sed -n '/^## 📋 当前任务/,/^---$/p' "$HANDOFF_FILE" | head -50
  echo ""
  echo "💡 继续时从「下一步」部分开始执行"
  echo "   完成后运行: session-handoff.sh clear"
  echo ""

  log "交接文件已加载展示"
}

# ── 清除已完成的交接 ─────────────────────────────────────────
clear_handoff() {
  if [ ! -f "$HANDOFF_FILE" ]; then
    echo "ℹ️  没有待清除的交接文件"
    return 0
  fi

  local archive_name="handoff-done-$(date '+%Y%m%d-%H%M%S').md"
  cp "$HANDOFF_FILE" "$ARCHIVE_DIR/$archive_name"
  rm "$HANDOFF_FILE"
  log "交接文件已完成归档: $archive_name"
  echo "✅ 任务交接文件已清除（已归档至 $ARCHIVE_DIR/$archive_name）"

  # 清理超过30天的归档
  find "$ARCHIVE_DIR" -name "*.md" -mtime +30 -delete 2>/dev/null
}

# ── 查看历史记录 ─────────────────────────────────────────────
show_history() {
  echo "=== 任务交接历史 ==="
  if ls "$ARCHIVE_DIR"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
    echo ""
    ls -lt "$ARCHIVE_DIR"/*.md 2>/dev/null | head -10 | awk '{print $NF}' | while read -r f; do
      local ts task
      ts=$(grep "创建时间" "$f" 2>/dev/null | head -1 | sed 's/.*: //')
      task=$(grep -A1 "^## 📋 当前任务" "$f" 2>/dev/null | tail -1 | cut -c1-60)
      printf "  %s  %s\n" "$ts" "$task"
    done
    echo ""
    echo "共 $(ls "$ARCHIVE_DIR"/*.md 2>/dev/null | wc -l) 条历史记录"
  else
    echo "  （无历史记录）"
  fi
}

# ── 快速交接（交互式引导）────────────────────────────────────
interactive_save() {
  echo ""
  echo "🦞 龙虾任务交接向导"
  echo "（切换模型前，快速记录关键信息）"
  echo ""
  read -rp "📋 当前任务是什么？> " task
  read -rp "✅ 已完成了什么？> " progress
  read -rp "➡️  下一步需要做什么？> " next_steps
  save_handoff "$task" "$progress" "$next_steps"
}

# ── 主入口 ──────────────────────────────────────────────────
usage() {
  cat << 'EOF'
龙虾任务交接管理器 — 用法：

  session-handoff.sh save ["任务"] ["进度"] ["下一步"]  保存当前任务状态
  session-handoff.sh wizard                            交互式引导保存
  session-handoff.sh load                              加载并显示交接上下文
  session-handoff.sh clear                             清除已完成的交接文件
  session-handoff.sh history                           查看历史交接记录

切换模型的正确流程：
  1. 保存交接: session-handoff.sh save "当前任务" "已完成" "下一步"
     或使用向导: session-handoff.sh wizard
  2. 切换模型（修改 settings.json 或启动新会话）
  3. 新会话中加载: session-handoff.sh load
  4. 完成任务后清除: session-handoff.sh clear

示例：
  session-handoff.sh save "修复登录bug" "已定位到auth.py:45" "添加空值检查并测试"
  session-handoff.sh load
  session-handoff.sh clear
EOF
}

case "${1:-help}" in
  save)
    save_handoff "${2:-}" "${3:-}" "${4:-}"
    ;;
  wizard)
    interactive_save
    ;;
  load)
    load_handoff
    ;;
  clear)
    clear_handoff
    ;;
  history)
    show_history
    ;;
  help|*)
    usage
    ;;
esac
