#!/bin/bash
# =============================================================
# obsidian-bridge.sh — 龙虾 Obsidian 双向桥接器
# 功能：在 Obsidian 笔记库与龙虾知识库（CLAUDE.md）之间同步
#
# 用法：
#   obsidian-bridge.sh import [笔记路径或标签]   # 从 Obsidian 导入到 CLAUDE.md
#   obsidian-bridge.sh export                     # 把 CLAUDE.md 知识库导出到 Obsidian
#   obsidian-bridge.sh status                     # 显示当前配置与同步状态
#   obsidian-bridge.sh setup                      # 交互式配置 Obsidian 库路径
#
# 配置文件：~/.claude/obsidian-config.sh
#   OBSIDIAN_VAULT="/path/to/your/vault"
#   OBSIDIAN_IMPORT_TAG="claude"          # 打了这个标签的笔记会被导入
#   OBSIDIAN_EXPORT_DIR="龙虾知识库"      # 导出到 Vault 内的哪个子目录
# =============================================================

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
KNOWLEDGE_FILE="$CLAUDE_DIR/CLAUDE.md"
CONFIG_FILE="$CLAUDE_DIR/obsidian-config.sh"
LOG="$CLAUDE_DIR/obsidian-bridge.log"

# ── 加载配置 ─────────────────────────────────────────────────
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
  OBSIDIAN_VAULT="${OBSIDIAN_VAULT:-}"
  OBSIDIAN_IMPORT_TAG="${OBSIDIAN_IMPORT_TAG:-claude}"
  OBSIDIAN_EXPORT_DIR="${OBSIDIAN_EXPORT_DIR:-龙虾知识库}"
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# ── 检查配置是否有效 ─────────────────────────────────────────
check_vault() {
  if [ -z "$OBSIDIAN_VAULT" ]; then
    echo "❌ 未配置 Obsidian 库路径"
    echo "   请运行：$(basename "$0") setup"
    exit 1
  fi
  if [ ! -d "$OBSIDIAN_VAULT" ]; then
    echo "❌ Obsidian 库目录不存在：$OBSIDIAN_VAULT"
    echo "   请检查路径是否正确，或重新运行：$(basename "$0") setup"
    exit 1
  fi
}

