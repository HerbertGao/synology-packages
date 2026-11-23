# EasyTier：DSM 权限与 TUN

## 背景

EasyTier 创建虚拟网卡需要 **CAP_NET_ADMIN**（及通常的 **CAP_NET_RAW**）。本 overlay **不**使用 setuid-root、外部 Permission Manager，或安装脚本内 `setcap`。

官方机制见 [Privilege Config](https://help.synology.com/developer-guide/privilege/privilege_config.html)：`defaults.run-as: package` 为必需；可用 `tool[]` 在安装时为 `bin/easytier-core` 声明 `capabilities`（DSM ≥ 7.0-40656）；亦可用 `ctrl-script` 将 `start`/`stop`/`status` 设为 `root`（[Breaking Changes](https://help.synology.com/developer-guide/breaking_changes.html) 要求特权操作建议走 resource worker，但文档仍列出 `ctrl-script`）。

## 当前 overlay（2.7.0-5 起）

### `conf/privilege`

- `defaults.run-as: package`
- `username` / `groupname`: `EasyTier`
- **`tool`**：`bin/easytier-core`，`user`/`group` 为字面量 `package`，`capabilities`: `cap_net_admin,cap_net_raw`，`permission`: `0755`
- **无** `ctrl-script`、**无** `_comment` 等非文档键

### 运行时

- `SERVICE_USER = auto` → 进程以套件用户 **EasyTier** 运行，能力由 DSM 在安装时写入二进制 file capabilities。
- `service_prestart`：检查 `/dev/net/tun` 与 tun 驱动线索；**不**以 package 用户执行 `modprobe` / `mknod` / `chmod`（与 DSM 7 降权模型一致，避免假修复）。
- `service_postinst` / `service_postupgrade` / `service_prestart`：通过 `getcap` **警告**缺失的 cap，**不**在安装阶段中止（installer 以 package 身份运行，不能在此处 `setcap`）。

### 从零安装与恢复

见 [fresh-install-restore.md](./fresh-install-restore.md)。

## 错误 319（`invalid package privilege content`）— 证据边界

`last_stage: prepare_install` 表示 DSM 在校验**待装 SPK** 的 `conf/privilege`（或相关元数据）时失败，**不会**进入停服、解包或钩子执行。

| 证据来源 | 结论 |
| --- | --- |
| [Privilege Config](https://help.synology.com/developer-guide/privilege/privilege_config.html) | 非法 JSON、缺少 `defaults`、未知字段可导致 privilege 无效；`tool.capabilities` 为**文档支持**字段 |
| 本仓库 PR #9 / 2.7.0-2 | **`_comment` 与非规范键** → 319（已修复）；最小合法 privilege（仅 defaults + username + groupname）可通过 prepare_install |
| 用户 NAS 观测（DSM 7.3.2-86009，自 2.7.0-2 升级） | **2.7.0-3**（`ctrl-script` start/stop/status as root）→ 319；**2.7.0-4**（`tool` + capabilities，无 ctrl-script）→ 319；**全新安装 2.7.0-4 未测** |
| [Breaking Changes](https://help.synology.com/developer-guide/breaking_changes.html) | `synopkg install` 与 UI 安装约束一致 → **无公开文档**表明升级与全新安装使用不同的 privilege 校验器；**不能**从升级失败推断「全新安装一定成功或一定失败」 |
| 社区案例（如 gitea-spk 319） | 常见为 **缺少 `defaults` 或 username 为空**；与本 overlay 当前 JSON 形态不同 |

**未证实（本 agent 未在真机复现）：**

- DSM 7.3.2 是否对**侧载/非 Synology 官方** SPK 拒绝 `tool.capabilities` 或 `ctrl-script` root；
- 卸载重装是否消除 319；
- 319 是否仅由「旧版已装 privilege 与新版合并」触发（prepare_install 通常只读新 SPK，故该路径**缺日志支撑**）。

**本回合策略：** 保留文档化的 `tool` capabilities 路径；精简脚本中无法以 package 用户完成的 TUN 修补；**不宣称**已解决用户 NAS 上的 319。真机对照请用 [fresh-install-restore.md](./fresh-install-restore.md)。

## 与第三方的差异（刻意）

- 不嵌入 `.sig`、SPM 或仓库外的启动包装。
- 文档与 PR 不含 NAS 专有 IP、路径白名单或配置密钥。

## 诚实性说明

- CI：`test-easytier-privilege-schema.sh`、`test-easytier-cap-warn.sh`、`test-easytier-tun-readiness.sh` 等为**离线模拟**，不替代 DSM 安装。
- SPK 构建：`./scripts/build-easytier.sh` 未在本回合标注为已在 DSM 真机验收。
