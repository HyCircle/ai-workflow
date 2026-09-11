# failure-modes —— 机制已知失效模式(留作纪律)

> **这是什么**:本机制历次翻车的蒸馏登记册。每条 = 症状 → 根因 → 现强制的规则(+ 在哪强制)。
> 改机制前先扫一遍:别把已经填过的坑重新踩一遍。
>
> **面向谁**:kit 维护者(改本仓的人)。**不投影进消费项目** —— 消费者面向的常驻宪法是
> `discipline.md`(六条纪律),那份一字不带这里的维护教训。
>
> **和纪律⑥(刻疤清理)的关系**:纪律⑥ 禁的是**代码/文档里的疤痕注释**(「不再手搓 X——那套有 Y 竞态」之类)。
> 一份专门的复盘登记册不是疤痕注释,是前瞻规则,故合规。写这里、别写进代码。
>
> **原始证据**:`docs/history/2026-08-diagnosis-v4.md`(P0–P3 修复执行记录)、
> `docs/history/extraction-plan.md`。本文是它们的蒸馏;要看逐文件明细回去翻原件。

---

## FM-1 · derive 状态解析漏掉「紧贴/脏行」的 FINDING 块 —— 真 bug

- **症状**:worker/验收单里 marker 紧贴文本(`<<<FINDINGS-NONE` 前缀被 opener 吞)、CRLF 行尾、行尾空格时,
  findings 块漏解析,四态派生出错。
- **根因**:逐行**精确相等**匹配 marker + marker 判定顺序错(先判 opener,NONE 被当 opener 前缀)。
- **规则**:读行**先 strip CR + 行尾空白**;marker 用 **contains** 匹配;**NONE 先判**再判 opener。
- **在哪强制**:`kit/scripts/tests/test_derive.sh` 覆盖 glued opener、glued NONE、CRLF 和行尾空白回归；测试集合保持与 derive 契约同步。

## FM-2 · 双验收「容忍层」掩盖 infra 失败

- **症状**:一个验收员外呼死掉/产出空单时,旧代码用容忍分支糊过去,整轮被误判为有效。
- **根因**:失败判定散在多处(derive 的 DEAD_FILES 分支 + run_worker 的 REVIEW_FAIL_COUNT→CLI_FAILED),
  且 DEAD_FILES 是死代码(call_agent 失败永远写非空内容,空文件判定触发不到)。
- **规则**:**任一验收员无有效产出 = 整轮 `infra_failed`**;失败判定**收敛到 derive 一处**;
  planner 见 infra_failed → 用已存活验收员的单子 → `REVIEW_ONLY=1` 重派失败那员(工作树冻结)。
- **在哪强制**:`test_derive.sh` test 12(双验收一死→整轮 infra_failed);删 DEAD_FILES / REVIEW_FAIL_COUNT 分支。

## FM-3 · 越界校验从 `git status --porcelain` 字符串截取 —— 解析错 rename/copy

- **症状**:worker 改动含 rename/copy 时,porcelain 的 `R  a -> b` 条目被字符串截取解析错,越界判定失真。
- **规则**:改动清单走 git **实源**:`git diff --name-only HEAD` + `git ls-files --others --exclude-standard`。
- **在哪强制**:`run_worker.sh` 越界校验段。

## FM-4 · 独立台账文件(dispositions.md / handoff.md)是多余机制

- **症状**:为「裁决记录」「交棒」各建一个 md 台账,和 git/transcript 双重记账、易漂移。
- **规则**:**裁决/驳回/跳过亲验的理由随 commit message 落库**;**交棒 = finishing 的 transcript 本身**
  (助手回复进会话 → 转写成 scratch transcript,尾部固定「下 session 开场提示词」段)。不建独立台账。
- **在哪强制**:`docs/design.md` 的文档职责与复审说明、`planner/SKILL.md`、`finishing/SKILL.md`。

## FM-5 · worker 自述与机器检查混为一谈

