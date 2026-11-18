# ai-dev-flow

[English](README.en.md)

`ai-dev-flow` 是给 AI 编程助手（Claude Code、Codex 等）用的开发流程 skill。你只管三件事：**方向**（要什么）、**品味**（需要人看的结果对不对）、**单向门**（撤不回的事做不做）。做、证明、独立审查、合并、复盘由它调度。

质量押在机器上，不押在流程和询问上：

- **项目自带 verify**：一条命令能判对错；按改动选测试，全量放到合并后机器空闲时在后台跑。
- **另一家模型审一次**：写和审不是同一个会话，最多两轮，不过就拆小重做。
- **每周量北极星**：在真实验收数据上量最终交付物，方向不对早发现。
- **推翻前提就停**：实测数字说明做法不成立时，单独通知你，不继续堆补丁。

能撤回的事不停下来问"要不要"：直接做，给出结果，你事后可以推翻。

## 结构

```
skills/ai-dev-flow/
  SKILL.md              总览（唯一入口）：定档、什么时候找你、信任等级、汇报
  modules/build.md      理解 → 做 → 证明
  modules/verify.md     独立审查：谁审、说明模板、几轮、记在哪
  modules/land.md       合并、提交正文模板、合并后清理
  modules/diagnose.md   诊断：先有能判对错的信号再修
  modules/orchestrate.md 队列格式、派活、模型设置表、关联项目
  modules/harness.md    给项目搭验证：verify、对照表、后台全量、hooks、权限
  modules/garden.md     每周复盘、教训升级、清理
  modules/direction.md  原型、决定卡、北极星
  modules/portfolio.md  多项目总览：项目清单、收状态、转达、通知
  modules/hosts.md      T3、Claude Code、Codex 的具体做法
  templates/            决定卡、模型设置表样例
  scripts/              PowerShell 脚本，清单见 scripts/README.md
skills/next/SKILL.md    /next：在项目里按队列一项接一项做，直到需要你
skills/next/cloud.md    在云端会话里做一项
tests/                  脚本的测试，pwsh -NoProfile -File tests/run-all.ps1 全跑
```

## 怎么用

| 你说 | 它会 |
|---|---|
| `/next`（可带答复，如 `/next #7 按你的`） | 按队列一项接一项做、审、合，直到需要你才收尾、发通知 |
| 想做 X、修 Y | 定档，做到需要你的地方 |
| 现在到哪了 | 三行汇报 |
| 可以 / 可以合并 | 合并 |
| 不对 / 报错了 | 先分类，再诊断 |
| 复盘 | 看一周合进去的东西，给你一份摘要 |
| 先停 | 停在安全点，写进队列 |

它只在这几种情况找你：单向门要授权、要你亲眼看、方向要选、卡住了、实测结果推翻了做法的前提。每次一次问完，附推荐答案。

| 档 | 情况 | 谁说了算 |
|---|---|---|
| 自走 | 能撤回，verify 能证明对错 | 按信任等级合并 |
| 看一眼 | 能撤回，但要人看效果 | 你说"可以"才合 |
| 单向门 | push、发版、改正式数据、删除、对外、花钱、安全设置 | 你授权才做 |

信任等级写在项目 `AGENTS.md`：L0 每次问你（默认），L1 摞好一次合一批，L2 直接合、你事后抽查。只由你改。

同时推进几个项目时，另建一个只在本地的总览仓库放项目清单、模型设置表和跨项目决定；`scripts/status.ps1` 一次收齐各项目的状态（`modules/portfolio.md`）。所有模块按需读取，单项目只用前面几个就够。

## 安装

在 Claude Code 或 Codex 里说一句：

```
按 https://github.com/a-littlecat/ai-dev-flow-oss/blob/main/INSTALL.md 安装 ai-dev-flow
```

AI 编程助手会检查环境，复制文件，接上 Claude Code，再确认装好。遇到已有文件不会直接覆盖，先问你。手机推送、权限通知、后台全量测试这几个可选功能也一次问你要不要。步骤见 [INSTALL.md](INSTALL.md)，想自己装就照着做。升级也用同一句话。

只在 Windows + PowerShell 7 上用。

## 版本

- **3.0.0**：首个公开版本。

## 许可

MIT，见 [LICENSE](LICENSE)。
