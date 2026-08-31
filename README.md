# ai-workflow —— 半自动多 agent 工作流(可移植机制)

「bs / planner / finishing / cleaning 四角色 + 跨家族异构派单 / 验收 + 闸门(脚本 + git pre-commit) + ADR 文档系统」的**独立机制仓**:机制的单一事实源在此,经 `install.sh` 装进 / 重链到各项目。

## 为什么单独一份
`.claude/`、`scripts/workflow/`、`agent-discipline.md` 在每个项目里是**投影进来的 kit 副本**(本地忽略,不在原地进版本库)。
机制的版本管理**只在这里**(单一事实源);各项目经 `install.sh` 投影。两种投影:
- **copy**(默认):冻结快照,Windows 稳;改工作流 = 改 `workflow-kit/` → 重跑 `install.sh` 推项目。**方向单一(kit → 项目)**,不在 copy 副本上改再回抓。
- **`--link`**(symlink 共读):项目目录指向 kit 单源,改 kit **即时生效、免重装**。

## 结构
- `agent-discipline.md` → 投影进项目根:常驻**六条纪律 + 脊椎**(全固化核,kit 拥有、一字不改)。worker/验收由 `run_worker.sh` 注进 prompt 开头;交互 harness 经 AGENTS.md 指针 + skills「开工先读」引到它。
- `claude/` → 投影进项目 `.claude/`:`skills/`(bs·planner·finishing·cleaning + 子文件)、`settings.json`、`workflow.env.example`。**不带 Claude Code 专属 hook**——闸门在脚本(意图/越界)与 git `pre-commit`(文档结构)里,可移植到 Cursor/Codex。
- `workflow-scripts/` → 投影进项目 `scripts/workflow/`:`run_worker.sh`(四模式派单;内化意图/越界闸门;放行状态纯派生成 `STATUS:` 四态;注入 discipline)、`call_agent.sh`(外呼公共入口:CLI 原生流式落 run.log、分角色超时杀整树)、`check_docs.py`(ADR frontmatter + 断链;`--changed`/`--staged`;仓根按 git toplevel 定位)、`transcribe_session.py`(会话转写)、`lib_timeout.sh` + `tests/`。
- `git-hooks/pre-commit` → install 装进目标 `.git/hooks/`:提交前跑 `check_docs --staged` 校验 index 待提交内容。
- `seed/` → 新项目首次 seed(已存在则不覆盖):`AGENTS.md`(项目工具约定 + 文档地图 + 指向 discipline)、`decisions/0000-template.md`(ADR 模板)。装进**已有 AGENTS.md** 的项目不覆盖,只提示补一行指针。
- `workflow.md` —— 设计蓝图 / 权威(**给人/维护者读**,不 seed 进消费项目、agent 不引用它)。
- `install.sh` —— 把本 kit 装进 / 更新一个项目。

## 用法
```bash
# 装进某项目(copy 快照;加 --link 则 symlink 共读)
/path/to/workflow-kit/install.sh [--link] /path/to/target-project
cd /path/to/target-project
cp .claude/workflow.env.example .claude/workflow.env    # 填模型/命令档
# install 已把忽略项写进 .git/info/exclude(不碰目标 tracked .gitignore)、pre-commit 装进 .git/hooks/
```


## 新项目 bootstrap(还没 ADR 时)
`install.sh` 已 seed 出 AGENTS.md(常驻纪律 + 文档地图)与 `decisions/0000-template.md`。再自己补空 `decisions/` 与 `TODO.md`、填 `.claude/workflow.env`;第一个架构选择直接走 `/bs` 著作 ADR-0001。冷启动清单里 architecture/TODO 可暂缺,读到什么算什么。

## 维护 / roadmap
- 改机制只动本仓 → `install.sh` 推 / 重链消费项目(方向单一 kit → 项目)。维护流程见 `docs/MAINTAINERS.md`。
- 改机制前先扫 `docs/failure-modes.md`(已知失效模式,留作纪律);原始证据在 `docs/history/`。
- 待办:跨平台兼容打磨、`install.sh --prefix` 通用化(见 `docs/history/extraction-plan.md`)。机制层单一语言,不写双份。
