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

## 七、Hermes 上 Claude OAuth 登录失败 & Provider 混乱

> 症状：想用 claude.ai 账号（OAuth）直连 Anthropic，但 `/model sonnet` 显示 `Provider: OpenRouter`，发消息报 HTTP 401

### 三种认证方式对比

| 认证方式 | 适用场景 | 需要配置 | 模型 ID 格式 |
|---------|---------|---------|------------|
| **Claude OAuth**（推荐） | 有 claude.ai Pro/Team 订阅 | 浏览器登录一次即可 | `claude-sonnet-4-6` |
| **Anthropic API Key** | 有 Anthropic API 账号 | `ANTHROPIC_API_KEY` 环境变量 | `claude-sonnet-4-6` |
| **OpenRouter API Key** | 通过 OpenRouter 路由 | `OPENROUTER_API_KEY` 环境变量 | `anthropic/claude-sonnet-4` |

**如果 `/model sonnet` 显示 `Provider: OpenRouter`，且模型 ID 是 `anthropic/claude-sonnet-4`**（带斜杠前缀）：  
说明当前环境路由到了 OpenRouter，而不是直连 Anthropic。

---

### 方向 A：使用 Claude OAuth 直连 Anthropic（无 API Key，用 claude.ai 账号）

在 Hermes 服务器上初次运行时完成 OAuth 授权：

```bash
# 1. 退出旧的认证（如有）
claude logout 2>/dev/null || true

# 2. 重新登录，Claude Code 会输出一个 URL
claude
# 复制终端里输出的 URL，在浏览器打开，用 claude.ai 账号授权

# 3. 授权成功后，再次运行并验证 Provider
claude
# 然后执行 /model 确认显示 Provider: Anthropic（而不是 OpenRouter）
```

授权完成后，OAuth token 存储在 `~/.claude/`，之后每次启动自动使用，无需重复登录。

**⚠ 注意：** 如果 Hermes 本身是 OpenRouter 架构（即它强制走 OpenRouter），则 Claude OAuth 在该 Hermes 实例中不可用，需联系 Hermes 服务管理员，或改用方向 B。

---

### 方向 B：使用 Anthropic API Key 直连（无需浏览器 OAuth）

适合无法在服务器做 OAuth 流程的场景（纯命令行 VPS）：

```bash
# 1. 在 console.anthropic.com 生成 API Key
# 2. 写入环境
echo "export ANTHROPIC_API_KEY='sk-ant-api03-xxx'" >> ~/.bashrc
source ~/.bashrc

# 3. 验证 Provider
claude
# /model 应显示 Provider: Anthropic
```

---

### 为什么 `/model sonnet` 默认显示 OpenRouter？

可能原因：

1. **之前执行了全局 provider 切换**：`/model sonnet --provider openrouter --global`  
   修复：`/model sonnet --provider anthropic --global`（设置全局默认回 Anthropic）

2. **OPENROUTER_API_KEY 已写入 shell 配置**，Claude Code 自动检测后使用  
   修复：从 `~/.bashrc` / `~/.zshrc` 删除该行，然后 `source ~/.bashrc`

3. **Hermes 服务本身是 OpenRouter 架构**  
   修复：需要直接使用 OpenRouter Key，或换一个支持 OAuth 的 Claude 访问方式

---

### 快速诊断脚本

```bash
echo "=== Provider 认证状态检查 ==="
if [ -n "$CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST" ]; then
  echo "✓ 平台托管认证（claude.ai/code 云端），无需配置"
elif [ -n "$ANTHROPIC_API_KEY" ]; then
  echo "✓ Anthropic API Key：$(echo $ANTHROPIC_API_KEY | cut -c1-20)..."
elif [ -n "$OPENROUTER_API_KEY" ]; then
  echo "⚠ OpenRouter Key：$(echo $OPENROUTER_API_KEY | cut -c1-20)... (非直连 Anthropic)"
else
  # 检查是否有 OAuth token
  if ls ~/.claude/auth* 2>/dev/null || ls ~/.claude/.credentials* 2>/dev/null; then
    echo "✓ 找到本地 OAuth token（Claude OAuth 登录状态）"
  else
    echo "❌ 未找到任何认证！"
    echo "   → 直连 Anthropic（OAuth）：运行 'claude' 完成浏览器登录"
    echo "   → 直连 Anthropic（API Key）：export ANTHROPIC_API_KEY='sk-ant-...'"
    echo "   → 使用 OpenRouter：export OPENROUTER_API_KEY='sk-or-...'"
  fi
fi

echo ""
echo "=== 全局 Provider 设置 ==="
grep -E '"provider"|"model"' ~/.claude/settings.json 2>/dev/null || echo "(未设置全局 provider)"
```

---

## 八、联系支持 & 反馈

- Claude Code 官方 Issues：https://github.com/anthropics/claude-code/issues
- 运行 `/doctor` 命令做自动诊断（如果版本支持）
- 提供 `claude --version` 和 `cat ~/.claude/settings.json` 信息

---

*本指南创建于 2026-02-27，更新于 2026-04-12，针对 VPS 部署和 Hermes 云端 Claude Code 性能、认证与记忆问题*
