# AGENTS.md — 维护约定

供人类与自动化 Agent 在本私有仓库协作时使用。

## 仓库范围

本仓库除配方外，还包含 **`packages/*/overlay`**、**`docs/`**（含 GitHub Pages 套件目录 `docs/packages.json`）及 CI 构建脚本。`master` 是活跃主干，不是「仅保留简短 README 的最小基线」。详细目录与发布说明见 [docs/package-source.md](docs/package-source.md)。

## 提交信息

采用 [Conventional Commits](https://www.conventionalcommits.org/) 简要形式，例如：

- `feat(openlist): bump upstream digest for v4.2.10`
- `feat(easytier): bump package revision for 2.7.0-11`
- `fix(openlist): preserve config on upgrade when temp backup missing`
- `docs: clarify DSM INFO port limitation`
- `ci: pin actions and split static checks from spk build`

## 拉取请求

- 默认 **草稿 PR** 审阅；合入 `master` 需维护者明确授权。
- 不在 PR 中合并、打 tag、发 Release、上传可安装 SPK 到公开渠道，**除非**维护者在本轮对话中明确授权。
- 配方、脚本、`docs/packages.json` 与 Pages 相关变更均在 PR 分支完成，经审阅后合入 `master`。

## 发布与部署（禁止自动化）

以下操作 **必须** 由用户显式授权后人工执行，Agent 不得擅自进行：

- 合并 PR、创建/编辑 GitHub Release、将 Release 标为 **latest/stable**
- 推送或合并会改变线上 **`docs/packages.json`** 的变更（套件目录 / GitHub Pages）
- 在 NAS 上安装 SPK、开启生产 SSH、访问生产凭据或修改生产 `config.toml`
- 修改仓库可见性或协作者权限

## OpenList 专用

- 上游基线：`packages/openlist/upstream.lock.json` 中的 `spksrc` commit 与 OpenList 版本为唯一真相来源。
- 修改版本时同步：`overlay/**/digests`、`upstream.lock.json`、`scripts/verify-upstream-digests.sh` 可验证性。
- 不得将静态检查或未跑过的构建描述为「已在 DSM 真机验证」。
- **本回合 EasyTier 工作时不得改动** OpenList 配方、`docs/packages.json` 中 OpenList 条目或 OpenList 专属文档（除非任务明确要求）。

## EasyTier 专用

### 代码与文档位置

| 用途 | 路径 |
| --- | --- |
| 配方 overlay | `packages/easytier/` |
| 运维说明 | `docs/easytier/`（privilege/TUN、升级、全新安装） |
| caphelper 源码 | `packages/easytier/overlay/cross/caphelper/src/caphelper.c` |
| privilege 模板 | `packages/easytier/overlay/spk/EasyTier/src/conf/privilege` |
| 生命周期脚本 | `packages/easytier/overlay/spk/EasyTier/src/service-setup.sh` |
| 本地/CI 构建 | `./scripts/build-easytier.sh` |

权威行为以源码与 `docs/easytier/` 为准；历史排错可参考 PR #16–#21（2.7.0-6 至 2.7.0-10 链）。

### 当前发布口径（维护者人工更新）

- 线上目录示例版本：**2.7.0-10**（GitHub **prerelease**，**非** latest/stable）。
- CI 绿 ≠ DSM 真机验收：artifact 或脚本通过 **不** 能写成「已在 NAS 验证 mesh/TUN」。

### 打包与 privilege（避免 319 与无效 cap）

1. **禁止** 在 `conf/privilege` 的 `tool[]` 里给 `easytier-core` 写 `capabilities`：未签名 SPK 会触发 DSM **错误 319**。
2. **唯一接受** 的 privilege 条目：`bin/helper/caphelper`，`user: root`，`group: package`，`permission: **4550**`（setuid-root 辅助程序，**非** setgid）。
3. **禁止** 对 `easytier-core` 做 setuid-root；**禁止** 把 `setcap` / `setfattr` / 手工 `chmod` 当作正式安装路径。
4. File cap 由 caphelper 在每次 `service_prestart` 写入 `easytier-core` 的 `security.capability` xattr。须为 Linux **VFS cap v2**（**20 字节、小端**）。`cap_net_admin,cap_net_raw+ep` 的已验证十六进制为：  
   `0100000200300000000000000000000000000000`  
   12 字节大端「镜像」无效：`fsetxattr` 在 DSM 7.3 仍可能返回成功，但 `+ep` 与 permitted 集可能错误（如误含 `CAP_SYS_ADMIN`），TUN 实际不可用。拒绝短/非 v2 blob 的内核会直接失败并中止启动。见 `scripts/test-easytier-cap-blob.sh`。
5. caphelper 打开套件目录：勿对 `/var/packages/EasyTier/target` **符号链接** 使用 `open(..., O_NOFOLLOW)`（会 **ELOOP** → `open_target`）。应对 `realpath` **结果路径** 再 `open` 目录（见 caphelper `main`）。
6. **4550 仅 setuid**：`setresuid(0,0,0)` 后 **egid 仍可能为套件组**。在创建 `/dev/net` 或 `mknod /dev/net/tun` 前必须 `setgroups(0,NULL)` 与 `setresgid(0,0,0)`，否则目录/节点为 `root:<package>`，`st_gid != 0` 检查失败（`dev_net_owner` 等），TUN 无法就绪。实现须包含 `grp.h` 等头文件。
7. `chmod 0666` 后须 `usleep(TUN_MODE_STICK_USEC)`（100000 µs）并确认模式仍为 **0666**，否则重试（见 caphelper `ensure_tun_world_rw_settled`）。

细节与威胁模型：[docs/easytier/privilege-and-tun.md](docs/easytier/privilege-and-tun.md)。

### 配置与升级

- 运行配置：**`/var/packages/EasyTier/var/config.toml`**（同 `@appdata/EasyTier/config.toml`）。**就地升级必须保留**，禁止覆盖用户配置。`service-setup.sh` 在 `UPGRADE` 时 `service_save` / `service_restore`；缺配置时 `validate_preupgrade` 中止。
- 全新安装可复制套件内注释模板；仅注释无有效键时 **不得启动**（避免上游默认组网）。
- 升级前维护者应保留：上一版 SPK、配置摘要（**仅文档中写 hash**，勿提交密钥/`network_secret`/peer URI/instance ID）、上一版已施 cap 的二进制备份。

见 [docs/easytier/upgrade.md](docs/easytier/upgrade.md)、[docs/easytier/fresh-install-restore.md](docs/easytier/fresh-install-restore.md)。

### DSM 安装与验证（人工，Agent 默认不执行）

**官方路径**：`sudo -n /usr/syno/bin/synopkg install <path/to.spk>`（全新安装或就地升级），再用 **`sudo -n /usr/syno/bin/synopkg start|stop|status EasyTier`**。

| 陷阱 | 说明 |
| --- | --- |
| 无密码 sudo 范围 | 生产上常见仅为 `synopkg` 与受限 `bash -c`；**勿**假设 `sudo -n /bin/rm` 可用。 |
| `synopkg status` 未 sudo | 可能误报 EasyTier **stopped** 或其它套件 **non_installed**。 |
| SSH / 传包 | 经 **跳板机** 再 NAS **内网 SSH**；Synology SSH **可能无 SFTP**。优先在跳板机 **直链下载** Release SPK，再 scp 到 NAS；**两侧校验 hash** 后再安装。 |
| 升级期间 overlay VIP | mesh 可能中断；**勿依赖** EasyTier overlay 虚拟 IP 维持 SSH 完成升级。 |
| 生产 SSH | **勿** 为发版 newly 开启生产 SSH；无授权不得登录生产。 |
| 邻域隔离 | EasyTier 变更时 **勿** 改生产网络、重启 NAS、动其它套件（如 **OpenList**）。 |

**推荐顺序**：

1. 隔离 **Virtual DSM** + 非生产身份：`synopkg install` → 官方 **`start`**，确认 caphelper `RESULT=ok`、`STAGE=tun`、套件用户可 rw `/dev/net/tun`。
2. 测试机 **彻底清理**（卸载、清 appdata、关闭临时 SSH）。
3. 生产多为 **就地升级**（保留 config 与节点身份），非重装。验收：`config.toml` hash 不变、tun0/mesh 仍通（维护者记录，**勿写入仓库**）。

成功启动后可在 DSM 上只读检查：`var/caphelper.out`、`getcap` / `getfattr` 于 `easytier-core`、`ls -l /dev/net/tun`（文档中勿贴真实 IP/VIP/密钥）。

### 目录与 Release（人工）

1. GitHub **Release** 上传 SPK（tag 如 `easytier-2.7.0-10`）；**本仓库 Agent 不得** 创建 Release 或将某版本标为 stable/latest，除非明确授权。
2. 授权后由维护者编辑 **`docs/packages.json`**：仅更新 **EasyTier** 条的 `version`、`link`、`md5`、`sha256`、`size`。
3. Pages 发布来源：`master` / `docs`（Location：`https://herbertgao.com/synology-packages/packages.json`，见 [docs/package-source.md](docs/package-source.md)）。
4. 发布后验证 **live `packages.json` 返回 200**；目录 HTML 索引 **可能 503** 而 JSON 已更新——以 JSON 为准。

### 秘密与私有配置

- **禁止** 提交 `network_secret`、peer URI、instance ID、真实主机/IP/VIP、生产 SSH 密钥或完整 `config.toml`。
- 文档中只写通用流程与 **配置 hash**（由维护者在 PR 外保管）。

## GitHub Actions（`synology-packages-ci`）

- **触发**：`pull_request`（任意分支）与 **`push` 仅限 `master`**，避免同一提交同时跑 push + PR 两套重型任务。
- **`static-checks`**：每次工作流均执行（含仅改 `docs/`、`AGENTS.md`、`docs/packages.json`、图标的 PR）。
- **`spk-build`**：仅当变更触及 OpenList SPK 相关路径（`packages/openlist/**`、OpenList 构建脚本、共享 overlay 脚本 `scripts/apply-overlay.sh` / `patch-spksrc-local-publisher.sh`、或本 workflow）时执行。
- **`easytier-spk-build`**：仅当变更触及 EasyTier SPK 相关路径（`packages/easytier/**`、EasyTier 构建/报告/GLIBC 脚本、同上共享脚本、或本 workflow）时执行。
- 仅文档/目录类 PR 通常 **跳过** 两个 SPK 任务；请确保分支保护要求的是 **`static-checks`（必需）**，SPK 任务为按需或可选，以免 `skipped` 阻塞合入。

## 测试命令

```bash
./scripts/ci-run-checks.sh
# 可选（需 Docker + 长时间构建）：
./scripts/build-openlist.sh
./scripts/build-easytier.sh   # EASYTIER_BUILD_ARCHES 默认 apollolake；CI 含 kvmx64
```

EasyTier 相关静态检查包括 `scripts/test-easytier-privilege-schema.sh`、`scripts/test-easytier-cap-blob.sh` 等；完整 caphelper（TUN + setuid 施 cap）**需 DSM 或 root**。