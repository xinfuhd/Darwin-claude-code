# VPS Claude Code（龙虾）性能迟钝 & 记忆丢失 — 诊断指南

> 症状：反应迟钝、回答质量下降、要求永久记忆的内容不执行

---

## 一、快速自检清单

在 VPS 上依次执行以下命令，判断问题根源：

```bash
# 1. 查看当前使用的模型
claude --version
cat ~/.claude/settings.json 2>/dev/null || cat ~/.config/claude/settings.json

# 2. 查看全局 CLAUDE.md（永久记忆文件）
cat ~/.claude/CLAUDE.md 2>/dev/null
ls -la ~/.claude/

# 3. 查看项目级 CLAUDE.md
ls -la ~/your-project/CLAUDE.md 2>/dev/null

# 4. 检查 API 密钥及配额
echo $ANTHROPIC_API_KEY | cut -c1-10   # 只显示前10位验证存在
```

---

## 二、问题一：反应迟钝（延迟高）

### 可能原因 & 解决方案

| 原因 | 诊断 | 解决方案 |
|------|------|----------|
| VPS 地区到 Anthropic API 延迟高 | `curl -w "%{time_total}" -o /dev/null https://api.anthropic.com` | 使用代理或换 VPS 地区 |
| 被限速（Rate Limit） | 检查 API 响应头 `x-ratelimit-*` | 升级 Anthropic 套餐 |
| 使用了慢速模型 | 查看 settings.json 中 model 字段 | 改用 claude-sonnet-4-6 |
| 上下文窗口爆满 | 对话轮次过多，token 积累 | 开新会话 `/clear` 或重启 |
| 网络带宽不足 | `iperf3` 测速 | 升级 VPS 带宽 |

### 测试 API 延迟
```bash
# 测试到 Anthropic API 的原始延迟
ping api.anthropic.com -c 5

# 测试完整 API 响应时间
time curl -s -o /dev/null \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' \
  https://api.anthropic.com/v1/messages
```

### 强制使用最快模型（临时测试）
```bash
# ~/.claude/settings.json
{
  "model": "claude-haiku-4-5-20251001"   # 速度最快，适合测延迟
}
# 确认质量后换回：
{
  "model": "claude-sonnet-4-6"           # 质量与速度平衡（推荐日常）
}
```

---

## 三、问题二：回答变"弱智"（质量下降）

### 最常见原因

#### 1. 模型被自动降级
```bash
# 检查当前实际使用的模型
cat ~/.claude/settings.json
# 如果 model 字段是 haiku 或为空（默认可能不是最强的），改为：
# "model": "claude-sonnet-4-6"
# 或
# "model": "claude-opus-4-6"  （最强但较慢）
```

#### 2. 上下文过长导致"遗忘"
- Claude 有上下文窗口限制，长对话后期回答质量会下降
- **解决**：`/clear` 清除上下文，或开新终端重新启动 `claude`

#### 3. CLAUDE.md 指令冲突
```bash
# 查看所有层级的 CLAUDE.md
cat ~/.claude/CLAUDE.md          # 全局
cat ~/项目路径/CLAUDE.md          # 项目级
cat ~/项目路径/.claude/CLAUDE.md  # 项目级备选
```

---

## 四、问题三：永久记忆不执行（最关键）

### 永久记忆的正确写法

Claude Code 的"永久记忆"通过 **CLAUDE.md 文件** 实现，而不是通过对话告知。

#### 层级结构（优先级从低到高）
```
~/.claude/CLAUDE.md          ← 全局记忆（所有项目生效）
~/项目/CLAUDE.md              ← 项目记忆（进入该目录后生效）
~/项目/.claude/CLAUDE.md      ← 项目记忆（备选位置）
```

#### 正确操作方式

**方法 1：让 Claude 自己写入（推荐）**
```
你对 Claude 说：
"请把以下内容永久写入 CLAUDE.md：
- 回复语言：中文
- 代码风格：xxx
- 禁止操作：xxx"
```
Claude 会自动调用 Write 工具写入文件。

**方法 2：手动写入**
```bash
cat >> ~/.claude/CLAUDE.md << 'EOF'

## 永久指令（2024-02-27 设置）
- 所有回复使用中文
- 提交代码前必须运行测试
- 不要自动 push，需确认后再 push
EOF
```

#### 验证是否生效
```bash
# 查看全局记忆文件
cat ~/.claude/CLAUDE.md

# 重新启动 claude 后测试
claude
# 然后问：你有哪些永久指令？
```

### 记忆不执行的常见原因

| 原因 | 诊断 | 修复 |
|------|------|------|
| CLAUDE.md 不存在 | `ls ~/.claude/CLAUDE.md` | 创建文件 |
| CLAUDE.md 在错误目录 | Claude 只读取当前工作目录链上的文件 | 确认目录层级 |
| 指令写法不清晰 | 语义模糊的指令 | 用明确的命令式语句 |
| 新会话未加载 | 每次会话都会重新读取 | 正常，文件存在即可 |
| 文件权限问题 | `ls -la ~/.claude/CLAUDE.md` | `chmod 644 ~/.claude/CLAUDE.md` |

