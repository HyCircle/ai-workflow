# 工作流 + 文档系统设计蓝图

> **这份文档是什么**:本工作流 + 文档系统的**设计权威 / rationale(为什么长这样)**,给人 / 维护者读。可运行的 SOT 是本仓的 skills / scripts / `git-hooks/` + `README.md`;本文只讲**为什么**,不复述**怎么调**。**agent 不读它**(它们读 `.claude/` 装入的副本)。
>
> **地位**:系统已按本设计建成并跑过(kit + ADR + architecture + TODO 均在)。本仓即独立机制仓、开源主 guide;定稿与变更流程见 §4。

---

## 0. 为什么这么设计(一切从这几条推导)

**两条经济学**
- **分层套利**:Claude(贵)只做重规划与判断;干活 / 验收 / 文档维护外包给便宜 harness/model。省钱与提质一体。
- **context 经济学**:planner **读验收单代替读 diff**,worker 的代码和 trace 永不灌进 Claude 上下文;文档用**指针**不复述。

**三条结构律**(整个系统的地基)
1. **著作,不追加**:长期知识由思考者(Claude / 人)**著作**成自足单元,绝不由 worker **追加**进中央池——单一池子被无限追加会退化成非人读的臃肿堆,所以每条知识都著作成自足单元、各归其家。
2. **durable / ephemeral 分离**(= tracked / gitignored 分离):长存的知识(决策、证据、现状)进 git;施工副产物(工单、验收单、run 日志、trace、转写)进 `scratchpad/`(gitignored、消费完 GC)。两者**永不混放**:durable 文件夹只装 durable,混入 transient 泥沙就会天天 churn。
3. **海拔分离(按是否长期)**:决策活在哪层由**是否长期(不可逆 / 会被反复引用)**决定——长期决策 → **ADR**;一次性执行步骤 → **WO**(ephemeral)。**ADR 记决策、不记实现**(可配伪代码,不搬真代码;写法 / 判据见 §1.3 与模板)。

**脊椎:开发期少即是多**。默认不加;补丁层 / 兜底 / 抽象 / 边界 / 测试,加之前先证明非加不可(有真实触发路径)。

---

## 1. 文档系统:五个家 + 别名

一类信息一个家,按**时态**切分。状态不单立仪表盘文件(见 §1.6)。

