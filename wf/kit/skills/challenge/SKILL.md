---
name: challenge
description: 结论质疑：把实验、基准比较、性能或数值结论，以及「X 比 Y 好」「问题不存在」「已验证完成」这类结论列成清单，交强模型专门找反证，最多两轮，再逐条结算。普通编码任务不需要。用户 /challenge 调用，或 planner 裁决实验与研究类结论前使用。
---

# Challenge(结论质疑)

先读 discipline，全程中文。施工审看的是改动；本技能检查的是「这句结论成立吗」。质疑者只找能推翻或削弱结论的证据，你负责结算。

本 session 的产物放 `.workflow/scratchpad/CH-<完整 session UUID>/`（planner 内使用时放 `PL-<id>/`）。

## 1. 写结论清单 `claims.md`

开头一行写结果对应的提交号与工作区是否有未提交改动（`git rev-parse --short HEAD`、`git status --short`）。每条结论：

```
### C1 <结论原文>
- 性质：有利 | 无效 | 不利 | 无定论 | 仅证明可行
- 证据：文件、命令、数据位置
- 已知局限：<没有写无>
```

一句话里混着几个结论时拆开写，各自标性质。

## 2. 外呼质疑者(第一轮)

默认用 `strong` 档，可换任意「后端/模型」。质疑者需要亲自运行核查，故用 `--write`，写入范围由开场白限制在 scratchpad。走后台执行，完成通知到了再读：

```bash
wf ask strong .workflow/kit/skills/challenge/challenger-preamble.md \
  .workflow/scratchpad/CH-<id>/claims.md \
  --write --timeout 2400 --out .workflow/scratchpad/CH-<id>/round1.md
```

## 3. 结算

对每条异议给出一种处理，写在 `claims.md` 对应结论下：

- **已解决**：附新证据（命令、数据位置、结果）；
- **接受为局限**：结论相应收窄或改写性质；
- **不采纳**：写理由。

需要时跑第二轮：把结算后的 `claims.md` 和 `round1.md` 一起交给质疑者，它只判断第一轮异议是否解决，不提新异议。

```bash
wf ask strong .workflow/kit/skills/challenge/challenger-preamble.md \
  .workflow/scratchpad/CH-<id>/claims.md .workflow/scratchpad/CH-<id>/round1.md \
  --write --timeout 2400 --out .workflow/scratchpad/CH-<id>/round2.md
```

两轮用完，质疑者的阻断作用结束；这不等于结论已被证明。

## 4. 汇报与入档

最终汇报和写入文档的结论分两列：**已支持的结论**（附证据）与**不被支持或未验证的结论**。写进 ADR、architecture 或手册时，未经结算的实验结论标「待验证」。被采纳的异议若对同类任务通用，作为手册候选交 finishing。

## 动手前(可选)：比较口径

跨多个候选做比较、或结论会影响默认实现时，先在 `contract.md` 写清：问题；假设；要测的量；候选与比较口径（起点、停止条件、预算、计时范围、reference 的数量与来源）；替代解释；什么结果会推翻假设；据结果怎么决定。用第 2 节的命令把 `contract.md` 交给质疑者先审口径与决策规则，再动手。
