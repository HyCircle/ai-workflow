# workflow-kit 修复执行记录（v4 · 已实施）

> **历史归档**:下文含抽取前的双侧同步与旧布局细节;**非现行 install 规范**。现行见 `docs/dot-workflow-layout.md`。

> 两侧同步完成：`workflow-kit/`（SOT）与消费项目（eval/ 前缀投影）逐文件镜像，差异仅剩 eval/ 布局的结构性适配（EVAL_ROOT、DECISIONS 路径）。所有脚本 `bash -n` 通过、`check_docs.py` AST 通过、`test_derive.sh` 双侧 18/18 全绿。

## P0 — derive 解析加固（真 bug 修复）

- `derive_status.sh`：读行先去行尾空白/CR；marker 改 contains 匹配（NONE 先判，防 `<<<FINDINGS-NONE` 被 opener 前缀吞）。「紧贴文本的 FINDING 块」现在正常计入；glued NONE / CRLF / 行尾空格均正确解析。
- `tests/test_derive.sh`：补 4 例回归（glued opener、glued NONE、CRLF、行尾空白）。

## P0 — 删双验收容忍层（语义：任一验收员无有效产出 → 整轮 infra_failed）

- `derive_status.sh`：删 DEAD_FILES 分支（死代码——call_agent 失败时永远写非空内容，空文件判定触发不到）；验收单缺失/空/不可解析 → 自曝 + infra_failed。
- `run_worker.sh`：删 REVIEW_FAIL_COUNT→CLI_FAILED 重复判定，验收失败判定收敛到 derive 一处（退出码/缺失提示保留在回显）。
- 循环：planner 见 infra_failed → 回显里已有存活验收员的单子 → `REVIEW_ONLY=1` 重派失败的那员（工作树冻结）。
- `tests/test_derive.sh`：test 12 改为新语义（双验收一死 → 整轮 infra_failed）。

## P1 — 越界校验改用 git 实源

- `run_worker.sh`：`git status --porcelain` 字符串截取 → `git diff --name-only HEAD` + `git ls-files --others --exclude-standard`（rename/copy 条目不再解析错）。

## P1 — dispositions.md 机制删除

- 引用点全部改写：`workflow.md`（§2.1 闭环行、§2.5 D3、§2.6 失败恢复）、`planner/SKILL.md`（第 6 步、跳过亲验、L49 scratch 产物清单、术语统一 disposition→裁决）、`run_worker.sh` 注释（「durable 审计痕迹在 git(commit message)」）。
- 驳回/跳过亲验的理由 → 随 commit message 落库。

## P1 — handoff.md 机制删除

- `finishing/SKILL.md`：总结/交棒只作为助手回复进会话（删「写入 handoff.md」选项），最后转写；transcript 即交棒的文档（用户对 /finishing 的要求作为 user 消息一并转写）。print 末尾固定「下 session 开场提示词」段，转写后位于 transcript 尾部。
- `workflow.md` §2.1 finishing 行同步。

## P1 — worker 报告收窄（四段 → 三段）

- `worker-preamble.md`：删 ③pytest 结果段（全量 pytest 由脚本亲产）；①落地方式 ②偏离 ③矛盾报告保留；「报告前自测绿」纪律保留。

## P1 — pytest 输出摘要化

- `run_worker.sh` 回显：`pytest: 全绿` 或 `pytest: 红(失败列表如下…)` + `grep '^FAILED' | head -20`；全文留在 run.log，`PYTEST_RC` 照常进 derive。

## P2 — 冗余清理

- `run_worker.sh`：删重复 STATUS 行（STATUS_LINE 已含在 DERIVE_OUT 内）；模式回显的 WO_REVIEW 分支与默认分支合并。
- 打码：保留两处（call_agent 流式打码覆盖 bs/planner 直呼 redteam 日志；run_worker 末次打码覆盖回显段验收单/机器输出全文），pattern 统一（run_worker 补 `gho_`）。

## P2 — 装回闸门 / 治理投影

- 消费项目 `.git/hooks/pre-commit` 已安装（适配 eval/ 路径，`check_docs --staged`）。
- kit `README.md` 增「既有项目的 eval/ 前缀布局（手动同步）」一节：方向单一 kit → 项目，差异只允许路径前缀。

## P3 — 非 git 静默兜底 → fail-loud

- `check_docs.py` `_repo_root`：非 git 直接 `raise SystemExit`（删 parents 兜底，kit/消费侧该函数现完全一致）。
- `call_agent.sh` ROOT：`git rev-parse` 失败即报错退出（删 `|| pwd`）。

## 纪律⑥ 刻疤清理

- `lib_timeout.sh`：删「不再手搓 setsid/pgid 看门狗——那套有 pgid 读取竞态、且一旦失效上层就永久楔死」。
- `call_agent.sh`：header「绝不静默产出 thinking 碎片当报告」改正面（thinking/assistant 增量一律不当报告）；stdin 注释「万一审批提示不会读终端阻塞」→「审批提示不读终端,不会阻塞」。
- `agent-discipline.md`：纪律④ 删「(这是 vibe coding 的头号翻车点)」。

## 保持不动（确认过，不属无效机制）

- codex/cursor 双后端（你要的）；install.sh 的旧 `.claude/hooks/` 升级清理（升级路径卫生）；`.git/info/exclude` 的 `/.cursor/` `/.agents/` 忽略项；WO 审/双验收并行/意图闸门/check_docs/四态派生等有真实消费者的机制。
