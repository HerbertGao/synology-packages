# Release PR 自动化（GitHub Release + 套件目录）

维护者授权参考：[HerbertGao/x_likes_downloader](https://github.com/HerbertGao/x_likes_downloader) 的 `release_plan` / `release_open_pr` 流程，以及 [HerbertGao/pi-extensions](https://github.com/HerbertGao/pi-extensions) 的「合并后发布」守门思路（本仓库用仓库变量而非 npm）。

## 在启用之前（默认）

- 工作流文件 `.github/workflows/release.yml` 在 `master` 上**存在**，但所有 job 带有  
  `if: vars.RELEASE_AUTOMATION_ENABLED == 'true'`。
- **未**设置该仓库变量时，工作流**从不**打开 release PR、不打 tag、不创建 Release、不改线上 `docs/packages.json`。
- 合入本自动化 PR **本身**不会触发发布（无 `feat`/`fix` 触及 `packages/*/overlay`，且变量默认未开）。

## 启用方式

1. 维护者审阅并合并自动化 PR。
2. 在 GitHub **Settings → Secrets and variables → Actions → Variables** 新建  
   `RELEASE_AUTOMATION_ENABLED` = `true`。
3. 确认 **Settings → Actions → General → Workflow permissions** 允许 `GITHUB_TOKEN` 创建 PR（与 x_likes 相同要求）。

无需额外 secret；全流程使用 `GITHUB_TOKEN` / `github.token`。

## 生命周期

```text
feat/fix 合入 master（触及 packages/openlist 或 packages/easytier）
    → release workflow（prepare）
    → 分支 release/<pkg>-next + 草稿 release PR
    → 在 manifest 中记录 **ci_sha**（`$rev` 上最近、触及该套件 CI path-filter 的提交，而非任意 docs-only master 推送）
    → 等待该 sha 上的 synology-packages-ci 构件 → 仅更新该套件 packages.json 字段
维护者审阅并合并 release PR（保留标题 chore(release): publish <pkg> <vers-rev>）
    → release workflow（publish）
    → 按 manifest.ci_sha（**非** merge 提交）拉取构件并校验目录哈希与 CI SPK 一致
    → annotated tag（如 openlist-4.2.10-4）+ GitHub Release（默认 prerelease，非 latest）
    → master 上 docs/packages.json 已由 PR 更新 → GitHub Pages 刷新目录
```

手动恢复路径：推送已有 tag（`openlist-*` / `easytier-*`）可在启用后触发 publish（若 Release 尚不存在）。

## 约束（与 AGENTS.md 一致）

- **只改**正在发布的套件在 `docs/packages.json` 中的那条记录。
- SPK 来自 **CI 构件**（`openlist-spk-apollolake-7.3`、`easytier-spk-apollolake-kvmx64-7.3`），不在此 workflow 内重建 Docker 图（除非 CI 未跑过则 publish 等待/失败）。
- 新 Release 默认 **`prerelease: true`**，**不**调用 `make_latest`；**不会**把已发布的 `easytier-2.7.0-10` 等改为 stable。
- **不**安装 NAS、不 SSH 生产、不包含任何秘密或私有配置。

## 文件

| 路径 | 作用 |
| --- | --- |
| `.github/workflows/release.yml` | 编排 prepare / enrich / publish |
| `scripts/release_plan.sh` | prepare / publish / skip 决策 |
| `scripts/release_open_pr.sh` | 推送 `release/<pkg>-next` 并开草稿 PR |
| `scripts/release_try_catalog_update.sh` | 拉 CI 构件、写目录字段 |
| `scripts/release_publish.sh` | 打 tag、上传 Release 资产 |
| `.release/<tag>.json` | 每版 manifest（由 release PR 引入） |