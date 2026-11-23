# EasyTier 升级与配置保留

本 overlay 套件在 DSM 7.3 / `apollolake` 上打包官方 GitHub Release **v2.7.0** `easytier-linux-x86_64` zip，套件名为 **EasyTier**（与 `@appdata/EasyTier` 路径一致，便于就地升级）。

## 配置路径

- 运行配置：`${SYNOPKG_PKGVAR}/config.toml`（即 `@appdata/EasyTier/config.toml`）
- 文件日志与 PID：同目录下 `EasyTier.log`、`EasyTier.pid`

## 升级行为

1. **已有 `config.toml` 绝不会被覆盖。** `service-setup.sh` 在 `UPGRADE` 时通过 `service_save` / `service_restore` 将现有 `config.toml` 移入临时升级目录再写回。
2. 打包在 `target/var/config.toml` 的模板仅供**全新安装**且 var 目录尚无配置时使用；升级路径不依赖该模板。
3. 若升级前缺少 `config.toml`，`validate_preupgrade` 会中止升级，避免用空模板替换用户数据。

## 全新安装

- 首次安装且 var 中无 `config.toml` 时，从套件内模板复制一份**仅含注释**的最小 `config.toml`（不含 `network_name`、密钥或监听地址）。
- 套件仍为 **可启动**（`STARTABLE=yes`），但在 `config.toml` 仍为注释模板或未写入任何有效键值前，**启动会在 `service_prestart` 中止**，并提示先编辑 `${SYNOPKG_PKGVAR}/config.toml`。这样可避免 `easytier-core` 套用上游默认组网参数（例如默认 `network_name` 与 `0.0.0.0:11010` 监听）。
- 配置完成后即可从套件中心正常启动；就地升级且已存在真实用户配置的实例不受影响。

## 权限与 TUN

见 [privilege-and-tun.md](./privilege-and-tun.md)。

## 未在仓库内验证项

- 未在真实 NAS 上安装或升级（见 AGENTS.md）。
- 更广架构与 DSM 版本不在本回合范围。