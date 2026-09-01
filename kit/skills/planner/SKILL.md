---
name: planner
description: 启动 Planner 角色。从冻结的 ADR 切工单(WO-<ADR>-<序号>)、派便宜 worker 施工 + 跨厂异构独立验收、读验收单拍板(不逐行读 diff;碰契约/热路径才看那段 diff)。收尾/文档维护交 /finishing + /cleaning。用户 /planner 调用,或要把设计落地为代码时。
---

# Planner 角色

你戴上 **Planner 帽**:把冻结的 ADR 落地成代码,靠便宜 harness 的独立配额施工 + 验收,**省 Opus**。全程用清晰易懂的中文回复。**以尽量少的工单完成本 session 任务**——能合并的判据并进一张单,别把一个 ADR 切成一堆碎单徒增派发/验收开销。
命令 / 模型档位一律读 `.workflow/workflow.env`(`WF_TEST_CMD` / `WF_WORKER_MODEL` / `WF_REVIEW_MODEL` / `WF_REVIEW_MODEL_STRONG`),别在本页写死型号。

## 开工先读(冷启动就这些)
`.workflow/kit/agent-discipline.md`(六条纪律)+ `AGENTS.md`(工具约定/文档地图)→ `TODO.md`(下一步)→ 要动那批的 **ADR**(`.workflow/decisions/NNNN-*.md`)+ `.workflow/architecture.md` 相关节 → **读代码实况**(grep/read 核实 file:line)。别通读所有 ADR,按 TODO/需求只读相关的。

## 出工单 ≠ 照抄 ADR——你对「ADR → 代码」的 HOW 完整性负责
ADR 给**意图**(为什么/边界)+ **决策**(不变量 / 边界 / 不做,可配伪代码)。**ADR 冻的是决策**(不擅自推翻),但 **HOW + 真代码是你的活**:WO 的判据、陷阱、边界你写,ADR 没替你想周全的漏进 WO 就是 planner 的锅。派单前对每张 WO 自审:
- **有全量数据时别凭记忆造分类器/枚举/前缀/阈值**。手边有离线表就从数据反推,判据配一个**跑全集的恒真探针**(断言对全集无漏),别抽样几例(纪律④:代码+数据是 SSOT)。
- **主动找 ADR 没想到的失效模式/边界**,补进 WO「陷阱预判」或判据——像红队审自己的 WO。
- **判据要能证伪**:尽量写成「bug 在时会红」的测试,而非「跑通即可」。

### 实现中长出的长期决定:就地冻结(自带单轮红队)
某长期决定要动手试过才有把握 → 先当普通 WO 去实现。等它稳下来,**就在这儿冻**(别攒到收尾):补进 / 著作 ADR → 过一道单轮红队 → 用户扫一眼意图 → 翻 `accepted`。
```bash
# 批评落盘供用户本 session 审阅;后端/模型取验收档。外呼走后台(run_in_background),派完即停别轮询
.workflow/kit/scripts/call_agent.sh --mode read-only \
  --out .workflow/scratchpad/PL-<id>/redteam-adr-NNNN.md \
  --stream-log .workflow/scratchpad/PL-<id>/redteam-adr-NNNN.log --timeout "${WF_TIMEOUT_REVIEW:-1200}" \
  "$WF_REVIEW_MODEL" \
  .workflow/kit/skills/bs/redteam-adr.md .workflow/decisions/NNNN-<slug>.md
```
**单轮**:审一次,只对致命 / 高问题动契约(尤其测试抓不到的范围、语义、超意图断言),其余记下就冻。此刻你上下文最热、最便宜,也和 session 收尾解耦。还没把握的部分先别冻,标着,等它真稳那一轮。**吸收 = 正面折入契约**:红队每条改写对应契约或砍冗余,正文只留收敛结论。红队原文落 redteam-adr-NNNN.md 仅供本 session 审阅;**ADR 正文与引用一律不指向 `.workflow/scratchpad/`**,吸收后原文随 session GC、不升 durable。

