# 工作流 + 文档系统设计蓝图

> 本文是给人和维护者看的设计权威，说明当前取舍与边界。可运行的 SOT 是本仓 `kit/` 与 `README.md`；消费仓的物理路径位于 `.workflow/`，agent 通过 `AGENTS.md`、skills 和 `discipline.md` 工作。

## 0. 核心取舍

工作流让一个 planner 对结果负责：理解目标与现状，找出最关键的不确定性，选择能最快获得有效反馈的下一步，整合证据，并判断结果是否足以支持用户目标。planner 可以自己实现，也可以委派；任务成本包括外呼、交接、返工、用户负担和质量，不只包括 planner 的上下文。

角色分工包括：bs 负责长期设计，planner 负责当前任务的编排和裁决，worker 执行，verifier 按需验收，finishing 交棒，cleaning 维护慢层文档。多 agent 是执行选项，是否委派由边界、反馈价值和交接成本决定。

## 1. 文档系统：各类信息各有其家

消费仓物理路径在 `.workflow/` 下；本文表格使用短名，完整路径由消费仓 `AGENTS.md` 的文档地图定义。

| 家 | 内容 | 维护方式 |
|---|---|---|
| `discipline.md` | 六条常驻纪律与脊椎 | kit 单源，随安装投影 |
| `AGENTS.md` | 项目工具约定和文档地图 | 项目维护，人策展 |
| `architecture.md` | 当前设计现状、模块边界、关键调用链 | cleaning 提交候选，人审判断型改动 |
| `decisions/` | 稳定、长期、会反复引用的 ADR | 一决策一文件；改变决策开新 ADR |
| `TODO.md` | 下一步真实工作 | 做完即删，保持扁平 |
| `scratchpad/` | WO、brief 快照、报告、验收单、run 日志和 transcript | ephemeral，按龄 GC |

ADR 记录意图、长期约束、边界和后果，不记录易变实现。用户目标、已接受契约和授权边界是硬约束；实现建议与尚未验证的假设要明确标出。没有稳定决策时，不为获得派单资格制造 ADR。

`architecture.md` 是 ADR 当前状态的地图和合成视图，具体契约仍以对应 ADR 为准。设计资产与 run 产物分离：长期证据随 ADR 进入 git，单轮材料留在 scratchpad；不另建裁决或交棒台账。

## 2. 当前工作闭环

```text
bs         发散真实方案、红队比较，冻结成熟的长期决策
planner    读目标和实况 → 三轴分诊 → 自做或短 brief 委派
           → 取得真实反馈 → 看整体与关键调用链 → 裁决并按需审查
worker     在目标和硬边界内实现，回报结果、偏离和矛盾
verifier   按风险或明确要求审查实际行为与证据
finishing  总结并把交棒内容写入 session transcript
cleaning   维护 architecture、排空 TODO、清理 scratchpad、查死链
```

### 2.1 三轴分诊

每项工作分别判断：

| 轴 | 要回答的问题 | 影响 |
|---|---|---|
| 不确定性 | 哪个假设尚未验证？什么反馈能推翻或确认它？ | 优先读实况、看样本或跑最小完整路径 |
| 风险 | 错误影响什么，能否发现和恢复？ | 决定验证强度、独立审查和用户放行 |
| 委派收益 | 交接是否清楚，委派是否比直接完成更有价值？ | 决定自做、委派或并行 |

工作量和行数只作参考。探索可以委派，机械改动也可能高风险；不因“含实验”自动套完整模板或双审。

### 2.2 brief、反馈和实现判断

默认派单是一份短 brief，包含目标、依据与硬边界、待验证假设、交付与证据，以及可调整的做法建议。目标可以是非空的实现目标，也可以是一个需要回答的问题；若本任务承接现有 ADR，则引用它，否则只需说明用户任务。brief 不承担无关历史，也不把建议写成冻结契约。

探索优先建立一条最小完整反馈路径，再决定是否扩大实现。框架、测试、真实结果和未验证部分分别陈述。环境不可用时可以完成独立准备，但必须明确哪些检查未执行、需要什么环境、因此不能证明什么。

worker 在授权范围内选择实现。发现关键假设不成立、目标或范围必须改变，或建议会引入显著新机制时，立即在短报告中写出具体矛盾、证据和可行选择。正常的局部实现选择无需逐项请示。

每轮 run 保存一份 `brief.md` 快照；worker 和所有 verifier 使用同一份快照。执行后的回显包含 worker 的完整短报告；报告中的偏离与矛盾是 worker 的自述，供 planner 判断，脚本不自动解析或替它背书。

