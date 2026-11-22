# OpenList 套件升级说明

## 范围

- 目标机型：**DS918+**（`apollolake` / x86_64）
- 目标系统：**DSM 7.3**
- 应用版本：**OpenList v4.2.10**（本仓库 overlay；非 SynoCommunity 官方源同步版本）

## 原则

1. **原地升级**：不卸载、不删除 `/var/packages/openlist/var/` 数据目录。
2. **保留配置**：升级前通过 `service_save` 备份 `config.json` 及数据库相关文件，升级后 `service_restore` 写回。
3. **迁移**：升级完成后执行 `openlist migrate`；失败时脚本以非零状态退出，**不**自动回滚二进制（数据库可能已迁移）。

## 端口与 DSM 元数据

| 来源 | 默认端口 | 说明 |
| --- | --- | --- |
| `SERVICE_PORT` / `ADMIN_PORT`（INFO，构建期） | 5244 | spksrc `mk/spksrc.service.mk` 在**编译 SPK** 时生成 `app/config`、`app/openlist.sc`、`INFO` 默认值 |
| `config.json` → `scheme.http_port` | 5244（新装） | **OpenList 实际监听端口** |
| 运行时同步（本 overlay） | 读 `config.json` | `openlist_sync_dsm_port_metadata` 在安装/升级/启动后写回 `target/app/config`、`*.sc`、`/var/packages/openlist/INFO` 的 `adminport` |

### 平台依据与剩余边界

- **构建期机制**（官方/spksrc）：`SERVICE_PORT` 生成 DSM7 的 `app/$(SPK_NAME).sc`（`dst.ports`）与 `app/config` 的 `port` 字段；`ADMIN_PORT` 写入 INFO（见 `mk/spksrc.spk.mk`、`mk/spksrc.service.mk`）。spksrc **没有**在运行时从 `config.json` 重算这些文件的 API。
- **本仓库替代设计**：在 `service_postinst` / `service_postupgrade` / `service_poststart` 调用 `openlist-dsm-port-sync.sh`，按 `scheme.http_port` 幂等更新上述文件；升级仍由 `service_save`/`service_restore` 保留自定义端口（含 5255）。
- **仍无法在套件脚本中保证的部分**（需 NAS 实测）：DSM 是否立即刷新已登录会话中的套件中心 UI、以及防火墙 daemon 是否无需额外 `synopkg` 动作即重载规则。文件内容与 OpenList 监听端口对齐；若 UI 仍显示旧端口，停止并重新启动套件或重新登录 DSM 后再试。

### 自动化测试说明

| 脚本 | 环境 |
| --- | --- |
| `scripts/test-port-sync.sh` | **模拟**（假 `app/`、`INFO` 树 + python3） |
| `scripts/test-upgrade-preservation.sh` | **模拟**（升级备份/恢复 + 端口同步） |
| `scripts/test-migrate-failure-sim.sh` | **模拟**（migrate 失败退出、数据仍在） |
| DSM 真机图标/防火墙即时生效 | **未测**（需用户另行授权 NAS） |

## 推荐步骤（人工 DSM）

1. 在 DSM 中停止 OpenList 套件（可选，降低迁移窗口风险）。
2. 备份 `/var/packages/openlist/var/`（至少 `config.json`、`data.db*`、`bleve/`）。
3. 上传并安装本仓库构建的 SPK（版本高于当前安装包）。
4. 启动套件，确认监听端口与升级前一致。
5. 查看日志：`/var/packages/openlist/var/log/log.log`。

## 失败处理

- `openlist migrate` 失败：保留备份，勿再次安装旧版 SPK 除非已确认数据库可回退。
- 配置缺失：`validate_preupgrade` 会阻止升级继续，以避免空配置覆盖。