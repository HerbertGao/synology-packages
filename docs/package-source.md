# Package Center 第三方来源（GitHub Pages 目录）

## 一条 Location 覆盖所有版本

在 DSM **套件中心 → 设置 → 套件来源** 中只需添加**一个** Location URL，后续发布新版本时**不必**改来源地址：

```text
https://herbertgao.com/synology-packages/packages.json
```

目录与图标由本仓库 `docs/` 经 **GitHub Pages**（`master` 分支、`/docs` 根目录）发布，并通过自定义域 **herbertgao.com** 对外提供 HTTPS。`https://herbertgao.github.io/synology-packages/...` 会 301 跳转到同路径的 `https://herbertgao.com/...`；在 Location 与 `thumbnail` 中应**直接**书写自定义域 HTTPS 地址（勿依赖跳转；对该域名的 plain HTTP 不可用）。

各套件的 **SPK 安装包** 仍放在对应版本的 **GitHub Release** 上，通过每条记录里的 `link` 指向。

启用 Pages：仓库 **Settings → Pages**，Source 选 **Deploy from a branch**，Branch 选 `master`，文件夹选 **`/docs`**。合并包含 `docs/packages.json` 的变更后即可通过上述 URL 访问目录。

## 发布新套件或新版本

1. 在 GitHub 上为该版本创建 **Release** 并上传 SPK（以及该版本所需的其它资产；图标若可复用则不必随 tag 重复上传）。
2. 将新图标（若需要）放入 `docs/icons/`。
3. 编辑 `docs/packages.json`：在顶层 `packages` 数组中**新增一条对象**，或**更新**已有 `package` 的 `version`、`link`、`md5`、`sha256`、`size` 等字段。
   - `link` 必须是该版本 Release 上的 SPK 直链，**不要**把 Location 设成 `releases/download/<tag>/packages.json` 这类按 tag 变的地址。
   - `thumbnail` 为两段 URL：**先 72×72、后 256×256**（与社群套件中心约定一致），使用自定义域 Pages 稳定地址，例如  
     `https://herbertgao.com/synology-packages/icons/<name>_72.png` 与  
     `https://herbertgao.com/synology-packages/icons/<name>_256.png`
4. 向 `master` 提交并合并 PR；Pages 更新后，用户端套件来源会自动看到新条目或新版本信息。

## 不要做的事

- **不要**为每个 Release tag 单独维护一份 `packages.json` 并让 Location 指向 tag URL（用户每次升级都要改来源）。
- **不要**把 SPK 放到 Pages 站点下当作 `link`（体积极大且不适合用 Pages 分发；使用 Release 资产）。
- 本目录 JSON 形状与常见第三方源一致：顶层 `{"packages":[...]}`，字段含义与 DSM 第三方来源约定相同。

---

# OpenList 上游来源与版本钉扎

## 真相来源

- 版本与 digest：`packages/openlist/upstream.lock.json`
- 构建 overlay：`packages/openlist/overlay/**`
- spksrc 基线 commit 与说明：同上 lock 文件中的 `spksrc` 段

## 上游监控（GitHub Actions）

工作流：`.github/workflows/upstream-monitor.yml`（每日 UTC 02:23 + `workflow_dispatch`）。

它仅做以下事情：

1. 用 GitHub API 对比 lock 中的钉扎与 [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList)、[OpenListTeam/OpenList-Frontend](https://github.com/OpenListTeam/OpenList-Frontend) 的最新 release/tag。
2. 可选地报告 [SynoCommunity/spksrc](https://github.com/SynoCommunity/spksrc) 默认分支相对 pinned commit 的前移，以及 `cross/openlist/Makefile` 上的 `PKG_VERS`（信息性；**不**等于必须同步提升本仓库的 OpenList 版本）。
3. 打开、更新或关闭唯一跟踪 Issue，标题固定为 `chore: upstream updates available`。

**不会**自动开升级 PR、合并、发 Release/tag、改 `docs/packages.json` / GitHub Pages，也不会在 NAS 上安装套件。

升级流程仍为：维护者审阅后开 **草稿 PR**，更新 lock、`digests`，运行 `./scripts/verify-upstream-digests.sh` 与 `./scripts/ci-run-checks.sh`（及可选 `./scripts/build-openlist.sh`），经明确授权后再发布 Release 与目录更新。

本地校验（无网络）：

```bash
node --test scripts/check-upstreams.test.mjs
node scripts/check-upstreams.mjs --validate
```

Manifest：`packages/openlist/upstreams.json`（watch 列表；pin 仍以 `upstream.lock.json` 为准）。