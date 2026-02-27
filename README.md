# 龙虾自主学习系统

让 Claude Code（龙虾）能自己找仓库、读代码、把知识永久记住。

## 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    每次会话启动                          │
│                         │                               │
│                  SessionStart Hook                       │
│              (session-start-hook.sh)                     │
│                         │                               │
│              每24小时触发一次后台任务                     │
│                         │                               │
│                  repo-learner.sh                         │
│                  （知识提取器）                           │
│          ┌──────────────┼──────────────┐               │
│     读观察列表      GitHub API      写入 CLAUDE.md       │
│  (repo-watchlist)   (MCP 服务)     (永久知识库)          │
│                                         │               │
│                              龙虾每次启动自动读取          │
└─────────────────────────────────────────────────────────┘
```

## 三种学习方式

| 方式 | 触发时机 | 说明 |
|------|---------|------|
| **自动** | 每次启动 | 后台学习 `repo-watchlist.txt` 里的仓库 |
| **指令** | 用户说"去学xxx" | 龙虾执行 `repo-learner.sh learn <repo>` |
| **搜索** | 用户说"搜索xxx" | 龙虾执行 `repo-learner.sh search <query>` |

## 快速安装（VPS 上执行）

```bash
git clone https://github.com/xinfuhd/Darwin-claude-code.git
cd Darwin-claude-code
chmod +x scripts/setup.sh
./scripts/setup.sh
```

安装完成后，编辑你的仓库观察列表：
```bash
nano ~/.claude/repo-watchlist.txt
```

## 手动使用

```bash
# 学习指定仓库
~/.claude/scripts/repo-learner.sh learn anthropics/claude-code

# 搜索并学习 Top 3
~/.claude/scripts/repo-learner.sh search "python async framework"

# 学习观察列表所有仓库
~/.claude/scripts/repo-learner.sh watchlist

# 查看知识库摘要
~/.claude/scripts/repo-learner.sh summary
```

## 对龙虾说的话

安装后，直接在 claude 里说：

> "去学习 anthropics/claude-code 这个仓库"

> "搜索 VPS 自动化部署相关的仓库，找几个好的"

> "你已经学了哪些仓库？"

## 文件结构

```
~/.claude/
├── CLAUDE.md              ← 永久知识库（龙虾每次启动都读）
├── settings.json          ← Claude 配置（含 MCP + Hooks）
├── repo-watchlist.txt     ← 自动学习列表
├── repo-cache/            ← 已学仓库记录
├── learner.log            ← 学习日志
└── scripts/
    ├── repo-learner.sh        ← 知识提取器
    └── session-start-hook.sh  ← 会话启动钩子
```

## 工作原理

1. **MCP GitHub 服务**：让龙虾能直接调用 GitHub API 读任意仓库，无需克隆
2. **repo-learner.sh**：从仓库提取 README、目录结构、核心代码，写入 CLAUDE.md
3. **CLAUDE.md**：龙虾每次启动都会读这个文件，相当于"长期记忆"
4. **SessionStart Hook**：每次会话启动时检查是否需要更新知识库

## 关键配置

### MCP GitHub（settings.json）
```json
{
  "mcpServers": {
    "github": {
      "command": "mcp-server-github",
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### 获取 GitHub Token
访问 https://github.com/settings/tokens/new
- 勾选 `repo` (只读) 和 `read:user`
- 复制 token，设置环境变量：`export GITHUB_TOKEN=ghp_xxx...`
