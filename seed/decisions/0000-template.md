---
id: 0000
title: <一句话结论,陈述句非疑问句>
date: YYYY-MM-DD
status: proposed        # proposed | accepted | superseded | deprecated
supersedes: []          # 取代了哪些 ADR,如 [7, 12];无则留空
superseded_by: null     # 被哪个 ADR 取代(填 id);未被取代留 null
tags: []                # 领域标签,便于「碰这块前先读相关 ADR」,如 [auth, storage]
---

# ADR-0000: <一句话结论——与 frontmatter title 一致>

## 意图(为什么存在 —— 散文 2–3 句)
<为什么要这个决策 / 用户可见价值 / 边界。冷读者靠这段理解「为什么」,不是「怎么做」。>

## 背景与约束
<触发这个决策的现实:现状、硬约束、必须满足的条件。
**决策要有数据支撑就把数据 / 实验结论贴这**(结论进正文;原始数据 / notebook 与 ADR 主文件就近同放一个文件夹,见文末约定),别拍脑袋。>

## 决策(契约 —— 可测的 WHAT)
<拍板做什么。写成可测:数据形状 / 不变量 / 硬上限 / **明确不做** / 能证伪的判据。
file:line 不进这里(归 architecture.md 或代码,那些会漂;ADR 不可变)。>

## 备选与失效模式(被否掉的路 + 为什么)
<认真考虑过的其他方案,各自为什么没选;每个配一句「若选它会怎么错」。最值钱的一节,防后人重踩。>

## 后果
<采纳后的代价 / 收益 / 新约束 / 需连带改的东西。>

<!--
ADR 约定(新建时删掉本注释):
- 文件名 decisions/NNNN-<kebab-英文-slug>.md,NNNN 四位零填充递增。frontmatter.id 必须与文件名一致。
- 引用写 `ADR-NNNN`(断链检查认这个 token → 查 decisions/NNNN-*.md 在不在)。
- **不可变**:决策变了 → 新开 ADR,新 ADR 的 supersedes 填旧 id,旧 ADR 的 status 改 superseded、superseded_by 填新 id。**不改旧 ADR 正文**。这取代旧 PLAN 的「§X.0 修正块」——文件级 supersede,不在文件内打补丁。
- **ADR 可单文件、也可文件夹**:无附件 → 单文件 `decisions/NNNN-slug.md`;有附件(原始数据 json/csv、notebook、一次性辅助脚本)→ 文件夹 `decisions/NNNN-slug/`,**主 md 与文件夹同名** `decisions/NNNN-slug/NNNN-slug.md`(不叫 README——编辑器多标签才认得出是哪个决策),所有相关文件就近同放该文件夹。ADR 正文只留结论 + 判据,数据在旁。
- 一次性实验脚本随数据留在 ADR 文件夹;某脚本若成了长期复用工具,再毕业到 `scripts/`。
- **谁起草 / 纯设计 vs 代码实据(判据要锐,别靠直觉)**:一条子契约**现在**能写成会红的测试、且依赖的类型/消费者/数据**此刻已存在** → 纯设计,bs 连契约一起冻;要靠**尚不存在的**代码/消费者/数据才能证伪 → **代码实据型**,bs 只写意图冻 `proposed`,契约留 planner 先建骨架、读码后回填。**同一 ADR 两类子契约可并存**(能证伪的先冻,其余标「待回填」)。
- **何时写**:决策稳定到**粘性**(不可逆 / 反复被引用)才建 ADR;早期高频探索留 scratchpad,别每个念头都冻(免 supersede 链爆炸)。
-->
