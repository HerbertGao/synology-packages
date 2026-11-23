# EasyTier：DSM 权限与 TUN

## 背景

EasyTier 创建虚拟网卡并参与二层/三层组网，通常需要访问 **TUN** 设备及较高的网络栈权限。部分第三方 Synology 套件借助外部「权限管理」工具在启动时提权；**本仓库不采用该方案**，也不依赖 Simple Permission Manager 或第三方签名的启动包装脚本。

## 本 overlay 的做法

1. **`src/conf/privilege`（DSM 原生）**
   - 默认日常文件归属：`run-as: package`，专用账户名 **`EasyTier`**（与常见存量套件命名一致，便于就地升级时的目录属主延续）。
   - 通过 `ctrl-script` 将 **start / stop / status** 以及安装生命周期钩子声明为 **`run-as: root`**，由 DSM 权限模型在套件脚本执行时提权，而非外部 helper。

2. **启动前 TUN 准备（`service_prestart`）**
   - 若不存在 `/dev/net/tun`，尝试 `mknod` 创建字符设备，并可选 `modprobe tun`。
   - 若仍不可用，记录警告；不在此脚本中静默改用第三方 root 包装。

3. **与第三方的差异（刻意）**
   - 不复制 `.sig`、哈希钉扎的启动脚本或外部 SPM 依赖。
   - 不在 PR / 文档中记录具体 NAS 网络参数或配置秘密。

## 运维说明

- 在 Package Center 安装或升级时，DSM 会展示 privilege 声明；接受后方可由套件以 root 启动 `easytier-core`。
- 若主机禁用 TUN 或 `/dev/net/tun` 无法创建，需由 NAS 管理员在系统侧启用 TUN/相应内核模块后再启动套件。
- `easytier-web` / `easytier-web-embed` 已随官方 zip 安装至 `bin/`，但默认 **SERVICE_COMMAND 仅启动 `easytier-core`**（与仅运行 core 的常见部署一致）；需要 Web 控制台时请自行另行调用官方二进制。

## 诚实性说明

若未来 Synology 在某 DSM 版本进一步限制 `ctrl-script` 的 root 启动，可能需要在文档中补充等效的手工 privilege 步骤（spksrc 社区对 ntopng 等设备类套件亦有类似说明）。本 PR 以 DSM **7.3** 为目标，并以官方 privilege 元数据表达提权需求。