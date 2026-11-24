# EasyTier：从零安装与配置恢复

面向「卸载旧版 → 全新安装 → 恢复相同组网身份」的**通用**清单。**本仓库不在此环境执行 NAS 操作**。

## 何时考虑从零安装

- 就地升级到新版 SPK 在 `prepare_install` 失败（例如 **319**）时，**旧版若仍在运行，应优先保持旧版在线服务**，继续用已验证可工作的安装路径（含你已接受的运维补偿，例如经授权的 `setcap`），而不是假设「只能卸载整机停机」。
- 若**必须**换 privilege 形态或重置 `/var/packages/EasyTier`，才进入卸载流程；且**只有**在回滚路径预检通过后才可卸载。

## 关键事实（影响备份范围）

| 事实 | 对备份的含义 |
| --- | --- |
| `getcap` 输出是**只读快照**，不能用来**还原** file capabilities | 2.7.0-6+ 在**首次启动**时由 `caphelper` 对 `easytier-core` 施 cap；须使用带 caphelper 的 SPK 并成功启动一次，而非仅抄二进制 |
| 复制 `easytier-core` 文件**不保证**携带扩展属性中的 cap（视文件系统/拷贝方式而定） | 须保留**当时可安装的 SPK** 或完整套件树，而非只抄二进制 |
| 卸载常删除 `@appdata/EasyTier` | 配置与日志须**在卸载前**离线保存 |
| `prepare_install` **319** 不会停服 | **无需**为 319 单独卸载；无回滚材料时**禁止**卸载 |

## A. 卸载前：完整材料（脱敏离线保存）

在**另一台机器或加密离线目录**保留下列项（路径以 DSM 默认为例，勿写入本机 IP / 密钥正文）：

### A1. 可回装的服务证据（**必需其一**）

- **当前已验证可工作的 SPK 文件**（例如仍在线的 2.7.0-2 构建物），含校验和（`sha256sum`）；或
- 从该 SPK 解出的 **`INFO` + `package.tgz` 内 `conf/privilege`**（`tar -xf … package.tgz conf/privilege`），用于确认 privilege 形态可再装。

> 没有「可再次安装且已知能跑 mesh」的旧 SPK / 等价物 → **不得卸载**。

### A2. 运行态目录快照（卸载会丢）

| 类别 | 路径（示例） | 说明 |
| --- | --- | --- |
| 用户配置 | `…/EasyTier/config.toml` | **必需**；恢复后做 `sha256` 与备份一致 |
| 可选日志 | 同目录 `EasyTier.log` | 排错用 |
| 套件变量树 | `/var/packages/EasyTier` 下 `etc`、`scripts`、`conf`（若存在） | privilege 安装结果、启动脚本 |
| 目标树元数据 | `/var/packages/EasyTier/target` 的 **`INFO`**（若存在） | 版本、维护者字段 |
| 权限诊断 | `getcap …/target/bin/easytier-core` 文本输出 | **仅对比**，不能当恢复源 |

### A3. 诊断记录（非恢复源，但排 319 / cap 用）

- `synopkg version EasyTier`、失败安装的 `synopkg` JSON（含 `last_stage`）
- 拟装新版 SPK 内 `conf/privilege` 副本

**禁止**将含密钥的 `config.toml` 提交公开仓库或 PR。

## B. 卸载前预检（全部满足再卸载）

1. **回滚 SPK** 可读，`sha256` 与记录一致，且管理员确认**可在本机侧载重装**（不要求此刻真装，但须有安装包与权限接受流程）。
2. **`config.toml` 备份**可读，`sha256` 已记录（例如 `sha256sum config.toml > config.toml.sha256`）。
3. **恢复演练（离线）**：在备份副本上执行 `sha256sum -c`；确认未误拷空文件。
4. **新版 SPK**（若目标为零从新版本安装）已在沙箱读过 `conf/privilege`；**不假设** 319 会消失。
5. 明确接受：2.7.0-6+ 依赖**首次成功启动**时 `caphelper` 施 cap；若 `caphelper.out` 非 `RESULT=ok`，需在排查前停止依赖 mesh 的服务。

任一不满足 → **停止**；保持旧版运行，收集 `synopkg` / `/var/log/synopkg.log` 再决策。

## C. 卸载与全新安装

1. 停止 EasyTier（若可操作）。
2. 再次确认 A/B 完成。
3. 卸载（接受 `@appdata/EasyTier` 可能被删）。
4. 安装目标 SPK（第三方提示；2.7.0-6 仅声明 caphelper `4550`，不含 `capabilities`）。
5. 启动前编辑 `config.toml`；首次启动后检查 `var/caphelper.out` 与 `getcap easytier-core`。

## D. 恢复配置与属主（不写死 UID）

1. 将备份 `config.toml` 写回 `${SYNOPKG_PKGVAR}/config.toml`（即 `@appdata/EasyTier/`）。
2. **属主**：改为套件账户名 **EasyTier**（`privilege` 中的 `username`，非数字 UID 硬编码），例如：
   ```bash
   chown EasyTier:EasyTier /path/to/@appdata/EasyTier/config.toml
   ```
   若本机用户名不同，以 `privilege` / `id EasyTier` 为准。
3. **权限**：建议 `0640` 或更严（仅套件用户可读）；与备份前 `stat` 记录对比，避免 world-readable 泄露。
4. **完整性**：`sha256sum -c` 与卸载前记录一致后再启动。
5. **能力验收**：`getcap …/easytier-core`；缺失时按 B.5 处理，**不要**假设立即可启动。

## E. 失败与回滚（非「永久离线」）

| 情况 | 动作 |
| --- | --- |
| 新 SPK `prepare_install` **319** | **未卸载前**：继续用旧版；**已卸载且无回滚 SPK**：用 A1 旧 SPK 重装，恢复 D，再评估 cap |
| 启动前 TUN / EACCES | 看 prestart 对 `/dev/net/tun` **类型 + rw** 的报错；修主机节点或 cap，脚本**不会** chmod 设备 |
| cap 未应用 | DSM 侧排查或授权 `setcap`；getcap 快照不能代劳 |
| 配置损坏 | 从离线备份重写；模板**不能**推断原 `instance_id` / 密钥 |

## F. 就地升级 vs 全新安装（校验层）

| 环节 | 就地升级 | 全新安装 |
| --- | --- | --- |
| 失败前是否可继续用旧服务 | 319 时通常**可以** | 仅当已完成 B 且卸载后 |
| `service_save` / `restore` | 保留 `config.toml`、可选日志 | 人工 D |
| postinst 模板 | 不覆盖已有配置 | 无配置时仅注释模板 |

**证据提示**：[Breaking Changes](https://help.synology.com/developer-guide/breaking_changes.html) **原文**：`synopkg install` 与 UI 安装有相同约束——这是**合理推断**「CLI 与 GUI 可能走同一套安装门槛」的依据，**并非**官方写明 `prepare_install` 在 upgrade 与 install 上逐步骤相同；二者是否共享**全部**校验项**仍未在公开文档中定位**。

## G. 验证分层

- **本仓库 `scripts/test-easytier-*.sh`**：离线 mock（含 TUN rw 探测）— 非 DSM。
- **SPK 构建**：未在本环境标注真机已验收。
- **NAS**：唯一可确认 319、cap 写入与 mesh 的层级。