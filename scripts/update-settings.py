#!/usr/bin/env python3
"""
update-settings.py — 合并更新 Claude Code settings.json
安全地添加 MCP 服务和 SessionStart hook，不覆盖现有配置
"""
import json, sys, os, shutil
from datetime import datetime

def find_mcp_server_github():
    """查找 mcp-server-github 可执行文件路径"""
    # 常见安装位置
    candidates = [
        shutil.which("mcp-server-github"),
        shutil.which("@modelcontextprotocol/server-github"),
    ]
    # npm global bin 目录
    npm_prefix = os.popen("npm prefix -g 2>/dev/null").read().strip()
    if npm_prefix:
        candidates.append(os.path.join(npm_prefix, "bin", "mcp-server-github"))

    for path in candidates:
        if path and os.path.isfile(path):
            return path
    return "mcp-server-github"  # 假设已在 PATH 中

def main():
    settings_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude/settings.json")
    hook_script   = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.claude/scripts/session-start-hook.sh")
    provider      = sys.argv[3] if len(sys.argv) > 3 else ""   # "anthropic" | "openrouter" | ""

    # 读取现有配置
    settings = {}
    if os.path.isfile(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)

    # 备份原文件
    if os.path.isfile(settings_path):
        backup = f"{settings_path}.bak.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        shutil.copy(settings_path, backup)
        print(f"  备份原配置：{backup}")

    # ── 添加 MCP GitHub 服务 ──────────────────────────────────
    mcp_path = find_mcp_server_github()
    settings.setdefault("mcpServers", {})
    if "github" not in settings["mcpServers"]:
        settings["mcpServers"]["github"] = {
            "command": mcp_path,
            "env": {
                "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
            }
        }
        print(f"  ✓ 已添加 MCP GitHub 服务（路径：{mcp_path}）")
    else:
        print("  - MCP GitHub 服务已存在，跳过")

    # ── 添加 SessionStart Hook ─────────────────────────────────
    settings.setdefault("hooks", {})
    settings["hooks"].setdefault("SessionStart", [])

    hook_cmd = hook_script
    # 检查是否已存在
    existing = settings["hooks"]["SessionStart"]
    already_exists = any(
        hook_script in str(entry)
        for entry in existing
    )

    if not already_exists:
        settings["hooks"]["SessionStart"].append({
            "hooks": [
                {
                    "type": "command",
                    "command": hook_cmd
                }
            ]
        })
        print(f"  ✓ 已添加 SessionStart hook")
    else:
        print("  - SessionStart hook 已存在，跳过")

    # ── 设置默认 provider（避免 OpenRouter 意外成为默认）─────────
    if provider == "anthropic":
        # OAuth 或 Anthropic API Key：清除 OpenRouter 配置，确保走 Anthropic
        settings.pop("provider", None)          # 移除显式 provider（OAuth 不需要指定）
        settings["model"] = "claude-sonnet-4-6"
        print("  ✓ 已设置默认模型 claude-sonnet-4-6（Provider: Anthropic）")
    elif provider == "openrouter":
        settings["provider"] = "openrouter"
        settings["model"] = "anthropic/claude-sonnet-4-5"
        print("  ✓ 已设置默认模型 anthropic/claude-sonnet-4-5（Provider: OpenRouter）")
    # provider 为空时不修改 model/provider，保留现有配置

    # ── 保留 $schema ───────────────────────────────────────────
    if "$schema" not in settings:
        settings["$schema"] = "https://json.schemastore.org/claude-code-settings.json"

    # 写入
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=4, ensure_ascii=False)
    print(f"  ✓ 已写入：{settings_path}")

if __name__ == "__main__":
    main()