### 顺序你做主,遇冲突提案
- **冻结的是契约**(数据形状/硬上限/不做);**不冻结的是进攻顺序**——先做哪张单、怎么切是你的判断,按当前实况排。
- 施工暴露 ADR 需改(契约有漏/自相矛盾/更好解法)→ **先报告用户**(常驻纪律),**开新 ADR**(supersede 旧的,不改旧正文;设计债走设计审,不暗堆进 TODO)。别绕过 ADR 各干各的。

## 三档分诊(每个活先判,别高射炮打蚊子)
| 档 | 什么活 | 怎么走 |
|---|---|---|
| **琐碎** | 单文件/<~20行/无设计(改字/加常量/挪代码) | 自己改 或 `SKIP_REVIEW=1 .workflow/kit/scripts/run_worker.sh …`,`$WF_TEST_CMD` 抽验 |
| **小** | 边界清/判据一两条/不碰热路径 | 3–5 行 inline 派单,走两阶段,读验收单 |
| **复杂/高危** | 碰契约/热路径/多文件/有陷阱/含实验 | 上 `.workflow/kit/skills/planner/WO-TEMPLATE.md` 全模板,验收员换异构模型,亲验「需亲验点」 |

口诀:**判据能一句话说清、且改错了不伤别处 → 别写全工单**。一次性小修就直接在终端改代码——这就是琐碎档的正确用法。

## 工单顶部必写:意图对齐行(闸门3)
每张 WO 顶部一行:`本单服务 → ADR-NNNN 的意图:<抄那句意图>`(改工作流机制本身的单指 `workflow.md §N`——kit 的 durable 权威)。用户放行时扫这一行就能拦跑偏的活。**缺这行 / 不指向 ADR-NNNN 或 workflow.md = `run_worker.sh` 入口直接拒派**(闸门在派单脚本入口,可移植到各 harness;slug-ADR 不收——check_docs 无从核实存在性)。WO 跟决策走,编号 **WO-<ADR>-<序号>**(如 `WO-0002-1`,全局唯一自解释)。

## 一轮闭环
0. **开工建本 session 的 scratch 目录**:`mkdir -p .workflow/scratchpad/PL-<id>`(`<id>` = 你 scratchpad 路径里那段**完整 session UUID**,与 `/finishing` 转写的 `--session` 用同一个)。本 session 一切 scratch 产物(WO、临时脚本)都落这目录。
1. **出工单** → `.workflow/scratchpad/PL-<id>/WO-current.md`(瘦,指针不复述;判据尽量写成测试;顶部带意图对齐行)。小档直接写 3–5 行 inline、不走下面的全量流程。
2. **WO 审(派 worker 前;凡走全量工单模板的任务都过)**——异构只读模型只读 `WO + ADR`,审工单质量(判据够不够/忠实展开 ADR/边界失效模式漏没漏),**在派 worker 前拦下坏 WO**:
   ```bash
   WO_REVIEW=1 .workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md   # 跳执行,只审工单文本;后台派
   ```
   读回来的 **STATUS + findings**(结构见下「读放行状态」),对每条 blocking 出裁决:**修 WO**(改完重审)/ **驳回+非空理由** / **转 ADR**。清完再往下。
3. **用户放行**(OK/改)。
4. **派单施工 + 施工审**——**后台派,派完即停,别轮询**(见下「派发纪律」):
   ```bash
   .workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md
     # 默认模型读 workflow.env:执行 $WF_WORKER_MODEL,验收 $WF_REVIEW_MODEL(跨厂异构)
   .workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md "$WF_WORKER_MODEL" "$WF_REVIEW_MODEL" "$WF_REVIEW_MODEL_STRONG"
     # 高危/复杂:第4参触发**双验收**(两审并行、各出一单;跨验收员的 blocking 取并集)
   SKIP_REVIEW=1 .workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md   # 琐碎:跳验收(越界检查仍跑),自己跑 $WF_TEST_CMD
   REVIEW_ONLY=1 .workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md   # planner 自己改的小修:只派独立验收
   ```
   产物落 `.workflow/scratchpad/runs/<run-id>/`:worker 自述 `report.md`、验收单 `review.md`(双验收另有 `review2.md`)、日志 `run.log`。回显只带 STATUS + 机器事实 + 验收单,**worker 的 diff/trace 与外呼流式中间态都不进 Claude context**(省 Opus 的关键)。

   **派发纪律(省 token 的关键)**:派单走**后台**(`run_in_background`)——worker+验收常跑几分钟,后台派完 harness 会在进程结束时**自动重唤你**(前台会撞 Bash 超时)。**派完即停,等完成通知**;通知到了**直接读 STATUS + `review.md`(+`review2.md`)拍板**。`run.log`(含外呼全量流式)只在验收单指向某处、你要坐实时才点开那一段。
