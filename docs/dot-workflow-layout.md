# .workflow 统一投影布局 —— install 改造方案(已定,待施工)

> **状态**:设计已定(经数轮发散 + 砍伪需求收敛),待在本仓施工。施工顺序见文末。
> **定位**:取代现行「投影进项目根(`.claude` / `scripts/workflow` / `agent-discipline.md` 散落根级)」的
> install 模型,也取代 `docs/history/extraction-plan.md` 第五节的 `install.sh --prefix <子目录>` 设想
> ——用**固定约定 `.workflow/`** 取代**可变前缀**,约定优于配置。

## 意图(为什么)

三个真问题逼出本方案:
1. **project-root ≠ git-root**:消费仓(如 zhidazhushou)的工作范围是子目录,旧工具假设 git 顶层 = 项目根,
   逼出满地 `eval/` 手改补丁,每次升级重打,极难维护。
2. **多消费仓 + 生产仓协作风险**:zhidazhushou 是生产仓,用户在 `eval` 分支频繁 rebase 到 develop;
   工作流文件若与生产 tracked 树共享命名空间,双向都可能互相搞坏。
3. **散落投影**:入口散在根级,`.git/info/exclude` 难写、冲突面大。

一句话解法:**把一个消费仓的全部工作流产物收进根下唯一的 `.workflow/`**,
用固定约定消除前缀、用一个 dot 目录把冲突面缩到最小、用两种 exclude 粒度满足「要不要版本化」。

## 决策(可测契约)

### 1. 安装一律 copy 进 `<gitroot>/.workflow/`

```
<gitroot>/
  .workflow/
    kit/                      # 机制 copy(SOT = ai-workflow 快照;整体永远 exclude)
      skills/                 #   bs · planner · finishing · cleaning + 子文件
      scripts/                #   run_worker.sh call_agent.sh check_docs.py derive_status.sh
      agent-discipline.md     #   lib_timeout.sh transcribe_session.py tests/
      settings.json  workflow.env.example
      git-hooks/pre-commit    #   源(install 装进 .git/hooks/)
    decisions/                # 设计资产(ADR;含 0000-template)—— 位置永远在这
    architecture.md  TODO.md  # 设计资产 —— 位置永远在这
    workflow.env              # 本机配置(永远 exclude)
    scratchpad/               # 临时产物(永远 exclude)
    VERSION                   # 版本印记:ai-workflow 的 tag + commit
  AGENTS.md                   # 因「根发现」留仓根(见 §4);CLAUDE.md → 软链它
  .claude/ .agents/ .cursor/  # 按 --backends 建的后端入口(见 §4)
  .git/hooks/pre-commit       # install 装
```

### 2. 两模式 track / no-track:只差 exclude 粒度,物理位置永不变

- 设计资产(`decisions/` `architecture.md` `TODO.md`)**位置永远在 `.workflow/`**,不剪切、不搬家、不 symlink 到根。
- `check_docs` **永远指 `.workflow/decisions`**;越界校验的 durable 锚也指 `.workflow/` 下这几个。
- **no-track**(如 zhidazhushou):`.git/info/exclude` 收 `/.workflow/` 一行(+ 根入口若干,见 §4)。
  设计资产不进仓、不版本化(用户已接受 ADR 易失)。**不**给 `.workflow/` 建独立 git 仓。
- **track**(如 hubpage):exclude 只收 `/.workflow/kit/` + `/.workflow/workflow.env` + `/.workflow/scratchpad/`;
  `decisions/` `architecture.md` `TODO.md` **tracked** → `pre-commit` 的 `check_docs --staged` 靠 git index
  校验 ADR 那条链**完整**。
  > 注:gitignore 语法下父目录一旦整体排除,子文件 `!` 救不回。故 track 模式必须**精确排 `/.workflow/kit/`**
  > 那一层,而非排 `/.workflow/` 再反选文档。

### 3. copy 按需升级 + VERSION 印记

- **只 copy、不自动更新**:symlink 到 SOT 单源会让所有消费仓被动跟版本,对生产仓危险。每仓按需 re-run install 升级。
- `.workflow/VERSION` 记 ai-workflow 的 tag + commit,回答「这仓装了哪版工作流」。track 模式让它 tracked(团队可见)。