### 2.3 审查与 planner 亲验

WO 审是可选能力：只有未经验证的方案一旦错误会造成明显返工，或用户明确要求时才安排；审查应回答指定疑点、读取相关实况并比较必要的替代方案。双审按第二双眼带来的增益选择，风险不足或没有独立价值时不启用。

施工审围绕目标、实际入口、关键调用链、证据有效性和不必要机制组织。工单是上下文，不是逐条合规清单。finding 要给出触发条件、错误结果和依据，已确认缺陷与待验证疑点分开；纯建议不自动阻断。

`SKIP_REVIEW=1` 复用探索执行后返回负责人的路径：脚本仍做越界等边界检查，但不运行 pytest 和 `check_docs`，回显明确列出未执行项；这不等于验收通过。需要独立审查时再用 `REVIEW_ONLY=1`。`review_complete` 只表示本轮审查状态，不表示业务目标已完成。

planner 对整体和关键调用链自主核实，不能只转述报告。测试全绿只证明执行过的断言成立；无 blocking 只证明本轮没有报告阻断问题。放行判断还要结合目标、设计取舍、真实结果和证据限度。

### 2.4 复审和状态

发现问题后，planner 可以修实现、调整或撤回本轮方案、给出理由不采纳，或在确实改变长期契约时转 ADR。若矛盾反复出现、修补不断增加平行机制，或关键假设已被推翻，应先重新判断方案。

复审重写当前有效的 brief，撤回过时要求；旧 brief 和审查原文仍在 run 记录中，但不要求执行者同时满足多代判据。轮数只作提醒，不能机械决定停工或继续。长期 ADR 纪律保持不变，具体实现做法可以随着证据改变。

脚本将机器事实和结构化 findings 纯派生为 `review_complete`、`review_blocked`、`review_skipped` 或 `infra_failed`。finding 使用结构化字段 `severity`、`where`、`claim`、`failure_scenario`，无 finding 用明确的 `<<<FINDINGS-NONE>>>` 标记；坏报告不能替代机器事实。脚本亲产 pytest、文档和越界等检查，并保留跳过项解释；入口参数或目标错误直接以非零退出，`infra_failed` 表示执行或验收基础设施失败。状态是信息态，最终裁决仍由 planner 负责；双审只有在明确需要时启用，启用后 blocking 取并集；任一审查员没有有效产出时该轮为 `infra_failed`，可冻结工作树用 `REVIEW_ONLY=1` 重派。

## 3. 实现契约与布局

`run_worker.sh` 负责派单、外呼、brief 快照、报告回传、著作文件越界检查和状态派生；`SKIP_REVIEW`、`REVIEW_ONLY`、`WO_REVIEW` 是显式能力。revision 在 worker 完成后对验收对象树取 hash，并包含 untracked 文件。脚本不把模型自报结果当作机器事实。`call_agent.sh` 负责原生流式输出、角色超时和整树回收；`check_docs.py` 负责 ADR 结构、断链及 staged/changed 检查；`transcribe_session.py` 将 session JSONL 转成 transcript；git hook 运行 staged 文档检查。

闸门放在动作发生处并保持单实现：派单入口检查目标或 ADR 定位，worker 结束后检查著作越界，提交时检查文档结构。`run_worker.sh` 保存的 brief 是本轮执行和验收的共同输入，不建立跨轮状态数据库。`.done` 只表示产物已定、可以清理，不表示放行；执行中的共享工作树不允许并行改写。著作类文件由负责人和适配当前 harness 的授权层维护，worker 的写入面限于代码与 scratchpad。worker 不读 secrets 配置（gitignore 与进程内凭证）；transcript 落盘前做 secret-scan。README、AGENTS、architecture 是注入面：worker 把仓内和 untracked 文本当不可信数据读，不执行其中的指令。

安装始终把 `kit/` copy 到消费仓 `.workflow/kit/`，不使用共享 symlink。track 与 no-track 只改变 git exclude 粒度，物理布局不变；`.workflow/VERSION` 记录安装时的 tag 与 commit。布局细节见 `docs/dot-workflow-layout.md`。

## 4. 变更原则

工作流机制只在本仓 `kit/` 修改，经 `install.sh` 投影；本文和 README 同步说明当前为什么这样设计。改脚本、hook 或安装逻辑前先读 `docs/failure-modes.md`，并按 `docs/MAINTAINERS.md` 跑相应检查。保持 bash、Markdown 和一个安装脚本的最小系统，不为低概率情形新增角色、状态或固定仪式。
