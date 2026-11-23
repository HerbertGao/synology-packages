# EasyTier：DSM 权限与 TUN

## 背景

EasyTier 创建虚拟网卡并参与二层/三层组网，通常需要访问 **TUN** 设备及较高的网络栈权限（创建 TUN 接口需要 **CAP_NET_ADMIN**（以及常见地 **CAP_NET_RAW**）；仅打开已有的 `/dev/net/tun` 字符设备对非特权用户往往不够）。部分第三方 Synology 套件借助外部「权限管理」工具在启动时提权；**本仓库不采用该方案**，也不依赖 Simple Permission Manager 或第三方签名的启动包装脚本。

在 DSM 7.3 上，`synopkg prepare_install` 会对 SPK 内 `conf/privilege` 做 schema 校验；**非文档字段（例如 `_comment`）会导致错误 319（invalid package privilege content）**。已发布 **2.7.0-1** 因 privilege 含 `_comment` 且缺少显式 `groupname` 而在部分 7.3.2 主机上安装失败。

**2.7.0-2** 采用仅 `defaults.run-as: package` 的 privilege，安装可通过，但 `easytier-core` 以套件用户运行时创建 TUN 接口会报 `Operation not permitted (os error 1)`。

**2.7.0-3** 尝试在 `ctrl-script` 中将 `start` / `stop` / `status` 声明为 `run-as: root`；在 DSM 7.3 上 **`prepare_install` 返回错误 319**，Package Center 亦会提示套件不能以 root 运行而拒绝安装/升级。因此 **不在 privilege 中通过 `ctrl-script` 做服务启动提权**。

## 本 overlay 的做法（2.7.0-4 起）

1. **`src/conf/privilege`（DSM 原生）**
   - `defaults.run-as: package`，专用账户 **`username` / `groupname` 均为 `EasyTier`**（与 `@appdata/EasyTier` 及常见存量套件命名一致）。
   - **不包含** `ctrl-script`、`_comment` 等非必需键；安装/升级生命周期钩子按 DSM 约定在 **root** 下执行，无需在 privilege 中声明。
   - **不**使用 `defaults.run-as: root` 或整段安装生命周期 root `ctrl-script`。

2. **安装/升级时文件能力（`service_postinst` / `service_postupgrade`）**
   - 在二进制解包后，对 **`${SYNOPKG_PKGDEST}/bin/easytier-core`** 执行 `setcap cap_net_admin,cap_net_raw+ep`。
   - 用 `getcap` 校验能力已生效；若找不到 `setcap`/`getcap` 或设置/校验失败，**安装/升级失败退出**（不静默留下会在启动时 TUN EPERM 的套件）。
   - 文件能力在 SPK 解包后需重新应用，故 fresh install 与 in-place upgrade 均调用同一逻辑。

3. **启动前 TUN 准备（`service_prestart`）**
   - 先 `modprobe tun`（失败可忽略：可能已加载或 built-in），再用 **`/sys/class/misc/tun`**、**`/sys/module/tun`** 或 **`/proc/modules`** 确认驱动存在。
   - 仅当驱动存在且设备仍缺失时才 `mknod`；**仅有 mknod 而无驱动证据时启动失败**。
   - 启动前已存在且可沿用的 `/dev/net/tun`（例如 built-in、modprobe 返回非零）仍视为就绪。
   - 设备节点权限为 `root:root` `0600`。
   - 就绪检查失败时 `service_prestart` **中止启动**（不 `|| true`）。

4. **实际运行身份（`start-stop-status`）**
   - `SERVICE_USER = auto`；在 **2.7.0-4** privilege 下，**`easytier-core` 以 EasyTier 套件用户运行**，依赖前述 **文件能力** 满足 TUN 接口创建权限。
   - 真机验收：安装/升级后启动套件，确认 `easytier-core` 常驻、`tun` 接口存在且组网正常。

5. **与第三方的差异（刻意）**
   - 不复制 `.sig`、哈希钉扎的启动脚本或外部 SPM 依赖。
   - 不在 PR / 文档中记录具体 NAS 网络参数或配置秘密。

## 运维说明

- 在 Package Center 安装或升级时，DSM 会展示 privilege 声明（套件以 **EasyTier** 用户运行）；接受后方可启动套件。
- 若主机禁用 TUN 或 `/dev/net/tun` 无法创建，需由 NAS 管理员在系统侧启用 TUN/相应内核模块后再启动套件。
- 若安装/升级因 `setcap` 失败而中止，请确认 DSM 上存在 `libcap` 提供的 `setcap`/`getcap`（常见路径 `/sbin/setcap`）。
- `easytier-web` / `easytier-web-embed` 已随官方 zip 安装至 `bin/`，但默认 **SERVICE_COMMAND 仅启动 `easytier-core`**（与仅运行 core 的常见部署一致）；需要 Web 控制台时请自行另行调用官方二进制。

## 诚实性说明

CI 中的 `scripts/test-easytier-privilege-schema.sh` 会校验 privilege JSON 无未知顶层键、**不得包含 `ctrl-script`**、`username` / `groupname` / `defaults.run-as` 符合约定；`scripts/test-easytier-setcap-hooks.sh` 校验 postinst/postupgrade 的 setcap 行为（含缺失 setcap 时失败退出）。**不保证**已在每一台 DSM 真机上完成安装与 TUN 验收。本 overlay 以 DSM **7.3** 为目标，privilege 形态以 [Synology Privilege Config](https://help.synology.com/developer-guide/privilege/privilege_config.html) 为准。