- **症状**:worker 报告里带自测 pytest 或文档检查结果,与脚本亲产的结果重复、且可被 worker 粉饰。
- **规则**:施工审路径由 `run_worker.sh` 亲产机器事实；worker 报告给出结果与证据、重要偏离、矛盾与待定。报告回传给 planner 作为待核实证据。`SKIP_REVIEW=1` 明确跳过 pytest 与 `check_docs`，回显说明未执行项，不能把探索执行标成验收通过。自测仍有价值，其适用范围与脚本检查分开陈述。
- **在哪强制**:`planner/worker-preamble.md`、`run_worker.sh` 回显与状态派生。

## FM-6 · pytest 全文灌进派单回显 —— 淹没信号

- **规则**:回显只给摘要：成功状态，或最多 20 行 `FAILED`；没有该格式时显示失败退出码，全文留 `run.log`，`PYTEST_RC` 照常进 derive。
- **补充触发**:配置的测试命令失败但不输出 `FAILED` 时，原来的 grep 管道在 `set -e` 下中断回显。摘要提取允许零匹配，仍完整报告失败并收束 run。
- **在哪强制**:`run_worker.sh` 回显段，`test_run_worker.sh` 的真实失败命令用例。

## FM-7 · 非 git 环境静默兜底 —— 定位漂到错仓

- **症状**:`check_docs._repo_root` / `call_agent` 的 ROOT 在非 git 目录下静默回退(parents 兜底 / `|| pwd`),
  仓根定位悄悄漂走,错误延后爆发。
- **规则**:**非 git 直接 fail-loud**(`raise SystemExit` / 报错退出),不静默兜底。
- **补充约束**:仓根**必须走 git toplevel + layout 标记**,**不能退回 `__file__` 相对定位** ——
  symlink 共读(`--link`)时 `__file__` 解析进 kit 而非消费仓。
- **在哪强制**:`check_docs.py._repo_root`、`call_agent.sh` ROOT。

## FM-8 · 代码/文档里的「疤痕叙述」(纪律⑥)

- **症状**:注释写成「不再手搓 setsid/pgid 看门狗——那套有 pgid 读取竞态」这类**记录旧伤**的负面叙述;
  或「(这是 vibe coding 的头号翻车点)」这类情绪化旁注。
- **规则**:删疤痕注释,改**正面陈述当前契约**(「thinking/assistant 增量一律不当报告」而非「绝不静默产出碎片当报告」)。
  历史教训写进**本文件**,不写进代码。
- **在哪强制**:`lib_timeout.sh` / `call_agent.sh` / `discipline.md` 已清;新代码 review 时照此把关。

## FM-9 · finding 用 sentinel 块,不用 yaml-fence / 嵌套 JSON

- **规则**:每条 `<<<FINDING` … `FINDING>>>`,字段各占一行,值可含冒号与引号、无嵌套转义。实测 sentinel/jsonl 干净率 100%,yaml-fence 50%(整块 ScannerError);sentinel 再以无转义负担和人读性优于 jsonl。语义仍是 `severity` / `where` / `claim` / `failure_scenario`。
- **在哪强制**:`review-preamble.md` / `wo-review-preamble.md` 的输出格式;`derive_status.sh` 解析。

---

## 保留的有效能力

- codex/cursor **双后端**(有意的跨厂异构第二双眼)。
- `install.sh` 里对旧 `.claude/hooks/` 残留的升级清理(升级路径卫生)。
- `.git/info/exclude` 的 `/.cursor/` `/.agents/` 忽略项。
- WO 审 / 双验收并行 / 意图闸门 / check_docs / 四态派生 —— 均有真实消费者。

WO 审保留为显式可选能力。它在未经验证的方案错误会带来明显返工，或用户明确要求时提供价值；默认流程不因每张工单都必须审而启用它。施工审仍可审工单本身，并应围绕目标、实际调用链、证据有效性和方案必要性给出具体 finding。双审同样按独立增益选择，不以固定档位自动触发。
