# .workflow 统一投影布局 —— install 改造方案(已定;工单 #1 已落地)

> **状态**:设计已定;**三张工单全部施工完毕**——#1 ai-workflow 本仓改造、#2 hubpage 重装(track,待用户 commit)、
> #3 zhidazhushou 重装(no-track,零 tracked 影响)。施工顺序 / 各仓落地细节见文末。
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
- **根发现文档**:`AGENTS.md` 是唯一全文真源、留仓根(no-track exclude、track tracked);`CLAUDE.md` = 一行
  `@AGENTS.md`(CC import,详见「备选与失效模式」根文档双读定案)。其余设计资产收 `.workflow/`(无需根发现,`check_docs` 指哪读哪)。

## 明确不做

- 不给 no-track 的 `.workflow/` 建独立 git 仓(用户定:no-track = 不版本化,ADR 易失,坏了重写)。
- 不引入可变 `--prefix` 前缀(被固定 `.workflow/` 取代)。
- 不为 cursor 单建 skills 入口。
- 不建插件 / npm / Docker / 多语言机制层。保持「bash + md + 一个安装脚本」。

## 备选与失效模式

**已实测(2026-08-31,用户在本仓建 `.agents` / `.cursor` 亲验):**
- ✅ **skills:cursor 去重,不双读**。故 `.claude/skills`(CC)+ `.agents/skills`(codex)各一份**安全**,
  cursor 只加载一次。(原「cursor 双读 skills」担忧**证伪**,删除。)
- ❌ **根发现文档 md:cursor 双读**。`CLAUDE.md` 与 `AGENTS.md` 若都在且同内容(如软链),
  cursor 把两份都注进上下文 = 冗余(非崩溃,但该消)。

**根文档双读 —— 定案**(CC 只认 `CLAUDE.md`,已确认 2026-08-31;决策树第 1 步「只留 AGENTS.md」因此排除):
- `AGENTS.md` = **唯一全文真源**(codex + cursor 读到全文)。
- `CLAUDE.md` = **一行 `@AGENTS.md`**(CC 的 import 语法,CC 展开得全文)。install 生成这一行,不再用软链。
- **唯一残留**:cursor 读 `CLAUDE.md` 那行时展不展开 `@`。不展开(预期)→ cursor 只多读一行、无冗余;
  若展开 → **`.cursorignore` 排掉 `CLAUDE.md`** 兜底(已定后备,施工时扫一眼即知)。不再考虑软链 `CLAUDE.md`(它必双读)。

**仍待测:** harness 认不认**仓内软链 skills 入口**(`.claude/skills → ../.workflow/kit/skills`)。
(本仓已知:`.claude` 为**真实目录**时 CC + cursor 认,codex 不认 `.claude` 目录。)不认则退 **copy 真副本**
(在 exclude 内,多份无妨,升级 install 覆盖)。

## 后果

- zhidazhushou monorepo 化(消除 eval/ 子repo 概念)后,装 root `.workflow/` no-track,与 hubpage **布局同构**,
  不再有「消费者特殊布局」、不再有 `eval/` 手改补丁。
- hubpage 从当前 `--link` 根级布局迁到 `.workflow/` track。
- 所有仓的工作流:一个 dot 目录、exclude 一到几行、copy 版本可追溯、skill 无重复(除上面待测组合)。

## 施工顺序(工单切分)

1. ✅ **ai-workflow 本仓改造(已完成)**:SOT 重组为 `kit/`(与投影同构);重写 `install.sh` 投影模型(`.workflow/`
   布局、`--track`/`--no-track`、`--backends`、`VERSION` 印记、exclude 用 BEGIN/END 界定**每次重写**——随 mode/backend
   刷新、不 stale);脚本读新布局(`check_docs` 的 `DECISIONS`、`run_worker` 的 scratch / discipline 注入路径、
   `call_agent` 的 ROOT 从 git-toplevel 假设改为「读 `.workflow/` 约定」);`test_install_smoke` 覆盖两模式 +
   backend 矩阵 + 切模式刷新;`README`/`MAINTAINERS`/`workflow.md` + 全 skill/seed 路径同步到新模型。
2. ✅ **hubpage 重装(已完成,待用户 commit)**(track):`git mv` 根级 tracked 设计资产(30 ADR + architecture.md +
   TODO.md)进 `.workflow/`(rename 保历史)、`--link` 根级布局迁到 `.workflow/kit` copy、`CLAUDE.md` 软链→`@AGENTS.md`、
   `.claude/workflow.env`→`.workflow/workflow.env`、AGENTS.md 路径同步、换新 pre-commit。**tracked 变更全 stage、未 commit**
   (由用户 review 后提)。check_docs 认全 30 ADR ✓、exclude track 粒度无泄漏 ✓。
   > 实测点(小旋钮④,harness 认不认软链 skills 入口)留待真跑一次 planner/skill 时验;当前只验了软链解析到真源。
3. ✅ **zhidazhushou 重装(已完成)**(no-track):事实核实——其工作流资产**本就全在 `.git/info/exclude`、零 tracked**
   (含 3 个真 ADR,符合 no-track「ADR 易失」),故重装**零 tracked 影响**、无「命名空间张力」问题(原担忧不成立)。
   拆两条根软链 → 新 install 装到 git 根 → `mv` 3 ADR + architecture.md + TODO.md + workflow.env 进 `.workflow/`(全 untracked)
   → 用干净 `.workflow/kit/scripts` 取代 `eval/scripts/workflow` 手改副本(旧 `eval/` 覆盖层留原地、用户按需清)。
   `git status` 迁移前后均空 = tracked 树纹丝未动;check_docs 认 4 ADR ✓。
   > 关键更正:zhidazhushou **未 monorepo 化**(工作流原装在 `eval/` 子目录),但因 worker `-C` 新旧都是 git 根、
   > 设计资产又全 untracked,直接装到 git 根即可,无需先 monorepo 化——原「待 monorepo 化」前置被证不必要。

## 施工时才定的小旋钮(工单 #1 已拍板)

- `--backends` 默认值 = **`cc`**(只建 `.claude`;cursor 蹭它,codex 需显式 `--backends cc,codex`)。
- `--track` / `--no-track` 默认 = **`--track`**(设计资产版本化,安全默认;no-track 须显式声明)。
- track 模式 `VERSION` **进 git**(团队可见装了哪版;它在 exclude 白名单外,自动 tracked)。
- backend 入口 = **仓内相对软链**(`.claude/skills → ../.workflow/kit/skills`;`.agents/skills` 同)。
  > **仍待消费仓实测**:harness(CC/codex)是否认这条仓内软链 skills 入口。不认 → install 退 copy 真副本
  > (`_skills_entry` 里把 `ln -s` 换 `cp -r` 即可,exclude 已覆盖、多份无妨)。本仓测试只验软链**解析到真源**,
  > 未验 harness 加载(需在装了后端的真消费仓里跑一次 planner/skill 才知)。
