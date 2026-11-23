# OpenList 套件升级说明

## 范围

- 目标机型：**DS918+**（`apollolake` / x86_64）
- 目标系统：**DSM 7.3**
- 应用版本：**OpenList v4.2.10**（本仓库 overlay；非 SynoCommunity 官方源同步版本）

## 原则

1. **原地升级**：不卸载、不删除 `/var/packages/openlist/var/` 数据目录。
2. **保留配置**：升级前通过 `service_save` 备份 `config.json` 及数据库相关文件，升级后 `service_restore` 写回。
3. **迁移**：OpenList v4.2.10 **无** `openlist migrate` 子命令（`cmd/` 仅含 `server`、`admin` 等）；数据库与配置补丁在 **`openlist server` 启动时**由 `bootstrap.Init()` 完成。升级钩子只负责配置/数据保留与 DSM 端口元数据对齐。
4. **端口策略（上游 5244）**：与上游 OpenList / spksrc `SERVICE_PORT` 一致，套件对外宣告与 DSM 集成文件固定为 **5244**。本包**不会**把 DSM 元数据改写为 `config.json` 中的非 5244 `scheme.http_port`。

## 端口与 DSM 元数据

| 来源 | 端口 | 说明 |
| --- | --- | --- |
| `SERVICE_PORT` / `ADMIN_PORT`（INFO，构建期） | 5244 | spksrc 在编译 SPK 时生成 `app/config`、`app/openlist.sc`、`INFO` |
| `config.json` → `scheme.http_port` | 5244（新装模板） | OpenList **进程监听**端口；升级时由 `service_restore` 保留已有值 |
| 运行时同步（本 overlay） | **5244（固定）** | `openlist_sync_dsm_port_metadata` 幂等对齐 `app/config`、`*.sc`、`INFO adminport` 到上游端口 |

### 与既有部署的关系

若某台 NAS 上 **早已存在** 非 5244 的 `http_port`（历史手工或旧策略所致），安装/升级本包会**保留**该 `config.json`，但 DSM 集成层会对齐 **5244**。本仓库**不包含**把运行中实例迁移到 5244 或反向统一端口的操作说明；此类真机存量部署不在本 PR 范围内。

### 平台依据与剩余边界

- **构建期机制**（spksrc）：`SERVICE_PORT` 生成 DSM7 的 `app/$(SPK_NAME).sc` 与 `app/config`；`ADMIN_PORT` 写入 INFO。spksrc 无运行时从 `config.json` 重算这些文件的 API。
- **本 overlay**：在 `service_postinst`、`service_postupgrade`、`service_prestart` 调用 `openlist_sync_dsm_port_metadata`，将集成文件维持在 **5244**（`OPENLIST_DSM_SERVICE_PORT`）。若 `config.json` 监听端口与 5244 不一致，脚本会打印提示，**不**按运行时端口改写 DSM 文件。
- **无法在套件脚本中保证的部分**（需 NAS 实测）：DSM 是否立即刷新已登录会话中的套件中心 UI、防火墙 daemon 是否无需额外动作即重载规则。若 UI 仍显示旧端口，停止并重新启动套件或重新登录 DSM 后再试。

### 自动化测试说明

| 脚本 | 环境 |
| --- | --- |
| `scripts/test-port-sync.sh` | **模拟**（5244 固定、config 非 5244 时不追随、幂等） |
| `scripts/test-upgrade-preservation.sh` | **模拟**（升级备份/恢复 + DSM 回 5244） |
| `scripts/test-migrate-failure-sim.sh` | **模拟**（缺少 config 时 postupgrade 失败但 data 仍在） |
| DSM 真机图标/防火墙即时生效 | **未测**（需维护者另行授权 NAS） |

## 推荐步骤（人工 DSM）

1. 在 DSM 中停止 OpenList 套件（可选，降低迁移窗口风险）。
2. 备份 `/var/packages/openlist/var/`（至少 `config.json`、`data.db*`、`bleve/`）。
3. 上传并安装本仓库构建的 SPK（版本高于当前安装包）。
4. 启动套件，确认 OpenList 行为与备份时期望一致。
5. 查看日志：`/var/packages/openlist/var/log/log.log`。

## 失败处理

- 首次启动新版 `server` 若迁移/启动失败：保留备份，在 DSM 日志或 `/var/packages/openlist/var/log/` 排查后再试；勿在未备份时安装更旧 SPK。
- 配置缺失：`validate_preupgrade` 会阻止升级继续，以避免空配置覆盖。