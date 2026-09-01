# ai-workflow —— 半自动多 agent 工作流(可移植机制)

「bs / planner / finishing / cleaning 四角色 + 跨家族异构派单 / 验收 + 闸门(脚本 + git pre-commit) + ADR 文档系统」的**独立机制仓**:机制的单一事实源在此,经 `install.sh` 装进各项目。

## 为什么单独一份
一个消费仓的全部工作流产物统一收进根下唯一的 `.workflow/`:机制层 `.workflow/kit/` 是本仓 `kit/` 的 **copy 快照**(本地忽略、按需重装升级),设计资产(ADR / architecture / TODO)也在 `.workflow/` 下。机制的版本管理**只在本仓**(单一事实源),各项目经 `install.sh` copy 投影。**只 copy、不 symlink 单源**:symlink 会让所有消费仓被动跟版本,对生产仓危险;每仓按需 re-run `install.sh` 升级,`.workflow/VERSION` 记装了哪版。

## 结构(SOT 与消费仓 `.workflow/kit/` 同构)
- `kit/` —— 机制层,整包 copy 进消费仓 `.workflow/kit/`:
  - `kit/agent-discipline.md`:常驻**六条纪律 + 脊椎**(全固化核,kit 拥有、一字不改)。worker/验收由 `run_worker.sh` 注进 prompt 开头;交互 harness 经 AGENTS.md 指针 + skills「开工先读」引到它。
  - `kit/skills/`:bs·planner·finishing·cleaning + 子文件(**skills 真源一份**;install 给只认自家目录的后端各建软链入口 `.claude/skills`、`.agents/skills` → 指向它)。
  - `kit/scripts/`:`run_worker.sh`(四模式派单;内化意图/越界闸门;放行状态纯派生成 `STATUS:` 四态;注入 discipline)、`call_agent.sh`(外呼公共入口:CLI 原生流式落 run.log、分角色超时杀整树)、`check_docs.py`(ADR frontmatter + 断链;`--changed`/`--staged`;设计资产按 `.workflow/decisions` 定位)、`transcribe_session.py`、`lib_timeout.sh` + `tests/`。
  - `kit/settings.json`、`kit/workflow.env.example`:CC 配置模板 / 本机配置样例。**不带 Claude Code 专属 hook**——闸门在脚本(意图/越界)与 git `pre-commit`(文档结构)里,可移植到 Cursor/Codex。
  - `kit/git-hooks/pre-commit`:install 装进目标 `.git/hooks/`,提交前跑 `check_docs --staged` 校验 index 待提交内容。
- `seed/` —— 新仓首次 seed(已存在则不覆盖):`AGENTS.md`(根发现文档,留仓根)、`decisions/0000-template.md`(ADR 模板,进 `.workflow/decisions/`)。
- `workflow.md` —— 设计蓝图 / 权威(**给人/维护者读**,不 seed 进消费项目、agent 不引用它)。
- `install.sh` —— 把本 kit 装进 / 更新一个项目。
- 完整投影布局定案见 `docs/dot-workflow-layout.md`。

## 用法
```bash
# 装进某项目。--track(默认,设计资产版本化)/ --no-track(整个 .workflow 不版本化)
# --backends cc,codex,cursor(默认 cc;cc 建 .claude、codex 建 .agents,cursor 蹭别人不单建)
/path/to/ai-workflow/install.sh [--track|--no-track] [--backends cc,codex] /path/to/target-project
cd /path/to/target-project
cp .workflow/kit/workflow.env.example .workflow/workflow.env    # 填模型/命令档
# install 已把忽略项写进 .git/info/exclude(不碰目标 tracked .gitignore)、pre-commit 装进 .git/hooks/
```

两种 track 模式只差 exclude 粒度,`.workflow/` 物理位置永不变:
- **track**(团队共享设计资产):exclude 只收 `/.workflow/kit/`、`/.workflow/workflow.env`、`/.workflow/scratchpad/` + 后端根入口(`.claude/` `.agents/` 等);`decisions/` `architecture.md` `TODO.md` `VERSION` tracked,`pre-commit` 靠 git index 校验 ADR 链完整。
  > 取舍:后端根入口(含 seed 到 `.claude/settings.json` 的项目配置)随入口目录整体不 track,团队成员各自 `install.sh` 重建。若要版本化 `settings.json`,手动把它移出 `.claude/` 或从 exclude 白名单里放行。
- **no-track**(与生产 tracked 树隔离):exclude 整包收 `/.workflow/` + `/AGENTS.md` + `/CLAUDE.md`;设计资产不进仓(接受 ADR 易失)。

## 新项目 bootstrap(还没 ADR 时)
`install.sh` 已 seed 出 `AGENTS.md`(常驻纪律指针 + 文档地图)与 `.workflow/decisions/0000-template.md`。再自己补空 `.workflow/architecture.md` 与 `.workflow/TODO.md`、填 `.workflow/workflow.env`;第一个架构选择直接走 `/bs` 著作 ADR-0001。冷启动清单里 architecture/TODO 可暂缺,读到什么算什么。

## 维护 / roadmap
- 改机制只动本仓 `kit/` → `install.sh` 推消费项目(方向单一 kit → 项目)。维护流程见 `docs/MAINTAINERS.md`。
- 改机制前先扫 `docs/failure-modes.md`(已知失效模式,留作纪律);原始证据在 `docs/history/`。
- 布局施工进度(工单 #1 本仓 / #2 hubpage / #3 zhidazhushou)见 `docs/dot-workflow-layout.md` 文末。