### 4. 后端入口:`--backends`,按声明建;skills 单源多入口

后端事实(施工前已核实):

| harness | 认的目录 | 只认自己? |
|---|---|---|
| CC | `.claude` | 是 |
| codex | `.agents` | 是 |
| cursor | `.cursor` / `.claude` / `.codex` / `.agents` 全读 | 否(全能) |

- `install --backends cc,codex,cursor`,按声明建对应根入口目录。
- **skills 真源一份** = `.workflow/kit/skills`;给每个**只认自家目录**的后端各建一个入口指向真源
  (CC → `.claude/skills`、codex → `.agents/skills`);**cursor 不单建入口**(它蹭别人的)。
  仅含 cursor 的仓 → 借 `.claude/skills` 给它读。
- **根发现文档**:`AGENTS.md`(+ `CLAUDE.md` → 软链)因**必须在仓根被 harness 发现**,留仓根
  (no-track exclude、track tracked);其余设计资产收 `.workflow/`(它们无需根发现,`check_docs` 指哪读哪)。

## 明确不做

- 不给 no-track 的 `.workflow/` 建独立 git 仓(用户定:no-track = 不版本化,ADR 易失,坏了重写)。
- 不引入可变 `--prefix` 前缀(被固定 `.workflow/` 取代)。
- 不为 cursor 单建 skills 入口。
- 不建插件 / npm / Docker / 多语言机制层。保持「bash + md + 一个安装脚本」。

## 备选与失效模式(唯二纸上定不死、必须拿真实 harness 实测)

1. **cursor 双读**:同一仓既建 `.agents`(codex)又用 cursor 时,cursor 会同读 `.claude` + `.agents`
   两份 skills(codex 只认 `.agents` 的硬约束逼出,消不掉)。**实测**:cursor 双读是冗余无害,还是报冲突 / 混乱?
   若有害 → 该仓的 backend 组合需取舍(codex 与 cursor 不同仓共存,或接受其一)。
2. **harness 认不认仓内软链入口**:`.claude/skills → ../.workflow/kit/skills` 这类**仓内相对软链**,
   CC / codex / cursor 认不认?(本仓已知:`.claude` 为**真实目录**时 CC + cursor 认,codex 不认 `.claude`。)
   软链入口不认 → 退化为 **copy 真副本**(在 exclude 内,多份无妨,升级 install 覆盖)。

## 后果

- zhidazhushou monorepo 化(消除 eval/ 子repo 概念)后,装 root `.workflow/` no-track,与 hubpage **布局同构**,
  不再有「消费者特殊布局」、不再有 `eval/` 手改补丁。
- hubpage 从当前 `--link` 根级布局迁到 `.workflow/` track。
- 所有仓的工作流:一个 dot 目录、exclude 一到几行、copy 版本可追溯、skill 无重复(除上面待测组合)。

## 施工顺序(工单切分)

1. **ai-workflow 本仓改造**:重写 `install.sh` 投影模型(`.workflow/` 布局、`--track`/`--no-track`、
   `--backends`、`VERSION` 印记、两种 exclude 生成);脚本读新布局(`check_docs` 的 `DECISIONS`、`run_worker`
   的 scratch / discipline 注入路径、`call_agent` 的 ROOT —— 从「git-toplevel 假设」改为「读 `.workflow/` 约定」);
   `test_install_smoke` 覆盖新布局的两模式 + backend 矩阵;`README` / `MAINTAINERS` 主体同步到新模型。
2. **hubpage 重装**(track):新 install 装 → 迁掉当前 `--link` 根级布局 → 验 pre-commit / check_docs 链 + `run-all`。
3. **zhidazhushou 重装**(no-track):待其 monorepo 化到 root 后,新 install 装 → 删旧 `eval/` 手改补丁 →
   验 `test_derive` 18/18 + 一次 dry 派单。

## 施工时才定的小旋钮

- `--backends` 默认值(不指定时建哪些)。
- track 模式 `VERSION` 进不进 git(倾向进,团队可见装了哪版)。
- backend 入口用软链 or copy —— 取决于「备选与失效模式」第 2 条的实测结果。
