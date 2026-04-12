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

## 七、联系支持 & 反馈

- Claude Code 官方 Issues：https://github.com/anthropics/claude-code/issues
- 运行 `/doctor` 命令做自动诊断（如果版本支持）
- 提供 `claude --version` 和 `cat ~/.claude/settings.json` 信息

---

## 八、OAuth 认证问题（Claude Pro/Max subscription）

> 症状：在 Hermes 或 Claude Code CLI 中选择 Anthropic → Claude Pro/Max subscription (OAuth login)，完成授权后仍无法正常使用。

---

### 根本原因分析

| # | 原因 | 说明 |
|---|------|------|
| 1 | **`ANTHROPIC_API_KEY` 环境变量冲突** | 若 VPS 上设置了此变量，它会**覆盖 OAuth token**，导致用 Pro/Max token 认证失败 |
| 2 | **模型不在 Pro/Max 订阅范围内** | `settings.json` 里指定的 model 可能是 API 计费模型，Pro/Max 订阅不覆盖，请求直接被拒绝 |
| 3 | **API 端点不匹配** | Pro/Max OAuth 访问的是 `api.claude.ai`，而 API Key 访问的是 `api.anthropic.com`；工具配置错端点时认证会失败 |
| 4 | **VPS 无浏览器，OAuth 回调丢失** | OAuth 需要浏览器完成重定向；VPS headless 环境下重定向 URL 可能无法被客户端捕获，token 未被正确存储 |
| 5 | **OAuth token 未持久化** | token 存储在 `~/.claude/.credentials.json`；若文件不存在或权限错误，每次重启后认证状态丢失 |

---

### 诊断步骤

```bash
# 1. 检查是否有 API Key 环境变量覆盖 OAuth token（最常见原因）
echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:0:10}..."
# 如果有值 → 这是问题所在，需要 unset

# 2. 检查 OAuth token 是否已存储
ls -la ~/.claude/.credentials.json 2>/dev/null && echo "token 已存储" || echo "token 不存在"
cat ~/.claude/.credentials.json 2>/dev/null | python3 -m json.tool | grep -E '"type"|"expires"'

# 3. 检查当前配置的端点和模型
cat ~/.claude/settings.json 2>/dev/null

# 4. 检查 claude 认证状态
claude auth status 2>/dev/null || echo "不支持此命令，请检查版本"
```

---

### 修复方案

#### 方案 A：清除冲突的 API Key（最常见修复）

```bash
# 临时 unset（当前 shell 生效）
unset ANTHROPIC_API_KEY

# 永久移除（从 ~/.bashrc 或 ~/.zshrc 中删除）
sed -i '/ANTHROPIC_API_KEY/d' ~/.bashrc ~/.zshrc 2>/dev/null

# 重新登录
claude auth login
```

#### 方案 B：VPS 无浏览器时完成 OAuth（headless 方式）

```bash
# 1. 在 VPS 上启动登录，获取授权 URL
claude auth login
# 程序会输出一个 https://claude.ai/... 的 URL

# 2. 复制该 URL，在本地浏览器中打开并完成授权

# 3. 授权完成后，浏览器会跳转到 http://localhost:... 的回调地址
#    复制完整的回调 URL，粘贴回 VPS 终端
```

#### 方案 C：Pro/Max 订阅可用的模型配置

```bash
# Pro/Max 订阅通过 OAuth 可用的模型（不需要 API 计费）
cat > ~/.claude/settings.json << 'EOF'
{
  "model": "claude-sonnet-4-6"
}
EOF
# 注意：不要在 settings.json 里设置 apiKey 字段，否则会绕过 OAuth
```

#### 方案 D：完全重置认证状态

```bash
# 清除所有认证信息，重新开始
claude auth logout 2>/dev/null
rm -f ~/.claude/.credentials.json
unset ANTHROPIC_API_KEY

# 重新通过 OAuth 登录
claude auth login
```

---

### 验证认证是否正常

```bash
# 发送一条简单消息，测试是否能通
claude -p "你好，回复'认证成功'"
```

若返回正常响应，说明 OAuth 认证已修复。

---

*本指南创建于 2026-02-27，针对 VPS 部署的 Claude Code 性能与记忆问题*
