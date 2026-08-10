# 工作流 + 文档系统设计蓝图

> **这份文档是什么**:新工作流 + 文档系统的**权威蓝图(SSOT)**。仓库里现有粘进来的 `.claude/skills`、`.claude/hooks`、`scripts/workflow` 是**上个项目的遗留、全部「待替换」**——实施阶段按本蓝图**从零重建**,不在旧文件上修修补补(§0①:掀地基,别 patch-on-patch)。
>
> **怎么用**:先把这份读透、交异构模型红队捅盲区,**改到没有遗漏再动手写代码**。它同时是将来抽取成独立模板仓、开源出去的主 guide。

---

## 0. 为什么这么设计(一切从这几条推导)

**两条经济学**
- **分层套利**:Claude(贵)只做重规划与判断;干活 / 验收 / 文档维护外包给便宜 harness/model。省钱与提质一体。
- **context 经济学**:planner **读验收单代替读 diff**,worker 的代码和 trace 永不灌进 Claude 上下文;文档用**指针**不复述。

**三条结构律**(整个系统的地基)
1. **著作,不追加**:长期知识由思考者(Claude / 人)**著作**成自足单元,绝不由 worker **追加**进中央池。上个项目的 LESSONS 烂掉,就因为 worker 往一个池子里无限追加 → 非人读 + 臃肿。
2. **durable / ephemeral 分离**(= tracked / gitignored 分离):长存的知识(决策、证据、现状)进 git;施工副产物(工单、验收单、run 日志、trace、转写)进 `scratchpad/`(gitignored、消费完 GC)。两者**永不混放**——混放就是"durable 文件夹堆 transient 泥沙",老病复发。
3. **海拔分离(按粘性,不按证据来源)**:决策活在哪层由**粘性 / 可逆性 / 被引用频率**决定,**不由"定它要不要读代码"决定**——不可逆或会被反复引用的粘性决策 → **ADR**(哪怕定它需要读代码);一次性执行步骤 → **WO**(ephemeral)。**证据来源只决定"谁起草"**:纯设计推理的决策 bs 起草;**"代码实据型粘性决策"仍进 ADR,但契约由读过代码的 planner 起草,bs 只写意图**。这既根除"凭记忆写实施细节→冻进 spec→层层偏离"(§0④),又不把粘性架构决策错误流放进用完即弃的 WO。

**脊椎:开发期少即是多**。默认不加;补丁层 / 兜底 / 抽象 / 边界 / 测试,加之前先证明非加不可(有真实触发路径)。

---

## 1. 文档系统:五个家 + 别名

一类信息一个家,按**时态**切分。STATE 已**溶解**(见 §1.6)。

