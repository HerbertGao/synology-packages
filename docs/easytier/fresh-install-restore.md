# EasyTier：从零安装与配置恢复

面向「卸载旧版 → 全新安装 → 恢复相同组网身份」的通用流程。**本仓库不在此环境执行 NAS 操作**；下列清单供管理员在 DS918+（`apollolake`、DSM 7.3.x）或同类 x86_64 主机上自行验证。

## 为何可能需要从零安装

- 就地升级在 `prepare_install` 阶段若返回 **319**（`invalid package privilege content`），安装程序**不会**停服或解包；见 [privilege-and-tun.md](./privilege-and-tun.md) 中的 319 证据说明。
- 卸载会清除套件私有数据目录（`@appdata/EasyTier`，即 `SYNOPKG_PKGVAR`）；**仅备份 `config.toml` 不足以保证 cap 与目录一并恢复**。

## 安装前备份（离线、脱敏）

在 NAS 或已从 NAS 拷出的副本上保留：

| 项目 | 路径或命令 | 用途 |
| --- | --- | --- |
| 运行配置 | `/volume*/@appdata/EasyTier/config.toml` | 节点 hostname、`instance_id`、监听、peer、密钥等 |
| 可选日志 | 同目录 `EasyTier.log` | 排错，非恢复必需 |
| 套件元数据 | 套件中心显示版本；或 `synopkg version EasyTier` | 记录升级前版本 |
| 文件能力快照 | `getcap /var/packages/EasyTier/target/bin/easytier-core` | 卸载后旧 cap 会丢失；用于对比新安装是否由 `privilege` `tool` 自动施加 |
| 权限声明 | 待装 SPK 内 `conf/privilege`（或发行说明） | 对照 DSM 安装向导中的权限提示 |

**不要**将含密钥或内网地址的配置提交到公开仓库或 PR。

## 从零安装步骤

1. **停止**旧版 EasyTier（若仍可操作）。
2. **完成上表备份**并确认备份可读。
3. 在套件中心 **卸载** EasyTier（接受 `@appdata/EasyTier` 可能被删除）。
4. **安装**新版 SPK（侧载或自建 catalog；接受第三方开发者提示）。
5. 安装完成后查看套件日志 / `synopkg` 输出中的 **getcap 警告**（见 `service_postinst`）。
6. **恢复配置**：将备份的 `config.toml` 写回 `@appdata/EasyTier/config.toml`（全新安装后目录由 DSM 重建）。
7. **核对能力**（不把手工作为默认流程，仅作验收）：
   ```bash
   getcap /var/packages/EasyTier/target/bin/easytier-core
   ```
   期望包含 `cap_net_admin`、`cap_net_raw`（若为空，启动可能仍失败；见诚实性说明）。
8. **启动**套件；确认 `easytier-core` 常驻、虚拟接口与 mesh 与升级前一致。

## 失败与回滚边界

| 现象 | 可能原因 | 建议 |
| --- | --- | --- |
| `prepare_install` **319** | SPK 内 `conf/privilege` 未通过 DSM schema/策略校验 | 保留 SPK 与 `synopkg` JSON 结果；对照 [Privilege Config](https://help.synology.com/developer-guide/privilege/privilege_config.html)；**不能**假定卸载重装一定消除 319 |
| 启动前提示未配置 | `config.toml` 仍为注释模板 | 写入有效键值后再启动；包**不会**自动生成 `instance_id` 或密钥 |
| TUN / EPERM | `easytier-core` 无 file capabilities 或主机无 `/dev/net/tun` | 查 `getcap` 与 `/dev/net/tun`；启用 TUN 模块 |
| 配置丢失 | 卸载前未备份或写回路径错误 | 从离线备份恢复；无法从包内模板推断原节点身份 |

## 与就地升级的差异

| 环节 | 就地升级 | 从零安装 |
| --- | --- | --- |
| `prepare_install` / privilege 校验 | 有（对用户观测：2.7.0-3/4 曾 319） | **应有相同校验**（[Breaking Changes](https://help.synology.com/developer-guide/breaking_changes.html)：`synopkg install` 与 UI 约束一致）；**全新安装 2.7.0-4+ 尚未在本环境真机证实** |
| `service_save` / `restore` | 保留 `config.toml`、可选日志 | 不适用；依赖人工恢复 |
| `validate_preupgrade` | 无 `config.toml` 则中止 | 不适用 |
| postinst 模板 | 不覆盖已有配置 | 无配置时仅复制**注释模板**并提示编辑 |

## 验证分层（避免误判）

- **CI / 本仓库脚本**：privilege JSON、钩子模拟、TUN 逻辑模拟 — **非 DSM**。
- **`./scripts/build-easytier.sh`**：产出 SPK — **未在本回合真机安装**。
- **NAS 套件中心 / `synopkg`**：唯一可确认 319、file capabilities 与 TUN 的层级 — **需管理员执行上述清单**。