#!/bin/bash
# =============================================================
# sync.sh — 从 GitHub 拉取最新配置并应用到龙虾
# 在 VPS 上运行：bash ~/.claude/Darwin-claude-code/scripts/sync.sh
# =============================================================
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

echo "============================================"
echo "  龙虾同步 — 从 GitHub 拉取最新配置"
echo "============================================"

# ── 1. 拉取最新代码 ──────────────────────────────────────────
echo ""
echo "▶ [1/4] git pull..."
cd "$REPO_DIR"
git pull --ff-only
echo "   ✓ 代码已更新"

# ── 2. 同步脚本 ──────────────────────────────────────────────
echo ""
echo "▶ [2/4] 同步脚本到 ~/.claude/scripts/..."
mkdir -p "$CLAUDE_DIR/scripts"
cp "$REPO_DIR/scripts/repo-learner.sh"       "$CLAUDE_DIR/scripts/"
cp "$REPO_DIR/scripts/session-start-hook.sh" "$CLAUDE_DIR/scripts/"
cp "$REPO_DIR/scripts/sync.sh"               "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*.sh
echo "   ✓ 脚本已同步"

# ── 3. 同步 CLAUDE.md（知识库模板）─────────────────────────
echo ""
echo "▶ [3/4] 检查 CLAUDE.md..."
TEMPLATE="$REPO_DIR/config/CLAUDE.md.template"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
  cp "$TEMPLATE" "$CLAUDE_MD"
  echo "   ✓ CLAUDE.md 已从模板初始化"
else
  # 只更新模板中的"永久指令"区块，保留龙虾已学到的知识记录
  # 提取模板中 "## 仓库知识库" 之前的内容作为新的 header
  HEADER_END=$(grep -n "^## 仓库知识库" "$CLAUDE_MD" | head -1 | cut -d: -f1)
  if [ -n "$HEADER_END" ]; then
    # 保留现有知识库部分，只替换 header（永久指令区块）
    TEMPLATE_HEADER_END=$(grep -n "^## 仓库知识库" "$TEMPLATE" | head -1 | cut -d: -f1)
    if [ -n "$TEMPLATE_HEADER_END" ]; then
      # 拼接：新模板的 header + 现有知识库内容
      head -n $((TEMPLATE_HEADER_END - 1)) "$TEMPLATE" > "${CLAUDE_MD}.new"
      tail -n +$HEADER_END "$CLAUDE_MD" >> "${CLAUDE_MD}.new"
      mv "${CLAUDE_MD}.new" "$CLAUDE_MD"
      echo "   ✓ CLAUDE.md 永久指令区块已更新（知识记录已保留）"
    fi
  else
    echo "   - CLAUDE.md 结构已自定义，跳过自动合并（手动比较：$TEMPLATE）"
  fi
fi

# ── 4. 同步 repo-watchlist（如仓库版本更新）────────────────
echo ""
echo "▶ [4/4] 检查 repo-watchlist.txt..."
WATCHLIST_SRC="$REPO_DIR/config/repo-watchlist.txt"
WATCHLIST_DST="$CLAUDE_DIR/repo-watchlist.txt"

if [ ! -f "$WATCHLIST_DST" ]; then
  cp "$WATCHLIST_SRC" "$WATCHLIST_DST"
  echo "   ✓ repo-watchlist.txt 已初始化"
else
  echo "   - repo-watchlist.txt 已存在，跳过（手动编辑：$WATCHLIST_DST）"
fi

# ── 完成 ─────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ 同步完成！"
echo "============================================"
echo ""
echo "重启 claude 会话即可加载新配置。"
echo "或对龙虾说：'重新读取 CLAUDE.md'"
echo ""
