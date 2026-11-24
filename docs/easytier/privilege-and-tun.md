# EasyTier：DSM 权限、caphelper 与 TUN

## 背景

EasyTier 创建虚拟网卡需要 **CAP_NET_ADMIN** 与 **CAP_NET_RAW**。本 overlay **不**对 `easytier-core` 使用 setuid-root，**不**在安装脚本中调用 `setcap`，也不在 `conf/privilege` 里声明 `tool[].capabilities`（见下文 319）。

## 为何不用 `tool.capabilities`（2.7.0-6+）

在 **Virtual DSM 7.3.2-86009**（2026-11-24）上已验证：未签名 SPK 若在 `conf/privilege` 的 `tool[]` 中带有 `capabilities` 字段，Package Center / `synopkg` 会在安装准备阶段返回 **错误 319**（invalid privilege content）。2.7.0-4 / -5 使用 `capabilities: cap_net_admin,cap_net_raw` 时 **全新安装**即失败。

接受的替代方案：在 `tool[]` 中仅声明一个 **setuid-root 能力辅助程序**（`bin/helper/caphelper`，`user: root`，`group: package`，`permission: 4550`）。DSM 安装后将其设为 `root:<套件 gid>`、模式 `4550`；套件以 `run-as: package` 启动时，执行该辅助程序可获得有效 root，由辅助程序对同目录下的 `easytier-core` 写入 `security.capability` xattr（VFS rev2：`cap_net_admin` + `cap_net_raw`，effective+permitted）。

`easytier-core` 本身保持普通套件用户文件（SPK 内 `0755`，运行前由 caphelper 调整为 `root:<gid>` `0750` 并附带 file cap）。**从不对 easytier-core 做 setuid。**

## 威胁模型（caphelper）

| 项 | 说明 |
| --- | --- |
| 入口 | 仅能通过 DSM 安装的 `4550` 辅助程序；`argc` 必须为 1（无参数）；`clearenv()`，不读取环境或命令行路径 |
| 权限 | 要求 `geteuid()==0` 后 `setresuid(0,0,0)`；通过 `open("/proc/self/exe")`+`fstat` 跟随 magic 链接，校验辅助程序本身属主为 root、组为套件组（**不得**对 `/proc/self/exe` 使用 `AT_SYMLINK_NOFOLLOW`，否则会读到 symlink 的 root:root） |
| 路径 | 固定 ` /var/packages/EasyTier/target`（`realpath` + basename 校验）；目录遍历使用 `openat(O_DIRECTORY\|O_NOFOLLOW)` |
| 二进制 | 仅处理 `bin/easytier-core`：流式 SHA-256 必须等于 **构建时嵌入** 的哈希；先 `fchown` 再 `fsetxattr`；原子 `rename` |
| 幂等 | 已具备相同哈希、owner、mode、xattr 时直接成功退出 |
| 日志 | 一行 stdout：`EasyTierCapHelper: RESULT=ok\|fail WHAT=...`；套件写入 `var/caphelper.out`（非 Log Center） |

辅助程序 **不能** 修改任意路径、不能执行 shell、不接受参数；仅能加固 `target` 下目录权限并对 **单一、哈希绑定的** `easytier-core` 施 cap。

## 运行时流程（2.7.0-6）

1. `service_prestart`：只读 TUN 检查（`/dev/net/tun` 字符设备 + 套件用户可读写）；不要求 `modprobe`/`mknod`/`chmod`。
   - 在**原厂 DSM 7.3.2** 上，`tun` 内核模块可能未加载（无 `/dev/net/tun`）；devtmpfs 在模块加载后也常创建 **root:root 0600** 节点，而本套件需要节点存在且对套件用户可读写（部分环境已为 0666）。若不满足，prestart 会明确失败（本 PR **不**改动 TUN 处理方式，仅记录观测）。
2. 配置检查：`config.toml` 不得仅为注释模板。
3. **`env -i` 执行 caphelper**，输出追加到 `${SYNOPKG_PKGVAR}/caphelper.out`；失败则 **中止启动**（无静默降级）。
4. 以套件用户启动 `easytier-core -c ...`（与既往相同）。

安装/升级：**不**在安装阶段施 cap；全新安装可复制 `var/config.toml` 模板，用户填入既有节点身份后启动。

## 在 DSM 上验证

```bash
# 辅助程序权限（安装后）
stat /var/packages/EasyTier/target/bin/helper/caphelper

# 核心二进制 cap（启动后）
getcap /var/packages/EasyTier/target/bin/easytier-core

# 最近一次 caphelper 结果
cat /var/packages/EasyTier/var/caphelper.out
```

## 错误 319 — 当前结论

| 类型 | 内容 |
| --- | --- |
| **已证实（Virtual DSM 7.3.2）** | 未签名 SPK + `tool[].capabilities` → 319；改用 caphelper `4550` **可被接受并完成安装** |
| **本仓库策略（2.7.0-6）** | 移除全部 `capabilities` 字段；仅 caphelper 一条 `tool` |
| **未在本仓库 CI 验收** | 真机 TUN 创建、mesh 组网、长期升级链 |

静态检查：`scripts/test-easytier-privilege-schema.sh`；构建后 GLIBC 版本门控：`scripts/test-easytier-glibc-max.sh`。

CI 产出 **apollolake**（DS918+）与 **kvmx64**（Virtual DSM 7.3.2 验证机）两份 SPK，上游二进制相同（官方 linux x86_64 zip）。

详见 [fresh-install-restore.md](./fresh-install-restore.md)。

## 诚实性

- `scripts/test-easytier-*.sh` 为离线/主机模拟；caphelper 主机测试 **不** 覆盖真实 setuid 施 cap（需 DSM）。
- CI 构建 SPK 上传 artifact，**不** 等同于已在你的 NAS 上验证 mesh。