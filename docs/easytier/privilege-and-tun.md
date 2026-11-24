# EasyTier：DSM 权限、caphelper 与 TUN

## 背景

EasyTier 创建虚拟网卡需要 **CAP_NET_ADMIN** 与 **CAP_NET_RAW**。本 overlay **不**对 `easytier-core` 使用 setuid-root，**不**在安装脚本中调用 `setcap`，也不在 `conf/privilege` 里声明 `tool[].capabilities`（见下文 319）。

## 为何不用 `tool.capabilities`（2.7.0-6+）

在 **Virtual DSM 7.3.2-86009**（2026-11-24）上已验证：未签名 SPK 若在 `conf/privilege` 的 `tool[]` 中带有 `capabilities` 字段，Package Center / `synopkg` 会在安装准备阶段返回 **错误 319**（invalid privilege content）。2.7.0-4 / -5 使用 `capabilities: cap_net_admin,cap_net_raw` 时 **全新安装**即失败。

接受的替代方案：在 `tool[]` 中仅声明一个 **setuid-root 能力辅助程序**（`bin/helper/caphelper`，`user: root`，`group: package`，`permission: 4550`）。DSM 安装后将其设为 `root:<套件 gid>`、模式 `4550`；套件以 `run-as: package` 启动时，执行该辅助程序可获得有效 root。

`easytier-core` 本身保持普通套件用户文件（SPK 内 `0755`，运行前由 caphelper 调整为 `root:<gid>` `0750` 并附带 file cap）。**从不对 easytier-core 做 setuid。**

## TUN 与 Tailscale `configure-host`（2.7.0-7+）

在**原厂 DSM 7.3.2** 上常见现象：

- `tun` 内核模块**未加载**时无 `/dev/net/tun`；
- 即使加载后，devtmpfs 创建的节点常为 **root:root 0600**，套件用户无法 `open(O_RDWR)`。

主流发行版多为 **`/dev/net/tun` 0666**，因创建/附加 TUN 接口仍依赖 **CAP_NET_ADMIN**（`TUNSETIFF` 等），世界可读写节点并不等价于任意用户建 VPN。Tailscale 在 Synology 上以 root 运行 [`tailscale configure-host`](https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/configure-synology.go)（`configure synology`）创建 `/dev/net/tun` 并 `chmod 0666`，再对 `tailscaled` 施 cap。

本 overlay **2.7.0-7** 将等效步骤并入 **caphelper**（在施 cap **之前**、固定路径、无环境/参数注入）：

| 步骤 | 行为 |
| --- | --- |
| 1 | 仅当 `/proc/modules` 无 `tun ` **且** `/dev/net/tun` 不存在时，从 **`/lib/modules/tun.ko`** 加载（`finit_module` + 校验 root 拥有、常规文件、非 group/other 可写；失败则 `execve /sbin/insmod` 同一路径、空环境） |
| 2 | 确保 **`/dev/net`** 为 root:root **0755** 目录（`mkdir` + `lstat`，拒绝 symlink） |
| 3 | 缺失则 **`mknod`** `10:200`；已存在则 `lstat` 校验字符设备与 rdev，拒绝 symlink；**`fchownat` root:root**（`O_PATH\|O_NOFOLLOW`） |
| 4 | **`chmod 0666`**（`fchmodat`/`fchmod`）；`/dev/net` 目录同样 **root:root 0755** |

stdout 输出 **`EasyTierCapHelper: STAGE=tun loaded=... created=... mode=...`**，失败为 `RESULT=fail WHAT=...`。流程幂等。

`service_prestart` **先**跑 caphelper，**再**以套件用户做只读 TUN 可读写探测（不再在 prestart 里 `modprobe`/`mknod`/`chmod`）。

## 威胁模型（caphelper）

| 项 | 说明 |
| --- | --- |
| 入口 | 仅能通过 DSM 安装的 `4550` 辅助程序；`argc` 必须为 1（无参数）；`clearenv()`，不读取环境或命令行路径 |
| 权限 | `geteuid()==0` 后 `setresuid(0,0,0)`、**`setgroups(0,NULL)`**、**`setresgid(0,0,0)`**（4550 仅 setuid，否则 `mkdir`/`mknod` 会为 root:套件组）；`/proc/self/exe` 用 `open`+`fstat` 读取**磁盘上**辅助程序的套件 gid |
| 主机 TUN | 固定路径：`/lib/modules/tun.ko`、`/dev/net`、`/dev/net/tun`；禁止 symlink；模块路径不从 env/argv 读取 |
| 路径 | 固定 `/var/packages/EasyTier/target`（`realpath` + basename 校验）；目录遍历使用 `openat(O_DIRECTORY\|O_NOFOLLOW)` |
| 二进制 | 仅处理 `bin/easytier-core`：流式 SHA-256 必须等于 **构建时嵌入** 的哈希；先 `fchown` 再 `fsetxattr`；原子 `rename` |
| 幂等 | TUN 步骤与「已具备相同 caps 的 core」均可重复执行 |
| 日志 | `RESULT=ok\|fail WHAT=...`、`STAGE=tun ...`；套件写入 `var/caphelper.out`（非 Log Center） |

辅助程序 **不能** 修改任意路径、不能执行 shell、不接受参数；在主机侧仅配置 TUN 与套件 `target` 下的 `easytier-core` caps。

## 运行时流程（2.7.0-7）

1. 配置检查：`config.toml` 不得仅为注释模板。
2. **`env -i` 执行 caphelper**（TUN 准备 → 目录加固 → 施 cap），输出写入 `${SYNOPKG_PKGVAR}/caphelper.out`；失败则 **中止启动**。
3. **TUN 只读探测**：套件用户须能读写 `/dev/net/tun`（与 caphelper 的 `STAGE=tun` 对照）。
4. 以套件用户启动 `easytier-core -c ...`。

安装/升级：**不**在安装阶段施 cap；全新安装可复制 `var/config.toml` 模板。

## 在 DSM 上验证

```bash
stat /var/packages/EasyTier/target/bin/helper/caphelper
getcap /var/packages/EasyTier/target/bin/easytier-core
cat /var/packages/EasyTier/var/caphelper.out   # RESULT=ok 与 STAGE=tun ...
ls -l /dev/net/tun
```

## 错误 319 — 当前结论

| 类型 | 内容 |
| --- | --- |
| **已证实（Virtual DSM 7.3.2）** | 未签名 SPK + `tool[].capabilities` → 319；caphelper `4550` **可完成安装** |
| **本仓库策略** | `tool[]` 仅 caphelper，**无** `capabilities` 字段 |
| **未在本仓库 CI 验收** | 真机 mesh、长期升级链 |

静态检查：`scripts/test-easytier-privilege-schema.sh`；构建后 GLIBC：`scripts/test-easytier-glibc-max.sh`。

CI 产出 **apollolake** 与 **kvmx64** 两份 SPK。

详见 [fresh-install-restore.md](./fresh-install-restore.md)。

## 诚实性

- `scripts/test-easytier-*.sh` 为离线/主机模拟；完整 caphelper（TUN + setuid 施 cap）**需 DSM 或 root**；CI 对 `/proc/self/exe` 与 prestart 顺序做回归。
- CI 构建 SPK 上传 artifact，**不** 等同于已在你的 NAS 上验证 mesh。