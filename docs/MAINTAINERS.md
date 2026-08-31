# MAINTAINERS —— 怎么改本仓(ai-workflow)

> 本仓 = 半自动多 agent 工作流的**机制单一事实源(SOT)**。装进各项目、随项目投影。
> 改机制**只动本仓**,再经 `install.sh` 推 / 重链到消费项目。**方向单一(kit → 项目)**,
> 绝不在项目里的投影副本上改再回抓。

## 冷启动读什么
`agent-discipline.md`(六条纪律)→ `README.md`(结构)→ `workflow.md`(设计权威)→
`docs/failure-modes.md`(改机制前必扫)→ 相关 `docs/history/`。

## 文档职责(一类信息一个家)
- `agent-discipline.md` —— 六条纪律 + 脊椎。**投影进每个消费项目根**,是消费者面向的常驻宪法。一字不带维护细节。
- `workflow.md` —— 设计权威 / 蓝图(给人 / 维护者读)。**不 seed 进消费项目,agent 不引用**。
- `README.md` —— 本仓结构与用法总览。
- `docs/failure-modes.md` —— 已知失效模式(留作纪律);改机制前必扫。**维护者面向,不投影**。
- `docs/dot-workflow-layout.md` —— 下一步 install 改造方案(`.workflow/` 统一布局,已定待施工)。
- `docs/history/` —— 原始诊断 / 计划的证据归档(failure-modes 的出处)。
- `docs/MAINTAINERS.md`(本文)—— 维护流程。

## 改机制的门禁
1. 改 `workflow-scripts/` / `git-hooks/` / `install.sh` → **push 前本地跑 `bash workflow-scripts/tests/run-all.sh`,绿了再 push**。
   跑五件:`test_derive`(18 例)/ `test_call_agent_stream` / `test_intent_gate` /
   `test_staged`(即 check_docs 自检)/ `test_install_smoke`(装进临时 git repo 验投影 / exclude / pre-commit)。
   solo 私有仓,不上 CI —— 靠这条本地纪律,不靠云端跑一遍。
2. 触碰 derive / 双验收 / 越界 / 定位逻辑前,**先读 `docs/failure-modes.md`** 对应条目——那些坑填过一次。
3. 新加代码别写疤痕注释(纪律⑥/FM-8):历史教训进 `docs/failure-modes.md`,代码里只留正面契约。

## 投影模式(consumer 侧)
- **copy**(默认):冻结快照,Windows 稳。改机制 = 改本仓 → 消费项目重跑 `install.sh` 推。
- **`--link`**(symlink 共读):项目目录指向本仓单源,改本仓即时生效、免重装。

## 版本化
- copy-mode 消费方 = 按 install 时点冻结的快照;打 tag 让「项目装的是哪版机制」可追溯。
- 从 `v0.1.0` 起打 tag;changelog = git 历史(不另写 CHANGELOG)。

## roadmap
- **下一步(已定待施工)**:install 改造为 `.workflow/` 统一布局 —— 见 `docs/dot-workflow-layout.md`。
  它**取代**了原 `install.sh --prefix <子目录>` 设想(`docs/history/extraction-plan.md` 第五节):
  用固定约定 `.workflow/` 取代可变前缀。zhidazhushou 迁移并入该方案第三步。
- 不建插件 / npm / Docker 包装、不做多语言机制层。保持「bash + md + 一个安装脚本」(纪律③)。