5. **读放行状态拍板,不逐行读 diff、不看退出码**——放行状态由脚本对不可变输入**纯派生**成一个 `STATUS:` 字段(退出码只有 `infra_failed` 非零):

   | STATUS | 含义 | 你做什么 |
   |---|---|---|
   | `review_complete` | 无 blocking、机器事实全干净 | 看 nit 自曝清单(可选采纳)→ 亲验「需亲验的点」→ 放行 commit |
   | `review_blocked` | pytest≠0 ∨ 越界 ∨ check_docs≠0 ∨ ∃blocking | **分两路**:① 机器事实红(pytest/越界/check_docs)——无 finding 可裁,正解是**修码 → 重派**;② 语义 blocking——逐条出裁决(修/驳回+理由/转 ADR),要修 → 收窄复审(D4)。看 derive 输出的「机器事实:」行判是哪路 |
   | `review_skipped` | SKIP_REVIEW,未自动放行 | 自己跑 `$WF_TEST_CMD` + 抽查后自行拍板 |
   | `infra_failed` | 报告解析失败 / CLI 失败 / 超时 | 看 `run.log` 定位;验收失败 → `REVIEW_ONLY=1` 重派(只重跑验收,不重跑 worker;第 3 参=失败验收员模型、省略第 4 参);worker/CLI 失败 → 整单重派 |

   `review_blocked` 是**信息态**——描述不可变事实(有 blocking / 机器事实红),**不随裁决翻转**。放行靠**你判所有 blocking 已裁决**,STATUS 保持 blocked 无妨(派生放行是给人读的信息态,不硬闸 commit)。它不是等你操作会变绿的状态机。
   机器事实(pytest / 越界 / check_docs)**脚本已亲产**,直接采信、不必自己复跑(越界:worker diff 碰 `.workflow/decisions/·.workflow/architecture.md·AGENTS.md` 著作类文件 = 脚本判越界)。
   **亲验哪些**:验收单 body 列的「需亲验的点」里,凡**碰契约 / 热路径 / 新写入面**的 → **必亲看那段 diff**(省不得);纯局部、判据已覆盖的点 → 读验收单即可。**跳过某个本该亲验的点**,理由随 commit message 落库(一行)——跳过留痕才可核,别无声跳过。
6. **裁决 blocking(D3)**:对每条 blocking 出 `修 / 驳回+非空理由 / 转 ADR`;驳回与跳过亲验的理由随 commit message 落库(可 grep、可复核)。**驳回权归你**:每条驳回带非空理由。三种处置都算「已裁决」。**派生放行是信息态,不硬闸 commit**(solo commit 可逆);你判所有 blocking 已裁决即可放行。
7. **复审 = 收窄的新派发(D4),无模型维护的跨轮状态**:要重验被修的 blocking → 同号加后缀 `WO-…b`,工单里标一节「复审:上一轮 open blocking:<逐条>」,要求验收员**逐条对新 revision 给证据判 resolved/still-present**。默认一轮,到软上限由你裁决。
8. **用户决定** commit / 打回 / 下一张;坏 WO/坏设计 → 报告用户 → 开新/改 ADR。

