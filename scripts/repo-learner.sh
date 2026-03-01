#!/bin/bash
# =============================================================
# repo-learner.sh — 龙虾知识提取器
# 功能：从 GitHub 仓库提取精华内容，写入 CLAUDE.md 知识库
#
# 用法：
#   repo-learner.sh learn <owner/repo 或完整URL>
#   repo-learner.sh learn --force <owner/repo>   # 强制重新学习
#   repo-learner.sh search <关键词>
#   repo-learner.sh watchlist          # 学习观察列表里所有仓库
#   repo-learner.sh summary            # 显示当前知识库摘要
# =============================================================

set -euo pipefail

# 是否强制重新学习（跳过缓存）
FORCE_LEARN=0

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
KNOWLEDGE_FILE="$CLAUDE_DIR/CLAUDE.md"
WATCHLIST="$CLAUDE_DIR/repo-watchlist.txt"
CACHE_DIR="$CLAUDE_DIR/repo-cache"
LOG="$CLAUDE_DIR/learner.log"
MAX_FILE_SIZE=50000   # 单文件最大读取字节数
MAX_KNOWLEDGE_SIZE=80000  # CLAUDE.md 最大字节数（超出则自动裁剪旧内容）

mkdir -p "$CACHE_DIR"

# ── 工具函数 ─────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

# 解析仓库标识 → owner/repo 格式
parse_repo() {
  local input="$1"
  # https://github.com/owner/repo  →  owner/repo
  input="${input#https://github.com/}"
  input="${input%.git}"
  input="${input%/}"
  echo "$input"
}

# GitHub API 请求（不使用 eval，避免命令注入）
gh_api() {
  local path="$1"
  local args=(
    curl -s -L
    -H "Accept: application/vnd.github.v3+json"
    -H "User-Agent: darwin-claude-learner/1.0"
  )
  # Token 作为独立参数传递，避免 shell 注入
  [ -n "${GITHUB_TOKEN:-}" ] && args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

  "${args[@]}" "https://api.github.com/$path"
}

