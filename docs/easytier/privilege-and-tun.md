# EasyTier：DSM 权限与 TUN

## 背景

EasyTier 创建虚拟网卡并参与二层/三层组网，通常需要访问 **TUN** 设备及较高的网络栈权限（创建 TUN 接口需要 **CAP_NET_ADMIN**（以及常见地 **CAP_NET_RAW**）；仅打开已有的 `/dev/net/tun` 字符设备对非特权用户往往不够）。部分第三方 Synology 套件借助外部「权限管理」工具在启动时提权；**本仓库不采用该方案**，也不依赖 Simple Permission Manager 或第三方签名的启动包装脚本。

在 DSM 7.3 上，`synopkg prepare_install` 会对 SPK 内 `conf/privilege` 做 schema 校验；**非文档字段（例如 `_comment`）会导致错误 319（invalid package privilege content）**。已发布 **2.7.0-1** 因 privilege 含 `_comment` 且缺少显式 `groupname` 而在部分 7.3.2 主机上安装失败。

**2.7.0-2** 采用仅 `defaults.run-as: package` 的 privilege，安装可通过，但 `easytier-core` 以套件用户运行时创建 TUN 接口会报 `Operation not permitted (os error 1)`（属 TUNSETIFF / 能力问题，而非单纯打开设备节点的 EACCES）。

**2.7.0-3** 尝试在 `ctrl-script` 中将 `start` / `stop` / `status` 声明为 `run-as: root`；在 DSM 7.3 上 **`prepare_install` 返回错误 319**，系统日志亦可能提示 `ctrl-script and executable section should not exist`，Package Center 亦会拒绝不能以 root 运行的套件。因此 **不使用 `ctrl-script` 或 `executable` 段**。

## 本 overlay 的做法（2.7.0-4 起）

1. **`src/conf/privilege`（DSM 原生）**
   - `defaults.run-as: package`，专用账户 **`username` / `groupname` 均为 `EasyTier`**。
   - **`tool` 数组**：对 `bin/easytier-core` 声明 `user` / `group` 为字面量 **`package`**，`capabilities` 为 **`cap_net_admin,cap_net_raw`**（按 [Synology 文档](https://help.synology.com/developer-guide/privilege/privilege_config.html) **不得**包含 `+-=eip` 等后缀符号），并设置 `permission`（例如 `0755`）。DSM 在安装/解包阶段负责将文件能力应用到二进制（参见 [Privilege 概述](https://help.synology.com/developer-guide/privilege/preface.html) 中 “Control file capabilities in package.tgz”）。
   - **不包含** `ctrl-script`、`executable`、`_comment`。
   - **不在** `postinst` / `postupgrade` 中调用 `setcap`：在 `defaults.run-as: package` 且安装钩子以套件用户执行时（例如日志出现 `USER=EasyTier`），`setcap` 需要 **CAP_SETFCAP**，失败会导致安装/升级异常；官方文档亦指出安装脚本非零返回可能导致套件状态损坏。

2. **安装/升级后的能力自检（仅警告）**
   - `service_postinst` / `service_postupgrade` 在可用时以 `getcap` 检查 `easytier-core` 是否带有 `cap_net_admin` / `cap_net_raw`；缺失时 **打印 Warning，不 `exit 1`**。
   - **残余风险（未在本仓库 SPK 上逐台证明）**：部分环境下，**非 Synology 官方签名 / 侧载安装** 的套件，DSM 可能 **不** 完全依照 privilege `tool.capabilities` 落盘；管理员可能在升级后需自行以 root 对二进制执行 `setcap`。本 overlay **不** 将 postinst 中的失败 `setcap` 作为修复手段。

3. **启动前 TUN 准备（`service_prestart`，以套件用户执行）**
   - 先 `modprobe tun`（失败可忽略），再用 **`/sys/class/misc/tun`**、**`/sys/module/tun`** 或 **`/proc/modules`** 确认驱动存在。
   - 若 **`/dev/net/tun` 已存在** 且驱动就绪：**不**修改已有节点的权限；仅校验当前套件用户对该字符设备 **可读且可写**，不满足则失败并提示。
   - 仅当驱动存在且设备仍缺失时才 `mknod`；新建节点使用 **`root:root` + mode `0666`**（与部分 DSM 7.3 主机上系统创建的 `0666` 节点一致），**不**在 fallback 中设为 `0600`（非 root 的 `prestart` 亦无法 `chmod` 已有 root 节点）。
   - 仅有 mknod 而无驱动证据时启动失败。

4. **实际运行身份**
   - `SERVICE_USER = auto`；**`easytier-core` 以 EasyTier 套件用户运行**，TUN 接口创建依赖 privilege **`tool` 声明的文件能力**（及上文的侧载残余风险）。
   - 真机观测（2.7.0-2）：`/dev/net/tun` 可为 `0666`，在二进制具备能力后套件用户可成功创建 TUN，**未必**需要改动设备节点权限。
   - **2.7.0-4 尚未在 NAS 上完成本 revision 的端到端安装验收**（诚实性说明）。

5. **刻意不采用**
   - `chmod u+s` / setuid-root 替代文件能力。
   - `ctrl-script` / `executable` 提权。
   - 在 `service_prestart` 中假定 root 去 `chmod` TUN 节点。

## 运维说明

- Package Center 安装/升级时展示 privilege（含 `tool` 能力声明）；接受后启动套件。
- 若 TUN 启动失败且日志提示 EPERM，检查 `getcap` 输出是否含 `cap_net_admin`；侧载场景下可按 DSM/Linux 惯例在升级后手动 `setcap`（需 root）。
- 若日志提示 TUN 设备对套件用户不可读写，在系统侧调整 `/dev/net/tun` 权限或使用系统默认节点，勿依赖套件以非 root 身份收紧为 `0600`。

## 诚实性说明

CI：`scripts/test-easytier-privilege-schema.sh` 校验 privilege（含必需 `tool`、禁止 `ctrl-script`/`executable`）；`scripts/test-easytier-cap-warn.sh` 校验安装钩子 **警告但不中止**；`scripts/test-easytier-tun-readiness.sh` 覆盖 TUN 就绪逻辑。**不保证**每台 DSM 真机已验证 2.7.0-4。