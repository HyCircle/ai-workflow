---
name: finishing
description: 收束 CC、Codex 或 Cursor session，先给简短交棒，再用本地脚本提取 transcript，交下一轮 cleaning 压缩归档。用户 /finishing 调用。
---

# Finishing

先读 discipline 和 AGENTS，命令取自 workflow.env。全程中文，顺序为交棒 → 提取 → 核对。

## 交棒

用一段简短回复说明本轮结果、验证范围、未完成项、稳定但未冻的决定候选，以及可复制的「下 session 开场提示词」。保留关键约束与下一步所需的精确路径。决定由 bs/planner 著作；文档维护交下一轮低成本模型执行 cleaning。

## 提取

复用本 session 的 `.workflow/scratchpad/<PL|BS>-<完整UUID>/`。从宿主标识或已确认的日志取得 UUID；来源不明时列候选，核对项目和开场任务。

```bash
$WF_PY .workflow/kit/scripts/transcribe_session.py --backend <cc|codex|cursor> \
  --session <完整UUID> --out .workflow/scratchpad/<PL|BS>-<完整UUID>/transcript.md
```

脚本按完整 UUID 精确查找本机 CC projects、Codex sessions/archived_sessions、Cursor agent-transcripts 的 JSONL 日志。非默认位置或多个匹配时，以 `--input <完整日志路径>` 替代 `--session`。

默认保留用户/助手正文，省略推理、工具流水账和宿主注入，附来源标识并做常见凭证打码。工具结果与图像内容需回原始材料核实。`--tools` 可保留工具骨架供排查；坏行报错并保留已有输出。

核对文件尾部包含刚才的交棒。日志未刷盘时重新提取；无法取得完整记录则报告缺口、保留源文件。最后回报 transcript 路径，交下一轮 `/cleaning <该路径>`。