---

## 五、完整重置流程（当以上都不解决问题时）

```bash
# 1. 备份现有配置
cp ~/.claude/settings.json ~/.claude/settings.json.bak 2>/dev/null
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak 2>/dev/null

# 2. 重建配置
mkdir -p ~/.claude

# 3. 写入推荐的 settings.json
cat > ~/.claude/settings.json << 'EOF'
{
  "model": "claude-sonnet-4-6",
  "theme": "dark"
}
EOF

# 4. 重建永久记忆
cat > ~/.claude/CLAUDE.md << 'EOF'
# 全局永久指令

## 语言
- 所有回复使用中文（除非用户用英文提问）

## 行为规范
- 在这里写你的永久要求...
EOF

# 5. 重启 claude
claude
```

---

## 六、VPS 特有的性能优化

```bash
# 使用代理加速（如果 VPS 到 API 延迟 >500ms）
export ANTHROPIC_BASE_URL=https://你的代理地址/v1
# 或者在 settings.json 中设置

# 检查系统资源
htop                          # CPU/内存使用
df -h                         # 磁盘空间（日志文件可能撑满）
du -sh ~/.claude/             # Claude 本地文件大小
```

---

## 七、Hermes（云端容器）环境 — OAuth 登录与 Provider 切换问题

> 症状：OAuth 登录失败，或 `/model sonnet --provider anthropic` 切换后发消息报错

### 背景：Hermes 环境是什么

当 Claude Code 运行在 `claude.ai/code`（即 Hermes 云端容器）时，环境中会设置以下特殊变量：

```
CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1       ← Provider 由平台托管
CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR=4    ← OAuth token 通过 fd 传入
CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE=cloud_default
```

这意味着：**认证（OAuth token）由 Hermes 平台通过文件描述符注入，而不是通过 `ANTHROPIC_API_KEY` 环境变量。**

### 问题一：OAuth 登录失败

**诊断：**
```bash
# 检查是否处于 host-managed 环境
echo $CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST    # 应为 1
echo $CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR  # 应有值（如 4）
```

**可能原因与解决方案：**

| 原因 | 表现 | 解决方案 |
|------|------|----------|
| OAuth token 过期 | 登录后立即失效 | 关闭页面重新打开，刷新 OAuth session |
| 平台 fd 注入失败 | 环境变量缺失 | 刷新页面，等待容器重新初始化 |
| 会话过期 | 长时间不操作后失效 | 重新打开 claude.ai/code 页面 |

### 问题二：`/model sonnet --provider anthropic` 切换后无法使用

**根本原因：**

在 `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1` 环境中：

- 默认认证 = Hermes 平台注入的 OAuth token（fd 4）
- `--provider anthropic` = 尝试绕过平台，直接用 `ANTHROPIC_API_KEY`
- 但 `ANTHROPIC_API_KEY` 未设置 → 切换后发消息失败

```
Warning: Could not reach the Anthropic API to validate claude-sonnet-4-6.
# 这个警告意味着已经在尝试直接调用 API，而非通过平台认证
```

**正确做法：在 Hermes 环境中切换模型，不要加 `--provider` 参数：**

```bash
# ✅ 正确：不指定 provider，使用平台托管的认证
/model sonnet
/model opus
/model haiku

# ❌ 错误：强制切换到直接 API 模式，在 Hermes 中会失败
/model sonnet --provider anthropic
```

**若需全局固定模型，在 `settings.json` 中设置（不要设置 provider）：**

```json
{
  "model": "claude-sonnet-4-6"
}
```

### 快速诊断脚本

```bash
# 检测当前是否为 Hermes 云端环境
if [ -n "$CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST" ]; then
  echo "⚠ 检测到 Hermes 云端环境（Provider 由平台托管）"
  echo "  → 请勿使用 /model --provider anthropic"
  echo "  → OAuth token 由平台通过 fd $CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR 注入"
else
  echo "✓ 标准环境，可自由切换 Provider"
  echo "  ANTHROPIC_API_KEY: $(echo $ANTHROPIC_API_KEY | cut -c1-10)..."
fi
```

---

## 八、联系支持 & 反馈

- Claude Code 官方 Issues：https://github.com/anthropics/claude-code/issues
- 运行 `/doctor` 命令做自动诊断（如果版本支持）
- 提供 `claude --version` 和 `cat ~/.claude/settings.json` 信息

---

*本指南创建于 2026-02-27，更新于 2026-04-12，针对 VPS 部署和 Hermes 云端 Claude Code 性能、认证与记忆问题*
