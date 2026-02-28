#!/bin/bash
# =============================================================
# daily-review.sh — 龙虾每日复盘脚本
# 分析近期日志，生成改善建议，写入 daily-review.md
# =============================================================

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
LOG="$CLAUDE_DIR/learner.log"
HOOK_LOG="$CLAUDE_DIR/session-hook.log"
TASK_FILE="$CLAUDE_DIR/current-task.md"
TODAY=$(date '+%Y-%m-%d')

echo "# 每日复盘 — $TODAY"
echo ""

# ── 1. 知识库学习统计 ────────────────────────────────────────
echo "## 知识库状态"
if [ -f "$LOG" ]; then
  learned=$(grep -c "学习完成" "$LOG" 2>/dev/null || echo 0)
  failed=$(grep -c "❌" "$LOG" 2>/dev/null || echo 0); failed=${failed:-0}
  echo "- 累计已学仓库：$learned 个"
  if [ "${failed}" -gt 0 ] 2>/dev/null; then
    echo "- ⚠️ 失败次数：$failed（建议检查 GitHub Token 或网络）"
  fi
  # 最近24小时活动
  recent=$(grep "$(date '+%Y-%m-%d')" "$LOG" 2>/dev/null | tail -5)
  if [ -n "$recent" ]; then
    echo "- 今日活动："
    echo "$recent" | sed 's/^/  /'
  fi
else
  echo "- 暂无学习记录"
fi
echo ""

# ── 2. 会话启动统计 ──────────────────────────────────────────
echo "## 会话统计（近7天）"
if [ -f "$HOOK_LOG" ]; then
  session_count=$(grep -c "会话启动" "$HOOK_LOG" 2>/dev/null || echo 0)
  echo "- 累计会话次数：$session_count"
  hook_errors=$(grep -c "ERROR\|error\|失败" "$HOOK_LOG" 2>/dev/null || echo 0)
  if [ "$hook_errors" -gt 0 ]; then
    echo "- ⚠️ 钩子异常：$hook_errors 次，最近错误："
    grep -i "error\|失败" "$HOOK_LOG" 2>/dev/null | tail -3 | sed 's/^/  /'
  fi
else
  echo "- 暂无会话记录"
fi
echo ""

# ── 3. 当前任务检查 ──────────────────────────────────────────
echo "## 当前任务"
if [ -f "$TASK_FILE" ] && [ -s "$TASK_FILE" ]; then
  cat "$TASK_FILE"
else
  echo "- 无进行中任务"
fi
echo ""

# ── 4. 自动改善建议 ──────────────────────────────────────────
echo "## 改善建议"

# 检查 GitHub Token
if [ -z "${GITHUB_TOKEN:-}" ]; then
  # 尝试从 shell 配置读取
  token_in_rc=$(grep -h "GITHUB_TOKEN" ~/.bashrc ~/.zshrc 2>/dev/null | grep -v "^#" | head -1)
  if [ -z "$token_in_rc" ]; then
    echo "- ⚠️ 未检测到 GITHUB_TOKEN，GitHub API 处于匿名限速模式（60次/小时）"
    echo "  → 建议：export GITHUB_TOKEN='ghp_...' 写入 ~/.bashrc"
  fi
fi

# 检查 watchlist 是否有内容（非注释行）
if [ -f "$CLAUDE_DIR/repo-watchlist.txt" ]; then
  active_repos=$(grep -v "^#" "$CLAUDE_DIR/repo-watchlist.txt" | grep -v "^$" | wc -l)
  if [ "$active_repos" -eq 0 ]; then
    echo "- ⚠️ repo-watchlist.txt 没有启用的仓库（全是注释），知识库无法自动更新"
    echo "  → 建议：取消注释你感兴趣的仓库行"
  fi
fi

# 检查 CLAUDE.md 大小
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  claude_size=$(wc -c < "$CLAUDE_DIR/CLAUDE.md")
  if [ "$claude_size" -gt 100000 ]; then
    echo "- ⚠️ CLAUDE.md 已超过 100KB（当前 ${claude_size} 字节），可能影响读取速度"
    echo "  → 建议：运行 ~/.claude/scripts/repo-learner.sh summary 并精简旧内容"
  fi
fi

echo ""
echo "---"
echo "> 复盘由 daily-review.sh 自动生成 | $(date '+%Y-%m-%d %H:%M')"
