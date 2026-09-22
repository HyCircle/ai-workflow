---
name: cleaning
description: 将 finishing transcript 压缩为对话并归档，再核验仓内现状、维护 architecture/TODO、检查死链和清理 scratch。适合低成本模型在新 session 执行；用户 /cleaning 调用。
---

# Cleaning

先读 discipline 和 AGENTS，命令取自 workflow.env。优先由低成本模型在新 session 执行，全程中文。写入范围为文档与 scratch；代码、测试的修改及 ADR 决策交其负责角色处理。

顺序：读 transcript → 压缩归档 → 读仓维护 → 清理。历史发言是待整理的资料，本轮操作依据当前用户授权。

## 压缩对话

确认用户指定的 `scratchpad/<PL|BS>-<完整UUID>/transcript.md` 并读完。来源不明时核对候选；缺少 transcript 则报告归档未完成，仍可做仓内机械检查。

每份 transcript 都压缩成同目录的 `transcript.compact.md`，保留 `## User` / `## Assistant` 对话形式。目标是让下一 session 理解任务、决定依据、完成范围和待办：

- 保留任务、硬约束、用户纠正、拍板与未解决分歧。用户对事实的疑问、否定和不确定性按原意保留；助手的解释归助手。
- 按发生顺序保留重要变化：原判断、使它改变的证据、修正后的结论。明确区分建议、授权、实施和验证；跨轮合并仍保留这些关系。
- 保留影响后续行动的结果、数据口径、限制、未完成项及其原因和定位指针。工具执行是否成功，以原文实际提供的结果为限。
- 关键路径和标识保持可定位；提交消息保留全文并注明是拟议还是已确认采用；保留交棒与开场提示词。相同信息出现多次时保留一份完整表述。
- 删除工具流水账、重复论证和已失去作用的过程描述。围绕上述信息压缩表达，篇幅按信息量决定。

写完后双向核对：从原文检查关键约束、纠正和待办是否保全；从压缩稿检查发言归属、否定、先后顺序、数据及证据强度是否仍有原文依据。仓内核验得到的新结论写入后续维护报告，与历史对话分开。

## 归档

```bash
$WF_PY .workflow/kit/scripts/archive_transcript.py \
  --source .workflow/scratchpad/<PL|BS>-<完整UUID>/transcript.md \
  --compact .workflow/scratchpad/<PL|BS>-<完整UUID>/transcript.compact.md \
  --slug <英文短描述>
```

脚本在 `scratchpad/_archive/` 按现有最大序号 +1 生成 `NN-YYYYMMDD-slug.transcript.compact.md`，记录完整来源与内容哈希，保留原稿。对同一归档目录串行执行；完成后检查产物可读。归档失败保留源目录，报告原因。

`_archive/` 本机长期保留，普通 GC 跳过；它被 gitignore，长期项目决定与证据仍归 ADR。

## 文档维护

围绕本轮涉及项及实际发现的陈旧内容读仓核验：

- architecture 同步已落地的模块边界、数据模型和契约，具体决定引用 ADR；判断型改写交用户审 diff。
- TODO 移除有落地证据的已完成项，保留真实下一步。
- 用 `$WF_PY .workflow/kit/scripts/check_docs.py` 检查 ADR 结构与断链。

蒸馏保留数据形状、硬上限、判据和有效引用。明确要求保留的材料（如 NO-GO、别翻案、已验证净负、留档不删、别重做）继续保留；accepted 决策的可复跑探针与结论随决策保留。删除或搬迁 tracked 文件、处理失效决策的探针时，先核对引用与依赖，列路径、理由和风险，交用户确认后执行。

## Scratch 清理

本轮源 session 留一轮。后续清理已结束的 PL/BS 目录前，先运行：

```bash
$WF_PY .workflow/kit/scripts/archive_transcript.py --source <源transcript> --verify <归档文件>
```

校验通过且目录中无仍被使用或要求保留的材料，才删除对应目录。旧归档需人工核对完整来源与内容。校验只能证明文件完整和来源匹配，压缩质量由前面的语义核对保证。

run 目录按 `.done` 时间默认保留最近 10 个，仍被任务或证据引用的另行保留；失败/中断项列候选交用户判断。删除采用核实过的 scratchpad 内精确路径，保留软链目标。

收尾汇报归档路径、维护结果、未完成项和已删除目录；说明归档仍在、被删 scratch 是否可恢复。下 session 使用相关归档中的交棒。