# ── 交互式配置 ───────────────────────────────────────────────
cmd_setup() {
  echo "=== 龙虾 × Obsidian 配置向导 ==="
  echo ""

  # 自动检测常见 Obsidian 库位置
  local detected=()
  for candidate in \
    "$HOME/Documents/Obsidian" \
    "$HOME/Obsidian" \
    "$HOME/obsidian" \
    "$HOME/obsidian-vault" \
    "$HOME/Desktop/Obsidian" \
    "$HOME/OneDrive/Obsidian" \
    "$HOME/iCloud Drive/Obsidian"
  do
    [ -d "$candidate" ] && detected+=("$candidate")
  done

  if [ ${#detected[@]} -gt 0 ]; then
    echo "检测到可能的 Obsidian 库："
    for i in "${!detected[@]}"; do
      echo "  [$((i+1))] ${detected[$i]}"
    done
    echo "  [0] 手动输入路径"
    echo ""
    read -rp "请选择（直接回车选1）: " choice
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#detected[@]}" ]; then
      OBSIDIAN_VAULT="${detected[$((choice-1))]}"
    else
      read -rp "请输入 Obsidian 库的完整路径: " OBSIDIAN_VAULT
    fi
  else
    read -rp "请输入 Obsidian 库的完整路径: " OBSIDIAN_VAULT
  fi

  # 展开 ~
  OBSIDIAN_VAULT="${OBSIDIAN_VAULT/#\~/$HOME}"

  if [ ! -d "$OBSIDIAN_VAULT" ]; then
    echo "⚠ 目录不存在：$OBSIDIAN_VAULT"
    read -rp "仍然保存此路径？(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "已取消"; exit 1; }
  fi

  read -rp "导入标签（含此标签的笔记会被导入）[默认: claude]: " tag
  OBSIDIAN_IMPORT_TAG="${tag:-claude}"

  read -rp "导出目录名（在 Vault 内创建）[默认: 龙虾知识库]: " export_dir
  OBSIDIAN_EXPORT_DIR="${export_dir:-龙虾知识库}"

  # 写入配置
  cat > "$CONFIG_FILE" << EOF
# 龙虾 × Obsidian 桥接配置
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')

OBSIDIAN_VAULT="$OBSIDIAN_VAULT"
OBSIDIAN_IMPORT_TAG="$OBSIDIAN_IMPORT_TAG"
OBSIDIAN_EXPORT_DIR="$OBSIDIAN_EXPORT_DIR"
EOF

  echo ""
  echo "✅ 配置已保存到：$CONFIG_FILE"
  echo ""
  echo "Obsidian 库：$OBSIDIAN_VAULT"
  echo "导入标签：   #$OBSIDIAN_IMPORT_TAG"
  echo "导出目录：   $OBSIDIAN_VAULT/$OBSIDIAN_EXPORT_DIR/"
  echo ""
  echo "下一步："
  echo "  - 在 Obsidian 笔记中添加标签 #$OBSIDIAN_IMPORT_TAG，然后运行 import"
  echo "  - 运行：$(basename "$0") import   （把 Obsidian 笔记导入到龙虾知识库）"
  echo "  - 运行：$(basename "$0") export   （把龙虾知识库导出到 Obsidian）"
}

# ── 从 Obsidian 导入到 CLAUDE.md ─────────────────────────────
cmd_import() {
  check_vault
  local filter="${1:-}"
  local imported=0

  log "开始从 Obsidian 导入（库：$OBSIDIAN_VAULT）"

  # 找到所有包含导入标签的 .md 文件
  local search_tag="#${OBSIDIAN_IMPORT_TAG}"
  local notes=()

  if [ -n "$filter" ]; then
    mapfile -t notes < <(find "$OBSIDIAN_VAULT" -name "*.md" -path "*${filter}*" 2>/dev/null | sort)
  else
    mapfile -t notes < <(grep -rl "$search_tag" "$OBSIDIAN_VAULT" --include="*.md" 2>/dev/null | sort)
  fi

  if [ ${#notes[@]} -eq 0 ]; then
    echo "未找到包含标签 $search_tag 的笔记"
    if [ -z "$filter" ]; then
      echo "提示：在 Obsidian 笔记中添加标签 $search_tag 后重试"
    fi
    return 0
  fi

  echo "找到 ${#notes[@]} 个笔记，准备导入..."
  echo ""

  [ ! -f "$KNOWLEDGE_FILE" ] && {
    mkdir -p "$(dirname "$KNOWLEDGE_FILE")"
    echo "# 龙虾知识库" > "$KNOWLEDGE_FILE"
  }

  local import_marker="## 来自 Obsidian 的笔记"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M')

  for note_path in "${notes[@]}"; do
    local note_name
    note_name=$(basename "$note_path" .md)
    local content
    content=$(cat "$note_path")
    local word_count
    word_count=$(wc -w < "$note_path")

    if [ "$word_count" -lt 20 ]; then
      log "  跳过（内容太短）：$note_name"
      continue
    fi

    echo "  导入：$note_name （$word_count 词）"

    {
      echo ""
      echo "### 📝 Obsidian: $note_name"
      echo "> 导入时间: $timestamp | 来源: ${note_path#$OBSIDIAN_VAULT/}"
      echo ""
      echo "$content" | head -c 3000
      if [ "${#content}" -gt 3000 ]; then
        echo ""
        echo "...(内容已截断，完整笔记见 Obsidian)"
      fi
      echo ""
      echo "---"
    } >> "$KNOWLEDGE_FILE"

    log "  ✅ 已导入：$note_name"
    imported=$((imported + 1))
  done

  echo ""
  echo "✅ 导入完成，共导入 $imported 篇笔记到龙虾知识库"
  log "导入完成：$imported 篇笔记"
}

# ── 把 CLAUDE.md 导出到 Obsidian ────────────────────────────
cmd_export() {
  check_vault

  local export_dir="$OBSIDIAN_VAULT/$OBSIDIAN_EXPORT_DIR"
  mkdir -p "$export_dir"

  log "开始导出到 Obsidian（目录：$export_dir）"

  local export_file="$export_dir/龙虾知识库总览.md"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  {
    echo "---"
    echo "tags: [claude, 龙虾, 知识库]"
    echo "updated: $timestamp"
    echo "---"
    echo ""
    echo "> 此文件由龙虾（Claude Code）自动生成，请勿手动编辑"
    echo "> 最后更新：$timestamp"
    echo ""
    cat "$KNOWLEDGE_FILE"
  } > "$export_file"

  echo "✅ 已导出到：$export_file"

  local repo_dir="$export_dir/仓库笔记"
  mkdir -p "$repo_dir"

  local repo_count=0
  if grep -q "^### 📦 " "$KNOWLEDGE_FILE" 2>/dev/null; then
    python3 - "$KNOWLEDGE_FILE" "$repo_dir" << 'PYEOF'
import sys, re, os

filepath = sys.argv[1]
repo_dir = sys.argv[2]

with open(filepath, 'r') as f:
    content = f.read()

sections = re.split(r'\n(?=### 📦 )', content)
count = 0
for section in sections:
    if not section.startswith('### 📦 '):
        continue
    first_line = section.split('\n')[0]
    repo_name = first_line.replace('### 📦 ', '').strip()
    safe_name = repo_name.replace('/', '_').replace(' ', '_')
    out_path = os.path.join(repo_dir, f"{safe_name}.md")
    with open(out_path, 'w') as f:
        f.write(f"---\ntags: [claude, 仓库, 龙虾]\nrepo: {repo_name}\n---\n\n")
        f.write(section)
    count += 1

print(f"导出了 {count} 个仓库笔记")
PYEOF
    repo_count=$(ls "$repo_dir"/*.md 2>/dev/null | wc -l)
    echo "✅ 已导出 $repo_count 个仓库独立笔记到：$repo_dir"
  fi

  log "导出完成：总览笔记 + $repo_count 个仓库笔记"
}

# ── 显示状态 ─────────────────────────────────────────────────
cmd_status() {
  load_config
  echo "=== 龙虾 × Obsidian 桥接状态 ==="
  echo ""

  if [ -f "$CONFIG_FILE" ]; then
    echo "配置文件：$CONFIG_FILE ✅"
    echo "  Obsidian 库：${OBSIDIAN_VAULT:-（未设置）}"
    echo "  导入标签：  #${OBSIDIAN_IMPORT_TAG}"
    echo "  导出目录：  $OBSIDIAN_VAULT/${OBSIDIAN_EXPORT_DIR}"
    if [ -n "$OBSIDIAN_VAULT" ] && [ -d "$OBSIDIAN_VAULT" ]; then
      echo "  库状态：    ✅ 目录存在"
      local note_count
      note_count=$(find "$OBSIDIAN_VAULT" -name "*.md" 2>/dev/null | wc -l)
      echo "  笔记总数：  $note_count 篇"
      local tagged_count
      tagged_count=$(grep -rl "#${OBSIDIAN_IMPORT_TAG}" "$OBSIDIAN_VAULT" --include="*.md" 2>/dev/null | wc -l)
      echo "  待导入笔记：$tagged_count 篇（含 #${OBSIDIAN_IMPORT_TAG} 标签）"
    else
      echo "  库状态：    ❌ 目录不存在"
    fi
  else
    echo "配置文件：未找到"
    echo "  请运行：$(basename "$0") setup 进行配置"
  fi

  echo ""
  if [ -f "$KNOWLEDGE_FILE" ]; then
    local kb_size
    kb_size=$(du -sh "$KNOWLEDGE_FILE" | cut -f1)
    local repo_count
    repo_count=$(grep -c "^### 📦 " "$KNOWLEDGE_FILE" 2>/dev/null || echo 0)
    local obsidian_count
    obsidian_count=$(grep -c "^### 📝 Obsidian:" "$KNOWLEDGE_FILE" 2>/dev/null || echo 0)
    echo "龙虾知识库（CLAUDE.md）："
    echo "  大小：$kb_size"
    echo "  GitHub 仓库：$repo_count 个"
    echo "  Obsidian 笔记：$obsidian_count 篇"
  else
    echo "龙虾知识库：尚未初始化"
  fi

  echo ""
  if [ -f "$LOG" ]; then
    echo "最近同步记录："
    tail -5 "$LOG" | sed 's/^/  /'
  fi
}

# ── 主入口 ───────────────────────────────────────────────────
load_config

case "${1:-help}" in
  setup)
    cmd_setup
    ;;
  import)
    check_vault
    cmd_import "${2:-}"
    ;;
  export)
    cmd_export
    ;;
  status)
    cmd_status
    ;;
  help|*)
    cat << 'EOF'
龙虾 × Obsidian 桥接器 — 用法：

  obsidian-bridge.sh setup              配置 Obsidian 库路径（首次使用）
  obsidian-bridge.sh import             导入含 #claude 标签的笔记到龙虾知识库
  obsidian-bridge.sh import <路径>      导入指定路径/名称的笔记
  obsidian-bridge.sh export             把龙虾知识库导出到 Obsidian
  obsidian-bridge.sh status             查看配置和同步状态

工作流程：
  1. 首次运行 setup，告诉龙虾你的 Obsidian 库在哪里
  2. 在 Obsidian 笔记里加标签 #claude，表示"这个给龙虾读"
  3. 运行 import，龙虾会把这些笔记加入记忆
  4. 运行 export，把龙虾学到的东西同步回 Obsidian

EOF
    ;;
esac
