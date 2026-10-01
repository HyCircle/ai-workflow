# MAINTAINERS —— 怎么改本仓(ai-workflow)

> 本仓 = 半自动多 agent 工作流的**机制单一事实源(SOT)**,以 Python 包 `ai-workflow` 分发,命令入口 `wf`。
> 机制文件在 `wf/kit/`,由 `wf init` 整包复制进消费仓 `.workflow/kit/`。**方向单一(本仓 → 项目)**,
> 不在项目里的副本上改再回抓。

## 冷启动读什么
`wf/kit/discipline.md`(六条纪律)→ `wf/seed/AGENTS.md`(文档路由)→ `README.md`(用法)→ `docs/design.md`(设计权威)→
`docs/failure-modes.md`(改 `wf/` 代码前必扫)→ 相关 `docs/history/`(历史归档,非现行规范)。

## 文档职责(一类信息一个家)
- `wf/kit/discipline.md` —— 六条纪律 + 脊椎。投影进 `.workflow/kit/`。
- `wf/seed/AGENTS.md` —— 消费仓根指令模板;**文档路由 + 路径简写真源**。`wf init` 首次放到仓根。
- `docs/design.md` —— 设计权威 / 蓝图(给人 / 维护者读)。**不投影进消费项目,agent 不引用**。
- `README.md` / `README.en.md` —— 本仓结构与用法总览,中英两份同步。
- `docs/failure-modes.md` —— 已知失效模式;改 `wf/` 代码前必扫。**维护者面向,不投影**。
- `docs/dot-workflow-layout.md` —— `.workflow/` 布局契约。
- `docs/history/` —— 原始诊断 / 计划的证据归档;**勿当现行规范**。
- `docs/MAINTAINERS.md`(本文)—— 维护流程。

## 书写纪律(路径)
- **消费仓运行时文档**(skills、seed/AGENTS):正文用 **AGENTS 文档路由** 里的简写;命令示例写 `wf` 命令与全路径。
- **`wf/kit/` 投影纪律**:只引用安装后消费仓**真实存在**的路径(`.workflow/*`、`AGENTS.md` 等),不引用 `docs/`、`README.md` 等仅本仓有的文件。
- **活跃文档不写具体消费仓名**;迁移故事只留 `docs/history/`。

## 改机制的门禁
1. 改 `wf/` 代码 → 提交前跑 `uv run --group dev pytest tests -q`,绿了再提交。测试用假 CLI(`tests/fake_cli.py`)替代三个模型 CLI,其余走真实代码路径。solo 私有仓,不上 CI。
2. 改外呼、越界检查或仓根定位前,先读 `docs/failure-modes.md` 对应条目。
3. 新代码别写疤痕注释(纪律⑥):历史教训进 `docs/failure-modes.md`,代码里只留正面契约。
4. 改了外呼参数时,用真实 CLI 跑一次最小 `wf ask`,确认最终回复与用量都能提取。

## 本机更新与投影
- 本机装当前工作树:`uv tool install --reinstall .`;从远端装:`uv tool install git+<仓地址>`。
- 消费项目里重跑 `wf init` 推新版本:只覆盖 `.workflow/kit/`,设计资产与本机配置不动。**不 symlink 单源**(避免所有消费仓被动跟版本)。
- track / no-track:同一 `.workflow/` 布局,只差 `.git/info/exclude` 粒度(见 README)。

## 版本化
- 版本号在 `pyproject.toml`,`wf --version` 显示。改了会影响消费项目的行为时递增版本并打 tag;changelog = git 历史。

## roadmap
- 下一步:`/challenge` 结论质疑技能,基于 `wf ask`。
- 不接各家 SDK、不做 MCP 服务、不支持原生 Windows;保持「一个标准库命令行工具 + Markdown」(纪律③)。
