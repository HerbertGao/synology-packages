# EasyTier：DSM 权限与 TUN

## 背景

EasyTier 创建虚拟网卡需要 **CAP_NET_ADMIN**（及通常的 **CAP_NET_RAW**）。本 overlay **不**使用 setuid-root、外部 Permission Manager，或安装脚本内 `setcap`。

## 机制选型（当前 overlay，2.7.0-5）

### 文档原文（可直接引用）

- [Privilege Config](https://help.synology.com/developer-guide/privilege/privilege_config.html)：`defaults.run-as: package`；`tool[]` 可含 `capabilities`（自 7.0-40656 起，字符串不含 `+-=eip`）。
- [Privilege 概述](https://help.synology.com/developer-guide/privilege/preface.html)：配置可控制 **package.tgz 内文件的 file capabilities**。
- [Breaking Changes](https://help.synology.com/developer-guide/breaking_changes.html)：**已移除** SPK 签名与 keyring/trust；非 Synology 套件安装时会**提示**（alert）。**未找到**「仅 Synology 可信身份可使用 `tool.capabilities`」的原文。
- 同上 Breaking Changes：特权操作建议通过 **resource worker** 完成；`ctrl-script` 仍在 Privilege Config 表中列出。

### 本仓库 `conf/privilege`

- `username` / `groupname`: `EasyTier`
- **`tool`**：`bin/easytier-core`，`capabilities`: `cap_net_admin,cap_net_raw`
- **无** `ctrl-script`

### 运行时（不宣称「TUN 已修好」）

- 进程目标身份：**EasyTier** 套件用户；cap 依赖 DSM 在**安装时**对二进制施加（非 postinst `setcap`）。
- `service_prestart`：**只读诊断** — 是否存在 **字符设备** `/dev/net/tun`、当前执行上下文是否 **可读可写**；**不** `modprobe` / `mknod` / `chmod`。通过≠ TUN 接口创建一定成功（仍取决于 cap 与内核）。
- `getcap`：**警告**缺失 cap，不中止安装。

详见 [fresh-install-restore.md](./fresh-install-restore.md)。

## 错误 319 — 证据分层

`prepare_install` + 319：**未**进入停服/解包。

| 类型 | 内容 |
| --- | --- |
| **文档 + 仓库已证实** | 非法 privilege 键（如 `_comment`）→ 319（#9 / 2.7.0-2 对照） |
| **用户 NAS 观测** | 2.7.0-2 → 2.7.0-3（ctrl-script root）319；2.7.0-2 → 2.7.0-4（tool caps）319；**全新安装 2.7.0-4+ 未测** |
| **合理推断（非原文）** | Breaking Changes 写 UI 与 `synopkg install` 约束一致 → 可能共享安装门槛；**不能**据此证明 upgrade/install 在 `prepare_install` 上逐步相同 |
| **检索结论（本回合）** | Developer Guide **无**侧载 SPK 禁用 `tool.capabilities` 的明确条款；**319 根因仍未定位**，**不宣称** 2.7.0-5 已解决 |
| **未证实** | 卸载重装消除 319；仅 Synology 包可施加 cap；旧 privilege 残留触发校验 |

**策略**：维持文档化 `tool` caps + prestart 诊断；319 真机对照见恢复清单；**保持旧版在线**直至回滚材料齐套。

## 诚实性

- `scripts/test-easytier-*.sh`：离线模拟。
- 未在本回合将 DSM 真机安装标为已验收。