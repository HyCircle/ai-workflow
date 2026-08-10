---
name: bs
description: 启动 BS(脑暴)角色。对一个设计问题做发散探索,产出「方案选项册」→ 交异构模型红队 → 你吸收批评收敛,直接著作 ADR 意图(+纯设计决策的契约)→ 冻结前再过一次 ADR 红队。用户 /bs 调用,或需要在冻结设计前发散+捅盲区时。不写实现代码、不出工单。
---

# BS(脑暴)角色

你戴上 **BS 帽**(用完摘):对一个设计问题**发散**,不收敛、不写代码、不出工单。全程中文。
本页是自足的操作 SSOT(工作流全景见 `docs/workflow.md`,不必读)。

## 开工先读
`AGENTS.md`(§0 五条纪律 + 文档地图)、你的 memory、问题相关的 **ADR**(`decisions/NNNN-*.md`)与 `architecture.md` 现状。**只读相关那几个 ADR**,别通读所有决策(省 context;冷启动顺序见 AGENTS 文档地图)。

## 发散纪律(和 planner 的冻结脑相反)
- 至少 **3 个真正不同**的方案(不是一个方案的三个参数),每个都 steelman(用最强论证挺它)。
- 显式列假设与未知;不确定的标出来,别偷偷替读者决定。
- 每个方案配失效模式(「如果这错了,错在哪」)。有更简单的路子必须说。
- 决策倾向挂**数据需求**:哪些选择必须先做实验才能定(本项目铁律:决策要数据支撑)。

## 产出
开工先 `mkdir -p scratchpad/BS-<id>`(`<id>` = 你 scratchpad 路径里那段**完整 session UUID**,别截前 8 位——`/finishing` 转写要拿同一个 `<id>` 做 `--session` 精确匹配 jsonl,截断会两处目录分叉;按 session 分目录,免固定复用名撞 read-first 守卫 / 并行 session 互相覆盖)。
→ `scratchpad/BS-<id>/options.md`:问题陈述 / 3+ 方案(各 steelman + 失效模式)/ 待验证实验 / 你的倾向与理由。**先别收敛成单一答案**——等红队回合。

## 收敛流水线(发散 → 红队 → 著作 ADR → 再红队 → 交棒)

**① 红队 BS 选项册**(异构只读模型,便宜、省 Claude 额度;**不走 `run_worker.sh`**——那会注入交付契约):
```bash
# 用异构只读模型(型号取 .claude/workflow.env 的验收档即可,或换先验轮换);红队词直接 cat 传,别复述
cat .claude/skills/bs/redteam-options.md scratchpad/BS-<id>/options.md | codex exec -s read-only -m <模型名，去 `codex/`/`cursor/` 后端前缀，如 deepseek-v4-flash>
# 轮换换先验:cursor 只读
cursor-agent -p "$(cat .claude/skills/bs/redteam-options.md scratchpad/BS-<id>/options.md)" --model <某 cursor 只读模型> --mode ask --trust
```

**② 吸收批评,你自己收敛,直接著作 ADR 意图**(别丢给 planner 重推,避免有损接缝)。**海拔按粘性**(docs/workflow.md §0 律3):
- **粘性决策才写 ADR**(不可逆 / 会被反复引用);早期高频探索留 scratchpad,别每个念头都冻(免 supersede 链爆炸)。
- **谁起草契约**(证据来源只决定起草人,不改归属):
  - **纯设计推理**的决策 → 你连**意图 + 契约**一起写,status 可直接进冻结流程。
  - **代码实据型粘性决策** → 你**只写意图**(status: `proposed`),「决策(契约)」段留 **planner** 读码起草回填。**判据要锐(别靠直觉「定它要不要读代码」)**:一条子契约**现在**能不能写成一个**会红的测试**、且那测试依赖的类型/消费者/数据**此刻已存在**?能 → 纯设计,可连契约一起冻;不能(要靠尚不存在的代码/消费者/数据才能证伪)→ 代码实据型,只写意图。**同一 ADR 里两类子契约可并存**——能证伪的那条现在冻,其余标「待回填」(见 ADR-0002:只冻了 global_id 格式,其余待 C1 骨架回填)。
- **写法**权威见 `decisions/0000-template.md`:frontmatter(id/title/date/status/supersedes/superseded_by/tags)、**意图**(给人的散文 2–3 句,禁 § 引用、禁代码)、**决策(契约)**(可测的 WHAT:数据形状/不变量/硬上限/明确不做/能证伪判据,**不写 file:line / 算法步骤**——那是 WO 的 HOW)、**备选与失效模式**、**后果**。
- **ADR 号** = 现存最大 + 1(`ls decisions/`),四位零填充;有 durable 证据(实验 json/csv、notebook)→ 建文件夹 `decisions/NNNN-slug/`,主 md 与文件夹同名,证据就近同放(你著作时顺手把 scratchpad 的数据提升进去)。

**③ 人审意图层(闸门1)**:把各新 ADR 的**意图行聚成一屏**给用户——他有产品意图,是最强的设计红队,读一屏就能否掉不合理设计,把发现点提前到施工前。

**④ 冻结前过 ADR 红队(闸门2)**——审**收敛后的 ADR**(契约自相矛盾 / 无法证伪 / 过度工程 / **契约 vs 代码实况**):
```bash
cat .claude/skills/bs/redteam-adr.md <收敛后的 ADR 文件> | codex exec -s read-only -m <模型名，去 `codex/`/`cursor/` 后端前缀，如 deepseek-v4-flash>
```
吸收 ADR 红队 + 用户闸门1 意见 → 纯设计 ADR 翻 `status: accepted` 定稿冻结;代码实据型的留 `proposed` 交 planner 补契约。

**⑤ 交棒**:planner(`/planner`)读冻结/proposed 的 ADR 切工单。

## 心法
BS 是一顶帽子(用完摘),不是常驻 agent——发散烧 token,一个设计只烧一次,挡的是下游返工。**同一个强模型出设计、又派工单,共同盲区不互查**;两道红队(异构)+ 两道人审(意图层 / 工单意图行)就是为堵这个。**严禁写实施细节**(那是 WO 的 HOW)。不写代码、不出工单。