# 检查 GitHub API 速率限制，剩余次数不足时暂停
check_rate_limit() {
  local remaining
  remaining=$(gh_api "rate_limit" 2>/dev/null | jq -r '.rate.remaining // 60' 2>/dev/null || echo 60)
  if [ "$remaining" -lt 5 ]; then
    local reset_ts
    reset_ts=$(gh_api "rate_limit" 2>/dev/null | jq -r '.rate.reset // 0' 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    local wait_secs=$(( reset_ts - now + 5 ))
    if [ "$wait_secs" -gt 0 ] && [ "$wait_secs" -lt 3660 ]; then
      log "⚠ GitHub API 剩余次数不足（$remaining），等待 ${wait_secs}s 后恢复..."
      sleep "$wait_secs"
    fi
  fi
}

# 获取文件内容（base64解码）
gh_file() {
  local repo="$1" path="$2"
  local result
  result=$(gh_api "repos/$repo/contents/$path" 2>/dev/null) || return 1
  local encoding
  encoding=$(echo "$result" | jq -r '.encoding // "none"' 2>/dev/null) || return 1
  if [ "$encoding" = "base64" ]; then
    echo "$result" | jq -r '.content' | base64 -d 2>/dev/null | head -c "$MAX_FILE_SIZE"
  else
    echo "$result" | jq -r '.content // ""' 2>/dev/null
  fi
}

# 裁剪 CLAUDE.md，保留最新内容
trim_knowledge() {
  local size
  size=$(wc -c < "$KNOWLEDGE_FILE" 2>/dev/null || echo 0)
  if [ "$size" -gt "$MAX_KNOWLEDGE_SIZE" ]; then
    log "知识库超过 ${MAX_KNOWLEDGE_SIZE} 字节，自动裁剪旧条目..."
    # 保留文件头（固定指令区）和最新的若干条目
    python3 - "$KNOWLEDGE_FILE" "$MAX_KNOWLEDGE_SIZE" <<'PYEOF'
import sys, re
filepath, max_size = sys.argv[1], int(sys.argv[2])
with open(filepath, 'r') as f:
    content = f.read()
# 找到第一个 "## 学习记录" 或 "## Learned:" 之前的内容作为头部
split_markers = ['## 学习记录', '## Learned:', '## 仓库知识库']
header_end = len(content)
for marker in split_markers:
    idx = content.find(marker)
    if idx != -1:
        header_end = min(header_end, idx)
        break
header = content[:header_end]
body = content[header_end:]
# 按仓库条目分割，保留最新的
entries = re.split(r'\n(?=### )', body)
# 从最新往旧删，直到大小合适
while len(header.encode()) + sum(len(e.encode()) for e in entries) > max_size and len(entries) > 1:
    entries.pop(0)
new_content = header + '\n'.join(entries)
with open(filepath, 'w') as f:
    f.write(new_content)
print(f"裁剪完成：保留 {len(entries)} 个条目")
PYEOF
  fi
}

# ── 核心功能：学习单个仓库 ──────────────────────────────────

learn_repo() {
  local input="$1"
  local repo
  repo=$(parse_repo "$input")
  local cache_flag="$CACHE_DIR/${repo//\//_}.learned"

  # 已学习过则跳过，--force 模式除外
  if [ -f "$cache_flag" ] && [ "$FORCE_LEARN" -eq 0 ]; then
    log "⏭  $repo 已在缓存中，跳过（使用 --force 可强制重新学习）"
    return 0
  fi

  log "开始学习仓库：$repo"

  # 检查 API 剩余次数，避免触发限流
  check_rate_limit

  # ── 获取仓库基本信息 ──
  local meta
  meta=$(gh_api "repos/$repo") || { log "❌ 无法访问仓库 $repo"; return 1; }

  # 检测 API 错误（如 404、403）
  local api_msg
  api_msg=$(echo "$meta" | jq -r '.message // ""' 2>/dev/null)
  if [ -n "$api_msg" ]; then
    log "❌ GitHub API 错误：$api_msg（仓库：$repo）"
    return 1
  fi

  local description stars lang updated
  description=$(echo "$meta" | jq -r '.description // "无描述"')
  stars=$(echo "$meta" | jq -r '.stargazers_count // 0')
  lang=$(echo "$meta" | jq -r '.language // "未知"')
  updated=$(echo "$meta" | jq -r '.updated_at // ""' | cut -c1-10)

  log "  仓库：$repo | ⭐$stars | 语言：$lang | 更新：$updated"

  # ── 提取关键文件 ──
  local content_parts=()

  # README
  local readme
  for readme_name in README.md readme.md README.rst README; do
    if readme=$(gh_file "$repo" "$readme_name" 2>/dev/null); then
      content_parts+=("**README:**\n\`\`\`\n$(echo "$readme" | head -c 3000)\n\`\`\`")
      break
    fi
  done

  # 顶层目录结构
  local tree
  if tree=$(gh_api "repos/$repo/git/trees/HEAD?recursive=0" 2>/dev/null); then
    local dirs
    dirs=$(echo "$tree" | jq -r '.tree[]? | select(.type=="tree") | .path' 2>/dev/null | head -20 | tr '\n' ' ')
    local key_files
    key_files=$(echo "$tree" | jq -r '.tree[]? | select(.type=="blob") | .path' 2>/dev/null | \
      grep -E '\.(py|js|ts|go|rs|sh|yaml|yml|json|toml|md)$' | head -20 | tr '\n' ' ')
    content_parts+=("**目录结构：** $dirs\n**关键文件：** $key_files")
  fi

  # 智能选择核心代码文件（按扩展名和路径判断重要性）
  local important_files=()
  local file_list
  if file_list=$(gh_api "repos/$repo/git/trees/HEAD?recursive=1" 2>/dev/null); then
    mapfile -t important_files < <(echo "$file_list" | jq -r '.tree[]? | select(.type=="blob") | .path' 2>/dev/null | \
      grep -E '(main|index|app|core|cli|server|config)\.(py|js|ts|go|rs|sh)$' | head -5)
  fi

  for fpath in "${important_files[@]}"; do
    local fcontent
    if fcontent=$(gh_file "$repo" "$fpath" 2>/dev/null); then
      content_parts+=("**$fpath:**\n\`\`\`\n$(echo "$fcontent" | head -c 2000)\n\`\`\`")
      log "    读取：$fpath"
    fi
  done

  # CHANGELOG / RELEASES（了解版本演进）
  for changelog_name in CHANGELOG.md CHANGES.md; do
    local cl
    if cl=$(gh_file "$repo" "$changelog_name" 2>/dev/null); then
      content_parts+=("**CHANGELOG（最新）：**\n$(echo "$cl" | head -c 1500)")
      break
    fi
  done

  # ── 写入知识库 ──
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M')

  {
    echo ""
    echo "### 📦 $repo"
    echo "> ⭐$stars | 语言: $lang | 描述: $description | 学习时间: $timestamp"
    echo ""
    for part in "${content_parts[@]}"; do
      printf '%b\n\n' "$part"
    done
    echo "---"
  } >> "$KNOWLEDGE_FILE"

  trim_knowledge
  touch "$cache_flag"
  log "  ✅ $repo 学习完成，已写入知识库"
}

# ── 搜索 GitHub 并选择仓库学习 ─────────────────────────────

search_and_learn() {
  local query="$1"
  log "搜索 GitHub：$query"

  local results
  results=$(gh_api "search/repositories?q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")&sort=stars&per_page=5") || {
    log "❌ 搜索失败"; return 1
  }

  local count
  count=$(echo "$results" | jq '.items | length' 2>/dev/null || echo 0)

  if [ "$count" -eq 0 ]; then
    log "未找到相关仓库"
    return 0
  fi

  echo ""
  echo "找到以下仓库（按 Stars 排序）："
  echo "$results" | jq -r '.items[] | "  \(.stargazers_count)⭐ \(.full_name) — \(.description // "无描述")"'
  echo ""

  # 自动学习 Top 3
  local top_repos
  mapfile -t top_repos < <(echo "$results" | jq -r '.items[].full_name' | head -3)

  for repo in "${top_repos[@]}"; do
    learn_repo "$repo"
  done
}

