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
| `SERVICE_PORT` / `ADMIN_PORT`（INFO） | 5244 | 编译期写入套件元数据 |
| `config.json` → `scheme.http_port` | 5244（新装） | **运行时真实监听端口** |
| DSM 防火墙（`openlist.sc` 等） | 通常跟随 INFO 默认 | 自定义端口需手动放行 |

若用户已将 `http_port` 改为非 5244（例如 5255），**升级会保留该值**，但 Package Center 的「打开」链接与 INFO 中的 `adminport` **不会**自动改为自定义端口。这是 DSM 静态元数据与运行时配置分离的已知取舍，不能伪造为「全自动一致」。

## 推荐步骤（人工 DSM）

1. 在 DSM 中停止 OpenList 套件（可选，降低迁移窗口风险）。
2. 备份 `/var/packages/openlist/var/`（至少 `config.json`、`data.db*`、`bleve/`）。
3. 上传并安装本仓库构建的 SPK（版本高于当前安装包）。
4. 启动套件，确认监听端口与升级前一致。
5. 查看日志：`/var/packages/openlist/var/log/log.log`。

## 失败处理

- `openlist migrate` 失败：保留备份，勿再次安装旧版 SPK 除非已确认数据库可回退。
- 配置缺失：`validate_preupgrade` 会阻止升级继续，以避免空配置覆盖。