| 家 | 时态 | tracked? | 谁著作 | 谁维护 | 装什么 |
|---|---|---|---|---|---|
| **agent-discipline.md** | 全固化(kit) | ❌(kit 投影) | kit | 一字不改随项目走 | 常驻六条纪律 + 脊椎 |
| **AGENTS.md** (+CLAUDE.md 软链) | 半固化 | ✅ | 人 / 模板 | 少动 | 项目工具约定 + 文档地图 + 指向 discipline |
| **architecture.md** | 活(慢层) | ✅ | bs/人 | cleaning 提 diff、人审 | 当前设计现状/地图 |
| **decisions/** (ADR) | 冻结(只增) | ✅ | bs/planner(Claude) | 不可变,仅翻状态位 | 一决策一 ADR:why+可测契约+证据 |
| **TODO.md** | 活(排空) | ✅ | planner/人 | cleaning 删已完成 | 扁平有序的"下一步" |
| **scratchpad/** | ephemeral | ❌ | worker/planner | GC | WO、验收单、run 日志、transcript、临时脚本 |

### 1.1 常驻纪律(agent-discipline.md)+ 项目壳(AGENTS.md)
**全固化核与半固化壳拆成两个物理文件**:
- **agent-discipline.md** = **全固化核**(六条纪律 + 脊椎),**kit 拥有、一字不改随项目走**。像 skills/scripts 一样**投影**进各项目(gitignored 副本 / symlink 共读),版本管理只在 kit。这样(a)纪律单源、随 kit 更新;(b)装进**已有 AGENTS.md** 的项目时,不覆盖它的 AGENTS.md,只投影 discipline + 补一行指针。
- **AGENTS.md** = **半固化壳**(项目工具约定 → 指向 `.claude/workflow.env`;文档地图;顶部一行指向 discipline),项目自己拥有。
- **纪律怎么到 agent 手里**:交互 harness 读 AGENTS.md(指针)+ skills「开工先读」列 discipline;**worker/验收**由 `run_worker.sh` 把 discipline **注进 prompt 开头**(不靠各 harness 的 AGENTS 自动加载,保证送达)。
- **入选核的三重判据**(三个都 yes 才留在 discipline):① 每 session 都要读?② 数周不变?③ 普适(非项目专属)。项目专属的挪去 AGENTS 壳 / skill / architecture。
- **CLAUDE.md** = 软链接到 AGENTS.md(给 Claude Code 认);单源,不是第二份要维护的文档。若 harness 直接认 AGENTS.md 可省掉它。

### 1.2 architecture.md(活地图,只装慢层)
- 只装**慢层**:模块边界、数据模型、关键不变量、对外契约、全局地图、术语。几周才动一次 → 同步成本低。
- **不装**:施工脚手架(路线图 / Epic→工单 / 待决问题 → TODO)、易变数据(服务清单 → 配置 `*.example`)、决策历史(→ ADR)。装多了就天天 churn。
- **权威从属 ADR**:architecture 是各 ADR 决策的**当前状态合成视图** + 冷读地图;任何具体不变量 / 边界 / 契约的**单一事实源是对应 ADR**,architecture 只复述并指 `ADR-NNNN`,两者冲突时 **ADR 赢**——一处事实一个源,architecture 复述而不与 ADR 双认领。
- **维护**:cleaning 从 transcript + 读仓提 diff,**人在 IDE 审**(判断型改动走候选清单)。

### 1.3 decisions/ —— ADR(决策记录)
- **定位**:一决策一 ADR,只装**决策内核**——HOW 卸给 WO、现状卸给 architecture、状态卸给 TODO。正因这些都不背,ADR 才瘦得下、停在人读高度。
- **不可变**:改决策 = **开新 ADR**,旧 ADR 翻 `status: superseded` / `superseded_by`,**不改旧正文**——文件级 supersede,不在文件内打补丁。
- **单文件 / 文件夹**:无附件 → `decisions/NNNN-slug.md`;有 durable 证据(实验数据 json/csv、notebook、一次性脚本)→ 文件夹 `decisions/NNNN-slug/`,**主 md 与文件夹同名**(不叫 README——多标签认得出),证据就近同放。**只有 durable 证据进这里;ephemeral 的 WO/run 产物进 scratchpad**。
- **写法**(权威见 `decisions/0000-template.md`):
  - **frontmatter**:`id/title/date/status(proposed|accepted|superseded|deprecated)/supersedes/superseded_by/tags`。验证脚本读结构化字段,不啃散文。
  - **意图**:给人的散文 2–3 句(为什么/价值/边界),**禁 §引用、禁代码**。这是"生来可读"的车道。
  - **决策**:拍板做什么——不变量 / 边界 / 硬上限 / **明确不做**。可配伪代码 / 算法;**不搬真代码**(file:line / 实现照抄归代码,会漂)。
  - **备选与失效模式**:被否的路 + 各自"若选它会怎么错"(最防重踩的一节)。
  - **后果**。
  - **引用**:代码 / 文档写 `ADR-NNNN`;断链检查 = 查 `decisions/NNNN-*` 在不在(存在性检查,不解析子章节)。
- **记决策、不记实现**:ADR 写意图 + 有把握的长期决定;能用代码 + 测试表达的形状放代码、ADR 只引不誊写;拿不准的先别冻。
- **何时才写**:决策**稳定、会长期生效**(不可逆 / 会被反复引用)才写 ADR;早期高频探索留在 scratchpad / architecture 草稿。只在决定真稳时冻,不是每次结晶。
- **证据谁搬**:实验支撑某决策时,**由 ADR 起草人在著作时顺手把 scratchpad 的 json/csv/notebook 提升进 `decisions/NNNN-slug/`**——是著作动作的一部分,不是 worker/GC 的活(否则 ADR 文件夹永远空)。
- **可发现性(ADR 多了再加)**:早期靠 frontmatter tags + `git grep` 足够。**decisions/ 攒到找不动时**,再让 `check_docs.py` 从 frontmatter 自动生成 `decisions/index.md`(零维护);不提前建、不搞 taxonomy(纪律③)。

### 1.4 TODO.md(扁平清单,做完即删)
- 只放**下一步真要做的事**,完成即删行(天然排空)。
- **设计债不进这里**:坏 WO / 发现的坏设计 → **开新 / 改 ADR**(显性化走设计审),不倒进 TODO 暗堆——设计债显性化为决策才不会在清单里越堆越沉、无人认领。
- **无仪表盘头**:HEAD 归 git、测试基线归"跑一次得真数"、"现在在做"就是清单顶部——都别手抄进来(双写必漂)。
- **TODO 默认、可长期用**:solo / 开发期自己发现问题自己改,近水楼台。只有当**项目进入成熟期 + 开源 + 真有他人提 issue**时,才迁移到 GitHub issues(取决于有没有多方 issue 流量;与「工作流本身开源」无关)。

### 1.5 scratchpad/(ephemeral,gitignored)
- session 分目录:`PL-<uuid>` / `BS-<uuid>`(完整 session UUID);派单产物 `runs/<run-id>`(时间戳+PID,并发唯一)。
- 装:WO、worker report、验收单、run.log、transcript、临时脚本。
- **GC**:cleaning 例程留最近 N 个(默认 20)有 `.done` 的 run、其余删(几行 find,不单独成脚本),随后清 session 目录。

### 1.6 没有 STATE 仪表盘文档
状态不单立一个仪表盘文件:冷启动读 AGENTS(地图)+ architecture(现状)+ TODO(下一步)+ 相关 ADR 就够。各类状态各归其家——已冻契约 → ADR + architecture;候选 / 当前活跃 → TODO;悬而未决 → TODO 或 proposed 的 ADR;已知地雷 → **代码本地注释** + AGENTS 项目铁律。手抄进单一仪表盘只会与这些真源双写漂移。

### 1.7 知识去哪(各类知识的家)
| 知识类型 | 新家 | 为什么 |
|---|---|---|
| 领域坑 / gotcha | **代码注释 / docstring**(触发点本地) | 碰到那行才读,不是中央文件读太晚 |
| 成规则的教训 | **ADR** | 教训=一个"以后要/不要 X"的决策 |
| 项目级铁律(跨切面) | **AGENTS.md 一小节** | 人策展、封顶,非追加 |
| 设计债 / 坏 WO 欠账 | **新 / 改 ADR** | 显性化为决策修正,不暗堆 |
| 实验数据 / A/B | **ADR 的证据**(文件夹内) | 实验终结于它支撑的决策 |
| "干了啥"叙事 | **ADR 本身**(生来可读) | 免二次蒸馏;按时间读 decisions/ = 设计故事 |
| 跨切面总览 | **architecture.md** | 活地图 |

---

## 2. 工作流:四角色,分层

**Claude(贵,出思考)**:`bs` 著作 ADR · `planner` 切 WO / 拍板 · `finishing` 收尾。
**便宜 harness**:`worker` 执行 · `verifier` 异构验收 · `cleaning`(Cursor)维护文档。
决策**只 Claude 层著作**,worker/cleaning 永不著作决策。

### 2.1 一轮完整闭环
```
bs        发散(≥3 真不同方案,各 steelman+失效模式) → 异构红队选项册
          → 收敛、著作 ADR(意图 + 有把握的长期决定,记决策不记实现)→ 冻结前红队 + 人审意图层 → accepted
   ↓ 交棒
planner   读 ADR → 读实况(grep/read 核实 file:line)
          → 设计 HOW(实现中长出的长期决定 → 就地单轮红队 + 冻结)
          → 切 WO-<ADR>-<序号>(顶部意图行「本单服务 → ADR-NNNN」)
          → WO 审(WO_REVIEW=1,派 worker 前审工单质量)→ 裁决 blocking → 用户放行
          → 派便宜 worker + 异构施工审(run_worker.sh)→ 读 STATUS 四态 + findings 拍板 + 按需看高危 diff
          → 对每条 blocking 出裁决(修/驳回+理由/转 ADR),驳回/跳过亲验的理由随 commit 落库
          → 都裁决且机器事实干净 → 放行 commit;要修 → 收窄复审 WO-…b;坏 WO/坏设计 → 报告用户 → 开新/改 ADR
finishing 出总结/交棒(列未冻决定候选;只进会话、随转写落 transcript,不另立文件)+ 转写 session(决定在成熟当下就地冻,不在这儿)
cleaning  (Cursor)维护 architecture.md(提 diff 人审)+ 排空 TODO + 清理 scratch + 死链核查
```

### 2.2 三档分诊(每个活先判,别高射炮打蚊子)
| 档 | 什么活 | 怎么走 |
|---|---|---|
| 琐碎 | 单文件/<~20行/无设计 | 自己改 或 `SKIP_REVIEW=1`,抽验 |
| 小 | 边界清/判据一两条/不碰热路径 | 3–5 行 inline 派单,走两阶段 |
| 复杂/高危 | 碰契约/热路径/多文件/有陷阱/含实验 | 全模板 WO,异构双验收,亲验需亲验点 |

### 2.3 闸门(异构 + 人审,堵同源盲区)
- **人审意图层**(闸门1):bs 把各 ADR 意图行聚一屏给用户,他有产品意图,一屏否掉不合理设计。
- **红队 ADR**(闸门2):**任何 ADR 冻结前**,交异构只读模型审一遍(单轮)——契约自洽、判据能证伪、没搬真代码、没为不存在的边缘写东西。bs 冻在纸面、动工前;planner 冻在实现里决定成熟的当下。
- **WO 意图行**(闸门3):每张 WO 顶部 `本单服务 → ADR-NNNN`(改工作流机制本身的单指 `workflow.md §N`),缺 / 指向不可核实的锚(如 slug-ADR)则 `run_worker.sh` 入口拒派;只收 `ADR-NNNN`(check_docs 能验断链)与 `workflow.md`(kit 的 durable 权威,恒在),用户扫这行拦跑偏。
- **异构验收**(闸门4):worker 与 verifier 跨厂异构;**拆两专项**——WO 审(派 worker 前审 WO-vs-ADR)+ 施工审(派 worker 后审 diff-vs-WO,经 diff 暴露的 WO 缺陷仍可报)。verifier 只提交结构化 findings,放行状态由脚本纯派生(§2.5)。

### 2.4 每个组件的设计规范(HOW 的 SOT = `.claude/skills/*`,这里只记 why 层取舍)
四角色 bs/planner/finishing/cleaning 的操作细节权威在各自 skill;本节只留不落在 skill 里的**设计取舍**:
- **bs vs planner 分脑**:bs 发散(≥3 真不同 + 红队),planner 冻结脑 + 切 WO;同一强模型「出设计又派单」共同盲区不互查,故设两道异构红队 + 两道人审(§2.3)。
- **验收员 ≠ worker 模型家族**:异构才是真独立第二双眼;高危双验收第二审尤其不能同家族。
- **闸门在动作处,单实现、可移植**:意图行校验在 `run_worker.sh` 派单入口、著作类文件越界校验在 worker 执行之后(跳过验收也跑)、文档结构校验在 git `pre-commit`(校验 index 待提交内容)。**同一逻辑单实现**(一处触发,不在多处重复),移植到 Cursor/Codex 等 harness 时闸门照在。
- **scripts 3+1 + 1 git hook**:`run_worker.sh`(四模式派单:施工+施工审 / SKIP_REVIEW / REVIEW_ONLY / WO_REVIEW;内化意图/越界闸门;把放行状态**对不可变输入纯派生**成一个 `STATUS:` 四态,退出码只有 `infra_failed` 非零;把 discipline 注进 worker/验收 prompt 开头;外呼流式只落 run.log)、`check_docs.py`(ADR 结构/断链 canonical,`--changed` 看工作树 / `--staged` 看 index blob;仓根按 **git toplevel** 定位,故 symlink 共读时也扫对消费仓)、`transcribe_session.py`(session JSONL→markdown transcript);`call_agent.sh` 是外呼公共入口(CLI 原生流式 + 分角色超时杀整树)。git `pre-commit` 跑 `check_docs --staged`。scratch GC 折进 cleaning,不单独成脚本。

### 2.5 强制机制(不靠纪律;背书三条结构律)
- **著作不追加(律1)**:著作类文件(`decisions/`、`architecture.md`、`AGENTS.md`)**只 Claude 层动**,worker 授权写面只限代码 + scratchpad。越界校验**由 `run_worker.sh` 在 worker 执行后亲跑**(跳过验收也跑),产出机器事实喂进放行派生。
- **验收可信 = 判定不由模型持有(闸门4)**:验收模型**只写它有权威的东西**(结构化 findings:发现了什么);身份 / 机器事实(pytest·越界·check_docs)/ 最终放行状态一律由 `run_worker.sh` 按一条可计算式**从不可变输入纯派生**成四态(`review_complete|blocked|skipped|infra_failed`)。**一个判定源**——机器事实脚本亲产、放行状态脚本派生、退出码只 `infra_failed` 非零,planner 直读验收报告不再转述。**验收员跨厂 ≠ worker**;**revision = worker 改完后对验收对象树取 hash**(含 untracked);WO 审 hash 工单内容。
  - **finding 结构 = sentinel 块**(每条 `<<<FINDING…FINDING>>>`,字段各占一行、值可含冒号引号、无嵌套转义):E5 实测 sentinel/jsonl 干净率 100%、yaml-fence 50%(整块 ScannerError),sentinel 再以「无转义负担 + 人读性」破 jsonl 的平局。冻语义(severity/where/claim/failure_scenario;blocking 须指名具体错误结果,否则为 nit)+ 这个语法;坏一块只跳一块。**nit 不进派生式,但 derive 必列 nit 自曝清单**(where+claim 逐条),供 planner 可选采纳、让「被降级为 nit 的东西」可见。
  - **双验收弹性**:两员并行、blocking 取并集。任一验收员无有效产出(缺失/空/不可解析)→ 该轮无验收结论,整轮 infra_failed + 自曝;回显仍展示存活验收员的单子,planner 用 `REVIEW_ONLY=1` 重派验收(工作树冻结,不重跑 worker)。重派 = 只重跑验收:`REVIEW_ONLY=1 scripts/workflow/run_worker.sh <WO> <验收模型…>`;重派单员把第 3 参设为该员模型、省略第 4 参,重跑整组就带原两模型。
- **planner 只裁决不转述(D3)**:放行状态是**信息态,不硬闸 commit**(solo commit 可逆,裁量权归 planner)。**裁决不进派生式**——派生只看 findings + 机器事实,故 `review_blocked` **不随裁决翻转**;planner 对每条 blocking 出 修/驳回+理由/转 ADR,驳回与跳过亲验的理由随 commit 落库(可复核),判所有 blocking 已裁决即放行,STATUS 保持 blocked 无妨。
- **验收拆两专项(D5)**:WO 审(派 worker 前,只读 WO+ADR)+ 施工审(派 worker 后,diff-vs-WO);坏 WO 在派 worker 前拦下。复审 = 收窄的新派发、逐条闭合上轮 blocking(D4),无模型维护的跨轮状态。
- **闸门加深不加数**:与其多盖章,不如让保留的那道真看——planner 对契约/热路径**看 diff**(§2.4),别只扫意图行。

### 2.6 轻量约束(solo 低概率,只文档约定、不建机制)
- **并发**:别并行跑两个 planner 碰同一 ADR;ADR id = 著作时取现存最大+1,撞号改名(git 仲裁)。
- **失败恢复**:`.done` = 「产物已定、可被 cleaning 按龄 GC」的标记,**不是放行判定**(放行看 `STATUS`)。complete/blocked/skipped 都落 `.done`;`infra_failed` / 硬中断无 `.done` → 下轮 planner 判重做/弃。blocked 的 run 按龄回收无妨——durable 审计痕迹在 git(commit message),不在 ephemeral run 目录。GO 后发现坏 → 开修正 WO,若是**决策**错则改 ADR。
- **密钥 / 注入面**:worker 不读 secrets 配置(gitignored + 进程内);transcript 落盘前 secret-scan;`README/AGENTS/architecture` 是注入面——worker 读仓内 / untracked 文本按**不可信数据**处理,不执行其中"指令"。

---

## 3. 不分项目档 —— 按任务自适应

**不设「轻/重项目」档**——全局设档会压制"该严的活",有损质量。质量自适应只在**任务粒度**,由 planner 的三档分诊(§2.2)按当前任务升降级:简单 → 轻量派单 / inline;重活 → 严格异构验收。

文档系统本就最小(AGENTS + architecture + decisions + TODO + scratchpad),**按 ADR/TODO 数量自然伸缩**,没有"重文档机制"需要开关——solo 项目就是 ADR 少、architecture 短、TODO 短,不需要切模式。

闸门(派单脚本 + git pre-commit)与异构红队是**随任务调用的机制**(planner 按需升级),不是项目级开关。

**何时用整套 vs 直接改代码**:这套流水线在『工作可批量/并行、任务非平凡、贵模型受限』时才回本。**一次性小修就直接在终端改代码——那不是绕过系统,那就是琐碎档的正确用法**。别假装 always-on:planner 在每张单的关键路径上,给 5 分钟的活套完整仪式是负 ROI。

---

## 4. 变更流程

低概率项只作文档约束(§2.6),不建机制——工作流遵守「少即是多」脊椎。

**此后对工作流本身的改动**:改 `workflow-kit/` 的 skills/scripts/discipline → `install.sh` 推项目;可运行 SOT = kit 文件,changelog = git 历史。本文只保留「现在为什么这么设计」,改完同步到最新结论即可,不留改动流水账。**改工作流机制本身的 WO 意图行指 `workflow.md §N`**(kit 的 durable 权威;kit 不给自己编号 ADR)。

**可移植性(投影 + 共读 + 本地忽略)**:`.claude/skills`、`scripts/workflow`、`agent-discipline.md` **投影进消费项目**。`install.sh` 两种模式:默认 **copy**(冻结快照,Windows 稳;只在 kit 改,再 `install.sh` 推项目);`--link` **symlink 共读**(项目指向 kit 单源,改 kit 即时生效、免重装)。忽略项写进 **`.git/info/exclude`**(本地、不污染消费项目 tracked 的 `.gitignore`),装进已有项目零改其版本库。`.cursor/.codex` 的内容投影待从那些 harness 驱动 planner 时再补。