# ── 学习观察列表 ────────────────────────────────────────────

learn_watchlist() {
  if [ ! -f "$WATCHLIST" ]; then
    log "观察列表不存在：$WATCHLIST"
    log "请创建文件并添加仓库（每行一个，支持 owner/repo 或完整URL）"
    return 1
  fi

  log "开始学习观察列表：$WATCHLIST"
  local count=0
  while IFS= read -r line; do
    # 跳过注释和空行
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    # 检查是否是搜索查询（以 search: 开头）
    if [[ "$line" =~ ^search:(.+)$ ]]; then
      (search_and_learn "${BASH_REMATCH[1]}") || log "⚠ 搜索 '${BASH_REMATCH[1]}' 失败，跳过"
    else
      (learn_repo "$line") || log "⚠ 学习 $line 失败，跳过"
    fi
    count=$((count + 1))
    sleep 1  # 避免触发 API 限速
  done < "$WATCHLIST"

  log "观察列表学习完成，共处理 $count 个条目"
}

# ── 显示知识库摘要 ──────────────────────────────────────────

show_summary() {
  if [ ! -f "$KNOWLEDGE_FILE" ]; then
    echo "知识库为空"
    return
  fi
  echo "=== 龙虾知识库摘要 ==="
  echo "文件大小：$(du -sh "$KNOWLEDGE_FILE" | cut -f1)"
  echo ""
  echo "已学习仓库："
  grep -E '^### 📦 ' "$KNOWLEDGE_FILE" | sed 's/### 📦 /  /' || echo "  （无）"
  echo ""
  echo "缓存记录："
  ls "$CACHE_DIR"/*.learned 2>/dev/null | wc -l | xargs echo "  已完成："
}

# ── 初始化 CLAUDE.md（如不存在）────────────────────────────

init_knowledge_file() {
  if [ ! -f "$KNOWLEDGE_FILE" ]; then
    cat > "$KNOWLEDGE_FILE" << 'EOF'
# 龙虾知识库 — 永久指令 & 从仓库学到的知识

## 永久指令

- 所有回复使用中文（除非用户用英文提问）
- 重要决策或危险操作前必须确认
- 学到的代码模式优先用于当前任务

## 如何主动学习仓库

当用户要求学习某个仓库时，执行以下流程：
1. 用 `~/.claude/scripts/repo-learner.sh learn <repo>` 提取知识
2. 读取提取的内容，理解核心架构和模式
3. 把关键洞察总结追加到本文件的 "## 学习记录" 区域
4. 在后续任务中主动应用这些模式

## 仓库知识库

<!-- 以下内容由 repo-learner.sh 自动维护 -->

EOF
    echo "  ✓ 知识库已初始化"
  fi
}

# ── 主入口 ──────────────────────────────────────────────────

case "${1:-help}" in
  learn)
    # 支持 --force 标志：learn --force <repo> 或 learn <repo>
    if [ "${2:-}" = "--force" ]; then
      FORCE_LEARN=1
      [ -z "${3:-}" ] && { echo "用法：$0 learn --force <owner/repo 或 URL>"; exit 1; }
      init_knowledge_file
      learn_repo "$3"
    else
      [ -z "${2:-}" ] && { echo "用法：$0 learn [--force] <owner/repo 或 URL>"; exit 1; }
      init_knowledge_file
      learn_repo "$2"
    fi
    ;;
  search)
    [ -z "${2:-}" ] && { echo "用法：$0 search <关键词>"; exit 1; }
    init_knowledge_file
    search_and_learn "$2"
    ;;
  watchlist)
    init_knowledge_file
    learn_watchlist
    ;;
  summary)
    show_summary
    ;;
  init)
    init_knowledge_file
    ;;
  help|*)
    cat << 'EOF'
龙虾知识提取器 — 用法：

  repo-learner.sh learn <owner/repo>           学习指定仓库
  repo-learner.sh learn --force <owner/repo>   强制重新学习（忽略缓存）
  repo-learner.sh search <关键词>              搜索并学习 Top 3 仓库
  repo-learner.sh watchlist                    学习观察列表里所有仓库
  repo-learner.sh summary                      显示知识库摘要
  repo-learner.sh init                         初始化知识库文件

示例：
  repo-learner.sh learn anthropics/claude-code
  repo-learner.sh learn --force anthropics/claude-code
  repo-learner.sh search "python async web framework"
  repo-learner.sh watchlist
EOF
    ;;
esac
