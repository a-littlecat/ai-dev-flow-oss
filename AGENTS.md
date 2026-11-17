# ai-dev-flow

开发流程 skill 本身，也按它自己管：开发相关请求从 `skills/ai-dev-flow/SKILL.md` 进入。

- **信任等级**：L0（合并前问维护者）。
- **北极星**：无（流程 skill 本身，效果看使用它的项目）。
- **队列**：`docs/queue.md`。
- **改了哪里跑哪些**（退出码 0 才算通过）：改了 `scripts/<名字>.ps1` 跑 `tests/<名字>.tests.ps1`（`notify.ps1`、`watch.ps1` 跑 `tests/status.tests.ps1`）；改了任何 `.md` 跑 `pwsh -NoProfile -File skills/ai-dev-flow/scripts/check-md.ps1`；其他或几个脚本都改了跑 `pwsh -NoProfile -File tests/run-all.ps1`。
- **不提交**：密钥、任何项目的数据、本机绝对路径。