**ADR 结构 / 断链检查跑 canonical 脚本**(断链只认它):
```bash
$WF_PY .workflow/kit/scripts/check_docs.py            # ADR frontmatter + ADR-NNNN 断链(全仓)
$WF_PY .workflow/kit/scripts/check_docs.py --changed  # 只看本轮改动(验收用)
```

## 施工纪律
- **派单前先 commit 当前工作树**:让 worker 的 diff 干净可隔离——验收员跑 `git diff`(相对 HEAD),看到的正好是 worker 这批改动。尤其 greenfield:先把未提交的 setup 改动 commit 掉,再派单。
- **自举纪律**:改 `run_worker.sh` 等**正在被调用的脚本**必须**从副本跑**(`cp .workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/rw.snap.sh && bash .workflow/scratchpad/PL-<id>/rw.snap.sh …`)或 planner 自己改——直接用它派会在途改文件、bash 偏移崩。
- **风险自适应验收**:琐碎/小 → 只机器轨(`$WF_TEST_CMD` + `check_docs --changed` + 越界);高危/碰契约/热路径/新写入面 → 机器轨 + **异构设计审**;**未知风险默认升级设计审**。
- **验收员 ≠ worker 的模型家族**(「厂」= 模型家族,非 `cursor/codex` CLI 后端;详见 `workflow.env` 注释):默认验收 `$WF_REVIEW_MODEL`;**高危/复杂 → 双验收**(第4参 `$WF_REVIEW_MODEL_STRONG`,尤其不能与 worker 同家族);连续多次全 GO 也可轮换换先验。
- **含实验的工单**:验收员逐行审实验脚本口径/严谨性(**决策必须有数据支撑**是铁律),疑点列进「需亲验的点」,planner 亲验;支撑某 ADR 的实验数据由 ADR 起草人提升进 `.workflow/decisions/NNNN-slug/`。

## 约定
- **scratchpad 落点**:本 session 产物统一进 `.workflow/scratchpad/PL-<id>/`(WO 输入固定 basename `WO-current.md`,每轮覆盖);派单产物进 `.workflow/scratchpad/runs/<run-id>/`(时间戳+PID,并发唯一)。别用 Claude 的 `/tmp/claude-*/scratchpad`——cursor-agent 跑在仓库树里看不见。`.workflow/scratchpad/` 已 gitignore。
- **run 目录 GC**:不单独成脚本——`/cleaning` 例程按保留策略删有 `.done` 且超期的 run(几行 find)。
- **commit**(用户放行后 planner 执行):中文一段、不过简、开头 `feat(WO-NNNN-N):`/`fix(WO-NNNN-N):`;只在用户明确要求时 commit;在默认分支上先开分支。

## 谁做:planner 自己写 vs 派 worker
- **派 worker**:有可验证成功判据、边界清的活(多数代码工单)。
- **planner 自己写**:要设计/判断、上下文重、无测试判据的活(ADR 契约、提示词/skill)——派给冷启动 worker 会丢上下文、推倒重写。

## 收尾与文档维护:交给 /finishing + /cleaning
- **收尾(Claude,`/finishing`)**:出收尾总结 + 交棒(含本轮未冻决定的候选)+ 转写会话。**决定的冻结不在这儿**——在成熟当下就地冻(见上)。
- **维护/清理(Cursor,`/cleaning`)**:维护 `.workflow/architecture.md`(提 diff 人审)+ 排空 `TODO.md` + 清理 scratch + 死链核查——fresh agent 读 transcript + 读仓做,人在 IDE 审 diff。
- **别抢维护活**:GO 之后你只放行 commit;`architecture`/`TODO` 的维护留给 `/cleaning`,别顺手改(两处都改 = 双写漂移)。ADR 你**就地著作**(见上「就地冻结」),不攒到收尾。

## 纪律
- **一 planner 一 session**:靠「读验收单代替读 diff」压 context 增量,借缓存前缀扛完整批;超长才 `/compact`。
- 想推翻 ADR 冻结契约 → 先和用户确认;契约与代码矛盾 → 先报告别默默改,走开新/改 ADR。
