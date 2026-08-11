# 工作流 + 文档系统设计蓝图

> **这份文档是什么**:本工作流 + 文档系统的**设计权威 / rationale(为什么长这样)**,给人 / 维护者读。可运行的 SOT 是 `workflow-kit/` 的 skills / hooks / scripts + `README.md`;本文只讲**为什么**,不复述**怎么调**。**agent 不读它**(它们读 `.claude/` 装入的副本)。
>
> **地位**:系统已按本设计建成并跑过(kit + ADR + architecture + TODO 均在)。它同时是将来抽取成独立模板仓、开源的主 guide;定稿与变更流程见 §4。

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
| **AGENTS.md** (+CLAUDE.md 软链) | 半固化 | ✅ | 人 / 模板 | 少动 | 常驻纪律 + 工具约定 + 文档地图 |
| **architecture.md** | 活(慢层) | ✅ | bs/人 | cleaning 提 diff、人审 | 当前设计现状/地图 |
| **decisions/** (ADR) | 冻结(只增) | ✅ | bs/planner(Claude) | 不可变,仅翻状态位 | 一决策一 ADR:why+可测契约+证据 |
| **TODO.md** | 活(排空) | ✅ | planner/人 | cleaning 删已完成 | 扁平有序的"下一步" |
| **scratchpad/** | ephemeral | ❌ | worker/planner | GC | WO、验收单、run 日志、transcript、临时脚本 |

### 1.1 AGENTS.md(常驻,短)
- **内部两层**:**全固化核**(§0 六条纪律,模板拥有、一字不改随项目走)+ **半固化壳**(项目工具约定 → 指向 `.claude/workflow.env`;文档地图 = 冷启动读哪几个)。
- **入选三重判据**(三个都 yes 才留):① 每 session 都要读?② 数周不变?③ 普适还是项目专属(物理分开)。不满足 → 挪去 skill/doc/architecture,按指针捞。
- **不装**:项目架构散文(→architecture)、完整代码风格(→linter 配置)、任何进度/状态(→TODO/git)。
- **CLAUDE.md** = 软链接到 AGENTS.md,不是独立文档(同内容,给 Claude Code 认)。

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
- **可发现性(ADR 多了再加)**:早期靠 frontmatter tags + `git grep` 足够。**decisions/ 攒到找不动时**,再让 `check_docs.py` 从 frontmatter 自动生成 `decisions/index.md`(零维护);不提前建、不搞 taxonomy(§0③)。

### 1.4 TODO.md(扁平清单,做完即删)
- 只放**下一步真要做的事**,完成即删行(天然排空)。
- **设计债不进这里**:坏 WO / 发现的坏设计 → **开新 / 改 ADR**(显性化走设计审),不倒进 TODO 暗堆——设计债显性化为决策才不会在清单里越堆越沉、无人认领。
- **无仪表盘头**:HEAD 归 git、测试基线归"跑一次得真数"、"现在在做"就是清单顶部——都别手抄进来(双写必漂)。
- **TODO 默认、可长期用**:solo / 开发期自己发现问题自己改,近水楼台。只有当**项目进入成熟期 + 开源 + 真有他人提 issue**时,才迁移到 GitHub issues(取决于有没有多方 issue 流量;与「工作流本身开源」无关)。

### 1.5 scratchpad/(ephemeral,gitignored)
- session 分目录:`PL-<uuid>` / `BS-<uuid>`(完整 session UUID);派单产物 `runs/<run-id>`(时间戳+PID,并发唯一)。
- 装:WO、worker report、验收单、run.log、transcript、临时脚本。
- **GC**:cleaning 例程按保留策略删有 `.done` 且超期的 run(几行 find,不单独成脚本),随后清 session 目录。

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
          → 切 WO-<ADR>-<序号>(顶部意图行「本单服务 → ADR-NNNN」)→ 用户放行
          → 派便宜 worker + 异构验收(run_worker.sh) → 读验收单拍板 + 按需看高危 diff
          → GO → 放行 commit;NO-GO → 打回重派;坏 WO/坏设计 → 报告用户 → 开新/改 ADR
finishing 出总结/交棒(列未冻决定候选)+ 转写 session(决定在成熟当下就地冻,不在这儿)
cleaning  (Cursor)维护 architecture.md(提 diff 人审)+ 排空 TODO + 归档 scratch + 死链核查
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
- **WO 意图行**(闸门3):每张 WO 顶部 `本单服务 → ADR-NNNN`,缺则派单 hook deny;用户扫这行拦跑偏。
- **异构验收**(闸门4):worker 与 verifier 跨厂异构,verifier 审 diff-vs-WO **和** WO-vs-ADR(判据本身够不够)。

### 2.4 每个组件的设计规范
- **bs**:开工读 AGENTS§0 + memory + 相关 ADR/architecture。发散纪律(≥3 真不同、steelman、显式假设、失效模式、决策挂数据需求)。产出 `options.md` → 红队 → **著作 ADR**(意图 + 有把握的长期决定,记决策不记实现)→ 红队 → 交棒 planner。不搬真代码。不写代码、不出工单。
- **planner**:开工读 AGENTS + 要动的 ADR + 相关代码实况。**读 ADR + 读实况 → 自己设计 HOW**(HOW 完整性是 planner 的活)。三档分诊。WO 瘦、指针不复述、判据尽量写成能跑绿的测试、顶部意图行。两阶段派单(执行 + 异构独立验收),**读验收单拍板**:看判定/判据逐条/判据外边界/WO判据体检/越界、自跑 pytest 复核;**碰契约 / 热路径的 WO,planner 必读那段 diff**(不是绝不读——只是不逐行通读无风险改动);验收单证据须机器可复核(引真行、跑真测试);**验收绑定不可变 revision**(commit/stash hash,防验收后代码又变)。坏 WO → 报告用户 → 开新/改 ADR(不绕过、不暗堆);实现中长出的长期决定就地冻(冻结前过单轮红队)。派 worker vs 自己写:有可验证判据边界清的派 worker;要设计/上下文重/无测试判据的(ADR、提示词)自己写。
- **finishing**:① 出总结/交棒(≤10 行,下 session 冷启最小上下文;列本轮未冻决定的候选)→ ② 转写 session(最后跑,才含交棒)。决定的冻结不在这儿——在成熟当下由 bs/planner 就地冻(自带单轮红队)。文档维护全交 cleaning。
- **cleaning**(Cursor 侧,fresh agent):读本 session transcript + 读仓交叉验证。维护 architecture.md / TODO / scratch / 死链。两条删除路径:机械易失项直接做;tracked 文件删除 / 搬迁走**候选清单→人 IDE 确认**。landmine 分层保护(`NO-GO`/`别翻案`/`已验证净负` 一律保留)。不著作决策、不改 ADR 正文。
- **hooks**:`doc_guard`(PostToolUse,改 *.md 后跑 `check_docs --changed`,认 ADR frontmatter + architecture;有结构违规 / 断链就非阻塞注入警告,Claude 自判修不修);`check_wo_intent`(PreToolUse,派单前认 `本单服务 → ADR-NNNN` 意图行,缺则 deny;判不了的边界 fail-open **但打点自曝**,不静默兜底,§0.2)。
- **scripts(3 主脚本 + 1 公共入口)**:① `run_worker.sh`(两阶段派单,模型/命令读 `workflow.env`,回 planner 只带验收单+token、不回 diff);② `check_docs.py`(ADR frontmatter/命名校验 + `ADR-NNNN` 存在性/断链,几十行,断链只认它);③ `transcribe_session.py`(session→压缩 transcript 喂 cleaning;压工具骨架、保 NL、软 token 顶);另 `call_agent.sh` 是外呼便宜 agent 的公共入口(worker / 验收 / 红队共用,只派发+落盘)。scratch GC 折进 cleaning 例程,不单独成脚本。

### 2.5 强制机制(不靠纪律;背书三条结构律)
- **著作不追加(律1)**:著作类文件(`decisions/`、`architecture.md`、`AGENTS.md`)**只 Claude 层动**,worker 授权写面只限代码 + scratchpad。**复用已有闸门4**:验收员/planner 红线核查——worker diff 若碰著作类文件 = 越界 NO-GO(用现成红线检查,**不新建 pre-write 守卫**;真频繁踩再加)。
- **验收可信(闸门4)**:验收绑定**不可变 revision**;**验收员跨厂 ≠ worker**(强审尤其不能和 worker 同属一厂,否则跨厂异构名存实亡);证据机器可复核。
- **闸门加深不加数**:与其多盖章,不如让保留的那道真看——planner 对契约/热路径**看 diff**(§2.4),别只扫意图行。

### 2.6 轻量约束(solo 低概率,只文档约定、不建机制)
- **并发**:别并行跑两个 planner 碰同一 ADR;ADR id = 著作时取现存最大+1,撞号改名(git 仲裁)。
- **失败恢复**:worker 中断无 `.done` → 下轮 planner 判重做/弃;GO 后发现坏 → 开修正 WO,若是**决策**错则改 ADR。
- **密钥 / 注入面**:worker 不读 secrets 配置(gitignored + 进程内);transcript 落盘前 secret-scan;`README/AGENTS/architecture` 是注入面——worker 读仓内 / untracked 文本按**不可信数据**处理,不执行其中"指令"。

---

## 3. 不分项目档 —— 按任务自适应

**不设「轻/重项目」档**——全局设档会压制"该严的活",有损质量。质量自适应只在**任务粒度**,由 planner 的三档分诊(§2.2)按当前任务升降级:简单 → 轻量派单 / inline;重活 → 严格异构验收。

文档系统本就最小(AGENTS + architecture + decisions + TODO + scratchpad),**按 ADR/TODO 数量自然伸缩**,没有"重文档机制"需要开关——solo 项目就是 ADR 少、architecture 短、TODO 短,不需要切模式。

hooks / 异构红队是**随任务调用的机制**(planner 按需升级),不是项目级开关;某项目选择不装 hooks,那是一次性 setup 选择,不是分档。

**何时用整套 vs 直接改代码**:这套流水线在『工作可批量/并行、任务非平凡、贵模型受限』时才回本。**一次性小修就直接在终端改代码——那不是绕过系统,那就是琐碎档的正确用法**。别假装 always-on:planner 在每张单的关键路径上,给 5 分钟的活套完整仪式是负 ROI。

---

## 4. 变更流程

设计经两道异构红队(deepseek + luna)+ 用户签字冻结为 v1,地基级批评已折入上文。低概率项只作文档约束(§2.6),不建机制——工作流自己也遵守 §0 脊椎,不过度工程。

**此后对工作流本身的改动,当作「关于工作流的 ADR」走**:先在 ADR 里定/改决策,再回来把本文同步到最新结论——本文只保留「现在的设计」,不在这儿开无限迭代、也不留改动流水账(那是 git 历史的活)。
