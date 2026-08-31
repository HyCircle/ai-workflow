# ai-workflow 独立仓抽取规划（分析 + 计划）

> 状态：规划已定，待新 session 执行。执行完成后本文随抽取归档（并入新仓 docs/ 或删除）。
> 关联：同目录 `workflow-kit-diagnosis-report.md` = 本机制此前的诊断与修复执行记录（含两侧同步明细），抽取时一并带走。

## 一、定位

把本 `workflow-kit/` 抽成独立仓库 `ai-workflow`：一个**机制仓**（安装进项目、随项目投影），不是产品仓。
内容 = 现有 workflow-kit 全部：README、workflow.md（设计权威）、install.sh、claude/skills、workflow-scripts、git-hooks、seed、agent-discipline.md，加本文档与诊断报告。

## 二、已定参数（本 session 拍板）

- 仓库名：`ai-workflow`
- 许可：MIT（未来开源）
- 机制层语言：单一中文（workflow.md「中英 canonical」已写死不写双份；公开后 README 顶部加英文简介即可）
- 待定：托管平台（GitHub / Gitee）、公开时间点

## 三、当前状态（抽取起点）

- 机制修复全部完成：derive 解析加固、双验收容忍层删除、越界 name-only、dispositions / handoff 机制删除、worker 报告三段、pytest 摘要化、冗余清理、非 git 兜底 fail-loud、刻疤清理。
- 双侧（kit ↔ 消费项目 zhidazhushou 的 eval/ 前缀投影）已同步一致；`test_derive.sh` 双侧 18/18 全绿；`bash -n` 全过。
- 消费侧残留差异 = eval/ 布局适配（EVAL_ROOT 手改补丁 + DECISIONS 路径），抽取时用 install.sh `--prefix` 消除（见五）。

## 四、历史迁移

`workflow-kit/` 现为 hubpage 仓子目录（无独立 .git），有完整演进历史。
workflow.md 承诺「changelog = git 历史」→ 用 `git subtree split --prefix=workflow-kit`（或 git-filter-repo）把历史拆进新仓，保留演进证据链；不用全新 copy 只留 initial commit。

## 五、抽取时要补的能力（现状缺口）

1. **install.sh 通用化（`--prefix <子目录>`）**：投影路径、`.git/info/exclude` 块、pre-commit 路径按前缀生成，并落一个 layout 标记（如 `.claude/workflow.env` 里 `WF_PREFIX=<子目录>`）；`check_docs.py` 的 `DECISIONS` 与 `run_worker.sh` 的 scratchpad 路径读该标记。消费侧现有 EVAL_ROOT 手改补丁随之删除，投影副本零手改。
   - 约束：不能退回 `__file__` 相对定位（check_docs docstring 已论证：symlink 共读时解析进 kit 而非消费仓，必须 git toplevel + 标记）。
2. **CI**：跑 4 个 bash 测试（test_derive 18 例 / call_agent_stream / intent_gate / staged）+ `check_docs` 自检 + install.sh 冒烟测试（装进临时目录，验证投影 / exclude / pre-commit 落位）。机制仓自身改动从此有测试门禁。
3. **版本化**：`v0.1.0` 起打 tag；copy 模式消费方天然是「按 install 时点冻结的快照」，tag 让「项目装的是哪版机制」可追溯。

## 六、消费侧迁移（zhidazhushou）

用新 install.sh `--prefix eval` 重装：删手改 EVAL_ROOT 补丁、重新生成 exclude 块与 pre-commit、验证 `test_derive.sh` 18/18 + 一次 dry 派单（`RUN_WORKER_INTENT_CHECK_ONLY=1`）。此后两边一致性由「新仓 → install.sh」单一方向保证，不再手工同步。

## 七、明确不做（纪律③）

不建插件系统、不做 npm / Docker 包装、不做多语言机制层、不为想象中的消费者预写功能。保持「bash + md + 一个安装脚本」的形态。

## 八、执行顺序

1. 定托管平台与公开时间点
2. subtree split 出仓 → initial commit → `v0.1.0` tag
3. CI（测试 + install 冒烟）
4. install.sh `--prefix` + layout 标记
5. 消费侧重装（`--prefix eval`）、删 EVAL_ROOT 补丁、验证
6. 消费侧 AGENTS.md 文档地图指向新仓

## 九、下 session 起点

冷启动：agent-discipline → AGENTS → 本文档 + `workflow-kit-diagnosis-report.md` → 按第八节顺序执行。
