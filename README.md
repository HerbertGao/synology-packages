# synology-packages

私人维护的 Synology 套件配方仓库（薄 overlay 于 [SynoCommunity/spksrc](https://github.com/SynoCommunity/spksrc)）。

当前首批目标：**OpenList v4.2.10**，**DS918+**（`apollolake` / x86_64），**DSM 7.3**。详见 `docs/openlist/` 与 `packages/openlist/`。

OpenList 套件对外端口与上游一致：**5244**（`SERVICE_PORT` / `ADMIN_PORT` / DSM 集成元数据）。Overlay 不会把 DSM 元数据同步为 `config.json` 中的自定义 `http_port`；既有非 5244 存量部署的迁移不在仓库文档范围内。

## 快速检查（开发机）

```bash
git clone <this-repo>
cd synology-packages
chmod +x scripts/*.sh
./scripts/ci-run-checks.sh
```

## 本地构建 SPK（需 Docker）

参考 [SynoCommunity Docker 文档](https://docs.synocommunity.com/developer-guide/setup/docker/)：

```bash
docker pull ghcr.io/synocommunity/spksrc
docker run -it --platform=linux/amd64 \
  -v "$(pwd):/repo" -w /repo \
  ghcr.io/synocommunity/spksrc \
  /repo/scripts/build-openlist.sh
```

构建产物路径依 spksrc 输出而定；CI 仅上传 artifact，**不**发 Release。

## 维护约定

见 [AGENTS.md](AGENTS.md)。

## 许可证与归属

见 [docs/licenses/THIRD_PARTY_NOTICES.md](docs/licenses/THIRD_PARTY_NOTICES.md)。