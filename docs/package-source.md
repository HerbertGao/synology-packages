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