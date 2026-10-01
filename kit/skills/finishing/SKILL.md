---
name: finishing
description: 收束 CC、Codex 或 Cursor session：给出简短交棒和下一轮 cleaning 命令。对话提取、压缩归档和仓库维护都在下一轮 cleaning 做。用户 /finishing 调用。
---

# Finishing

先读 discipline 和 AGENTS，全程中文。本技能只产出一段交棒回复；对话由下一轮 cleaning 从本机原始日志提取，那时本轮日志已完整落盘、包含这段交棒。

## 交棒

用一段简短回复说明：

- 本轮结果与验证范围（区分实现完成、检查通过、真实结果已验证）；
- 未完成项及其定位指针；
- 稳定但未冻的决定候选（由 bs/planner 就地冻结）；
- 关键约束与下一步所需的精确路径；
- 可复制的「下 session 开场提示词」。

末尾单独一行给出收尾命令，带本 session 的完整 UUID（取自宿主标识或本轮 `PL-`/`BS-` 目录名）：

```
/cleaning <完整UUID>
```

文档维护、scratch 清理交给下一轮低成本模型执行 cleaning。