| 家 | 时态 | tracked? | 谁著作 | 谁维护 | 装什么 |
|---|---|---|---|---|---|
| **AGENTS.md** (+CLAUDE.md 软链) | 半固化 | ✅ | 人 / 模板 | 少动 | 常驻纪律 + 工具约定 + 文档地图 |
| **architecture.md** | 活(慢层) | ✅ | bs/人 | cleaning 提 diff、人审 | 当前设计现状/地图 |
| **decisions/** (ADR) | 冻结(只增) | ✅ | bs/finishing(Claude) | 不可变,仅翻状态位 | 一决策一 ADR:why+可测契约+证据 |
| **TODO.md** | 活(排空) | ✅ | planner/人 | cleaning 删已完成 | 扁平有序的"下一步" |
| **scratchpad/** | ephemeral | ❌ | worker/planner | GC | WO、验收单、run 日志、transcript、临时脚本 |

### 1.1 AGENTS.md(常驻,短)
- **内部两层**:**全固化核**(§0 五条纪律,模板拥有、一字不改随项目走)+ **半固化壳**(项目工具约定 → 指向 `.claude/workflow.env`;文档地图 = 冷启动读哪几个)。
- **入选三重判据**(三个都 yes 才留):① 每 session 都要读?② 数周不变?③ 普适还是项目专属(物理分开)。不满足 → 挪去 skill/doc/architecture,按指针捞。
- **不装**:项目架构散文(→architecture)、完整代码风格(→linter 配置)、任何进度/状态(→TODO/git)。
- **CLAUDE.md** = 软链接到 AGENTS.md,不是独立文档(同内容,给 Claude Code 认)。

### 1.2 architecture.md(活地图,只装慢层)
- 只装**慢层**:模块边界、数据模型、关键不变量、对外契约、全局地图、术语。几周才动一次 → 同步成本低。
- **不装**:施工脚手架(路线图 / Epic→工单 / 待决问题 → TODO)、易变数据(服务清单 → 配置 `*.example`)、决策历史(→ ADR)。装多了就天天 churn。
- **权威从属 ADR**:architecture 是各 ADR 决策的**当前状态合成视图** + 冷读地图;任何具体不变量 / 边界 / 契约的**单一事实源是对应 ADR**,architecture 只复述并指 `ADR-NNNN`,两者冲突时 **ADR 赢**。消灭"architecture 与 ADR 双认领"的漂移。
- **维护**:cleaning 从 transcript + 读仓提 diff,**人在 IDE 审**(判断型改动走候选清单)。

### 1.3 decisions/ —— ADR(决策记录)
- **定位**:旧 PLAN 决策内核(§0/§3)的继任者。**ADR = PLAN 减去(现状 + HOW)**:HOW→WO,现状→architecture,状态→TODO。正因卸载,它才瘦得下、停在人读高度。
- **不可变**:改决策 = **开新 ADR**,旧 ADR 翻 `status: superseded` / `superseded_by`,**不改旧正文**(取代旧 PLAN 的"§X.0 修正块",文件级 supersede)。
- **单文件 / 文件夹**:无附件 → `decisions/NNNN-slug.md`;有 durable 证据(实验数据 json/csv、notebook、一次性脚本)→ 文件夹 `decisions/NNNN-slug/`,**主 md 与文件夹同名**(不叫 README——多标签认得出),证据就近同放。**只有 durable 证据进这里;ephemeral 的 WO/run 产物进 scratchpad**。
- **写法**(权威见 `decisions/0000-template.md`):
  - **frontmatter**:`id/title/date/status(proposed|accepted|superseded|deprecated)/supersedes/superseded_by/tags`。验证脚本读结构化字段,不啃散文。
  - **意图**:给人的散文 2–3 句(为什么/价值/边界),**禁 §引用、禁代码**。这是"生来可读"的车道。
  - **决策(契约)**:可测的 WHAT——数据形状 / 不变量 / 硬上限 / **明确不做** / 能证伪的判据。**不写 file:line / 算法步骤**(那是 HOW,归 WO)。
  - **备选与失效模式**:被否的路 + 各自"若选它会怎么错"(最防重踩的一节)。
  - **后果**。
  - **引用**:代码 / 文档写 `ADR-NNNN`;断链检查 = 查 `decisions/NNNN-*` 在不在(比旧的解析子章节简单得多)。
- **谁起草契约**:纯设计推理的 ADR,bs 起草意图+契约;**代码实据型粘性决策**,bs 只写意图,「决策(契约)」段由读过代码的 planner 起草回填(证据来源决定起草人,不改归属)。
- **何时才写**:决策**稳定到粘性**(不可逆 / 会被反复引用)才写 ADR;早期高频探索留在 scratchpad / architecture 草稿,别每个中途念头都冻(否则 supersede 链爆炸)。finishing 只冻**已稳定**的,不是每次结晶。
- **证据谁搬**:实验支撑某决策时,**由 ADR 起草人在著作时顺手把 scratchpad 的 json/csv/notebook 提升进 `decisions/NNNN-slug/`**——是著作动作的一部分,不是 worker/GC 的活(否则 ADR 文件夹永远空)。
- **可发现性(ADR 多了再加)**:早期靠 frontmatter tags + `git grep` 足够。**decisions/ 攒到找不动时**,再让 `check_docs.py` 从 frontmatter 自动生成 `decisions/index.md`(零维护);不提前建、不搞 taxonomy(§0③)。

### 1.4 TODO.md(扁平清单,做完即删)
- 只放**下一步真要做的事**,完成即删行(天然排空)。
- **设计债不进这里**:坏 WO / 发现的坏设计 → **开新 / 改 ADR**(显性化走设计审),不倒进 TODO 暗堆(这是旧 BACKLOG 臃肿的根)。
- **无仪表盘头**:HEAD 归 git、测试基线归"跑一次得真数"、"现在在做"就是清单顶部——都别手抄进来(双写必漂)。
- **TODO 默认、可长期用**:solo / 开发期自己发现问题自己改,近水楼台。只有当**项目进入成熟期 + 开源 + 真有他人提 issue**时,才迁移到 GitHub issues(取决于有没有多方 issue 流量;与「工作流本身开源」无关)。

### 1.5 scratchpad/(ephemeral,gitignored)
- session 分目录:`PL-<uuid>` / `BS-<uuid>`(完整 session UUID);派单产物 `runs/<run-id>`(时间戳+PID,并发唯一)。
- 装:WO、worker report、验收单、run.log、transcript、临时脚本。
- **GC**:cleaning 例程按保留策略删有 `.done` 且超期的 run(几行 find,不单独成脚本),随后清 session 目录。

### 1.6 STATE —— 已溶解(不再是文档)
旧五段各归其位:已冻结契约→ADR+architecture;下一批候选/当前活跃→TODO;悬而未决→TODO 或 proposed 的 ADR;已知地雷→**代码本地注释** + AGENTS 项目铁律。冷启动直接读 AGENTS(地图)+architecture(现状)+TODO(下一步)+相关 ADR,不需要单独仪表盘。连带:`check_docs.py` 的 STATE 规则一并删除。

### 1.7 知识去哪(替代 LESSONS/BACKLOG/docs 的路由)
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

**Claude(贵,出思考)**:`bs` 著作 ADR · `planner` 切 WO / 拍板 · `finishing` 冻结收尾。
**便宜 harness**:`worker` 执行 · `verifier` 异构验收 · `cleaning`(Cursor)维护文档。
决策**只 Claude 层著作**,worker/cleaning 永不著作决策。

### 2.1 一轮完整闭环
```
bs        发散(≥3 真不同方案,各 steelman+失效模式) → 异构红队选项册
          → 收敛、著作 ADR:纯设计决策写意图+契约(冻结前红队+人审意图层→accepted)
              代码实据型决策只写意图(proposed),契约留 planner
   ↓ 交棒
planner   读 ADR → 读实况(grep/read 核实 file:line)
          →(代码实据型:起草契约回填 → 红队 → accepted)→ 设计 HOW
          → 切 WO-<ADR>-<序号>(顶部意图行「本单服务 → ADR-NNNN」)→ 用户放行
          → 派便宜 worker + 异构验收(run_worker.sh) → 读验收单拍板 + 按需看高危 diff
          → GO → 放行 commit;NO-GO → 打回重派;坏 WO/坏设计 → 报告用户 → 开新/改 ADR
finishing 会话中已稳定的决策 → 就地冻结成 ADR + 出总结/交棒 + 转写 session
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
- **红队 ADR**(闸门2):冻结前交异构只读模型审收敛后的 ADR(契约自相矛盾/无法证伪/过度工程/契约 vs 代码实况)。
- **WO 意图行**(闸门3):每张 WO 顶部 `本单服务 → ADR-NNNN`,缺则派单 hook deny;用户扫这行拦跑偏。
- **异构验收**(闸门4):worker 与 verifier 跨厂异构,verifier 审 diff-vs-WO **和** WO-vs-ADR(判据本身够不够)。

### 2.4 每个提示词的设计规范(实施照此从零写)
- **bs**:开工读 AGENTS§0 + memory + 相关 ADR/architecture。发散纪律(≥3 真不同、steelman、显式假设、失效模式、决策挂数据需求)。产出 `options.md` → 红队 → **著作 ADR 意图**(纯设计决策连契约一起写;**代码实据型决策只写意图,契约留 planner 读码起草**)→ 红队 → 交棒 planner。严禁写实施细节(那是 WO 的 HOW)。不写代码、不出工单。
- **planner**:开工读 AGENTS + 要动的 ADR + 相关代码实况。**读 ADR + 读实况 → 自己设计 HOW**(HOW 完整性是 planner 的活)。三档分诊。WO 瘦、指针不复述、判据尽量写成能跑绿的测试、顶部意图行。两阶段派单(执行 + 异构独立验收),**读验收单拍板**:看判定/判据逐条/判据外边界/WO判据体检/越界、自跑 pytest 复核;**碰契约 / 热路径的 WO,planner 必读那段 diff**(不是绝不读——只是不逐行通读无风险改动);验收单证据须机器可复核(引真行、跑真测试);**验收绑定不可变 revision**(commit/stash hash,防验收后代码又变)。坏 WO → 报告用户 → 开新/改 ADR(不绕过、不暗堆)。派 worker vs 自己写:有可验证判据边界清的派 worker;要设计/上下文重/无测试判据的(ADR、提示词)自己写。
- **finishing**:顺序 ① 冻结(会话中**已稳定**的决策就地著作成 ADR,整块意图+契约;未稳定的别冻)→ ③ 出总结/交棒(≤10 行,下 session 冷启最小上下文)→ ② 转写 session(最后跑,才含交棒)。文档维护全交 cleaning。
- **cleaning**(Cursor 侧,fresh agent):读本 session transcript + 读仓交叉验证。维护 architecture.md / TODO / scratch / 死链。两条删除路径:机械易失项直接做;tracked 文件删除 / 搬迁走**候选清单→人 IDE 确认**。landmine 分层保护(`NO-GO`/`别翻案`/`已验证净负` 一律保留)。不著作决策、不改 ADR 正文。
- **hooks**:`doc_guard`(改 *.md 后跑结构守护,非阻塞注入警告)按新结构改——认 ADR frontmatter / architecture,删 STATE 规则;`check_wo_intent`(派单前认 `本单服务 → ADR-NNNN` 意图行,缺则 deny;不确定时放行**但打点自曝**——不静默兜底,§0.2)。
- **scripts(新设计下 5 → 3,ADR 让检查大幅变简单)**:① `run_worker.sh`(两阶段派单,模型/命令读 `workflow.env`,回 planner 只带验收单+token、不回 diff);② `check_docs.py`(**合并旧 check_deadlinks**:ADR frontmatter/命名校验 + `ADR-NNNN` 存在性检查;旧的 STATE/docs 规则、PLAN§子章节解析全删,只剩几十行);③ `transcribe_session.py`(session→压缩 transcript 喂 cleaning;压工具骨架、保 NL、软 token 顶)。`scratch_gc.sh` 的保留策略 GC **折进 cleaning 例程**,不单独成脚本。

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

## 4. 旧 → 新映射(简略)

| 旧 | 新 |
|---|---|
| PLAN(一名扛三生命周期) | **ADR**(只冻结决策)+ architecture(现状)+ WO(HOW) |
| PLAN §0/§3 著作 | 著作 **ADR** |
| WO-A-B(planner 作用域编号) | **WO-\<ADR\>-\<序号\>**(跟决策走,全局唯一自解释) |
| LESSONS(中央追加池) | 代码本地 / ADR / AGENTS 铁律 |
| BACKLOG(设计债暗堆) | ADR(设计债)/ TODO(真下一步) |
| docs/(事后蒸馏) | ADR(生来可读 + 证据)/ architecture |
| STATE(仪表盘) | 溶解(git + ADR + architecture + TODO) |
| §X.0 修正块 | ADR 文件级 supersede |

---

## 5. 实施顺序 & 远期

- **顺序**:先在 hubpage **就地**按本蓝图从零重建工作流 + 完成文档系统迁移 → **真跑一轮验证** → 再抽取中立机制进**独立模板仓**(别对动靶抽取)。
- **实施清单(给施工 session,按序)**:① 改 `.gitignore` track 机制 + 出 `workflow.env.example`;② 照 §2.4 从零重写 4 skill(bs/planner/finishing/cleaning)——**不改旧文件**;③ 重写 2 hook(doc_guard 认 ADR/architecture、check_wo_intent 认 ADR-NNNN 且不静默);④ 合并 check_deadlinks→check_docs、scratch_gc 折进 cleaning;⑤ `workflow.env` 强审改成**非 cursor 厂**(≠worker,§2.5);⑥ architecture.md 瘦身(§11/13/16/17→TODO、§15→example、复核已种的 ADR-0001)——**破坏性,先出切分方案再动**;⑦ 建 `TODO.md`;⑧ 真跑一轮闭环验证。
- **机制必须 track**:现 `.claude/`、`scripts/workflow/`、`workflow.env` 全 gitignored = 新机器 clone 后零钩子零脚本。实施时改 `.gitignore`:**track 机制**(`.claude/skills`、`.claude/hooks`、`scripts/workflow` 的 `*.py`/`*.sh`)+ 只 gitignore **每机的值**(`workflow.env`,另 track 一份 `workflow.env.example`)。
- **新项目 bootstrap(还没 ADR 时)**:先建 AGENTS.md(§0 + 工具约定 + 文档地图)→ 空 `decisions/` + `TODO.md` → 第一个架构选择直接走 bs 著作 ADR-0001。冷启动清单里 architecture/TODO 可暂缺,读到什么算什么。
- **远期(抽取模板仓之后)**:开源上 GitHub;全平台兼容(编排偏 Python,bash hook 是 Windows 坎);中英兼容(机制层单一 canonical 语言,别手写两份)。

---

## 6. 红队结论(已跑两道异构:deepseek + luna)

两道红队已跑,地基级问题已并入上文修订:**海拔律改按粘性(§0 律3)、architecture 从属 ADR(§1.2)、planner 碰契约必读 diff(§2.4)、著作不追加加强制写权限(§2.5)、ADR 时机 + 证据搬运 + 自动索引(§1.3)、经济学破财点写明(§3)、机制 track + bootstrap(§5)**。低概率项只作文档约束(§2.6),不建机制——避免把工作流自己搞成过度工程(§0 脊椎)。

**定稿判据(终止红队循环)**:两道异构红队 + 用户签字 = v1 冻结;此后对工作流本身的改动,当作"关于工作流的 ADR"走,不再无限迭代蓝图。
