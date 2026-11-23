# EasyTier：DSM 权限与 TUN

## 背景

EasyTier 创建虚拟网卡并参与二层/三层组网，通常需要访问 **TUN** 设备及较高的网络栈权限（创建 TUN 接口需要相当于 **CAP_NET_ADMIN** 的权限，仅打开已有的 `/dev/net/tun` 字符设备对非特权用户往往不够）。部分第三方 Synology 套件借助外部「权限管理」工具在启动时提权；**本仓库不采用该方案**，也不依赖 Simple Permission Manager 或第三方签名的启动包装脚本。

在 DSM 7.3 上，`synopkg prepare_install` 会对 SPK 内 `conf/privilege` 做 schema 校验；**非文档字段（例如 `_comment`）会导致错误 319（invalid package privilege content）**。已发布 **2.7.0-1** 因 privilege 含 `_comment` 且缺少显式 `groupname` 而在部分 7.3.2 主机上安装失败。

## 本 overlay 的做法

1. **`src/conf/privilege`（DSM 原生）**
   - `defaults.run-as: package`，专用账户 **`username` / `groupname` 均为 `EasyTier`**（与 `@appdata/EasyTier` 及常见存量套件命名一致）。
   - **不包含** `_comment` 等非 schema 键。
   - **2.7.0-3** 起在官方文档允许的 `ctrl-script` 中声明 **`start` / `stop` / `status` → `run-as: root`**（**不**包含 `preinst` 等安装钩子）：未声明时 **2.7.0-2** 真机观测为 `easytier-core` 以 **EasyTier** 用户运行，`service_prestart` 可完成，但核心进程创建 TUN 时出现 `Operation not permitted (os error 1)` 并立即退出；`start` 提权后进程以 root 运行，故 **`stop` / `status` 亦需 root**，否则套件中心无法可靠停止或查询状态。
   - **不**恢复 **2.7.0-1** 中整段安装生命周期均以 root 运行的 `ctrl-script`（该形态与错误 319 同期出现；PR #9 已确认 319 的直接原因是 `_comment` 与缺失 `groupname`，安装/升级钩子仍走 `defaults.run-as: package`）。

2. **启动前 TUN 准备（`service_prestart`）**
   - 先 `modprobe tun`（失败可忽略：可能已加载或 built-in），再用 **`/sys/class/misc/tun`**、**`/sys/module/tun`** 或 **`/proc/modules`** 确认驱动存在。
   - 仅当驱动存在且设备仍缺失时才 `mknod`；**仅有 mknod 而无驱动证据时启动失败**。
   - 启动前已存在且可沿用的 `/dev/net/tun`（例如 built-in、modprobe 返回非零）仍视为就绪。
   - 设备节点权限为 `root:root` `0600`。
   - 就绪检查失败时 `service_prestart` **中止启动**（不 `|| true`）。

3. **实际运行身份（`start-stop-status`）**
   - `SERVICE_USER = auto`；在 **2.7.0-3** 的 privilege 下，**`start` 动作**由 DSM 以 **root** 执行生成的 `scripts/start-stop-status`，从而在同一启动流程内以 root 运行 `service_prestart` 与 **`SERVICE_COMMAND`（`easytier-core`）**，满足 TUN 接口创建权限。
   - **`stop` / `status`** 与 `start` 同为 root，以便管理 root 启动的 `easytier-core` 后台进程。
   - 真机验收：安装/升级后启动套件，确认 `easytier-core` 常驻、`tun` 接口存在且组网正常。

4. **与第三方的差异（刻意）**
   - 不复制 `.sig`、哈希钉扎的启动脚本或外部 SPM 依赖。
   - 不在 PR / 文档中记录具体 NAS 网络参数或配置秘密。

## 运维说明

- 在 Package Center 安装或升级时，DSM 会展示 privilege 声明（含 **以 root 启动服务**）；接受后方可启动套件。
- 若主机禁用 TUN 或 `/dev/net/tun` 无法创建，需由 NAS 管理员在系统侧启用 TUN/相应内核模块后再启动套件。
- `easytier-web` / `easytier-web-embed` 已随官方 zip 安装至 `bin/`，但默认 **SERVICE_COMMAND 仅启动 `easytier-core`**（与仅运行 core 的常见部署一致）；需要 Web 控制台时请自行另行调用官方二进制。

## 诚实性说明

CI 中的 `scripts/test-easytier-privilege-schema.sh` 会校验 privilege JSON 无未知顶层键、`username` / `groupname` / `defaults.run-as` 符合约定，并检查 **`ctrl-script` 仅含 `start`/`stop`/`status` 且均为 root**；**不保证**已在每一台 DSM 真机上完成安装与 TUN 验收。本 overlay 以 DSM **7.3** 为目标， privilege 形态以 [Synology Privilege Config](https://help.synology.com/developer-guide/privilege/privilege_config.html) 为准。