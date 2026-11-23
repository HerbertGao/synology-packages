# OpenList 验收清单（草稿）

区分三类结果，避免把静态检查等同于真机兼容。

## 1. 静态 / 模拟（可在 CI 或开发机完成）

- [ ] `scripts/verify-upstream-digests.sh` 通过（官方发布物摘要与 `upstream.lock.json` 一致）
- [ ] `scripts/check-port-consistency.sh` 通过（默认 5244 一致）
- [ ] `scripts/test-upgrade-preservation.sh` 通过（模拟保留自定义端口与 `data.db`）
- [ ] `scripts/test-port-sync.sh` 通过（模拟 5244/5255、幂等、非法端口；非真机 UI）
- [ ] `scripts/test-migrate-failure-sim.sh` 通过（模拟升级缺 config / 数据保留）
- [ ] `shellcheck` 无 error（若 runner 已安装）

## 2. SPK 构建（Docker / 本地 spksrc）

- [ ] `scripts/build-openlist.sh` 在 `ghcr.io/synocommunity/spksrc` 内完成
- [ ] 产出 `openlist_apollolake-7.3_4.2.10-*.spk`（文件名以实际构建为准）
- [ ] CI 将 SPK 存为 **artifact**（非 Release）

## 3. DSM 真机（需人工授权 — 本轮未执行）

- [ ] DS918+ / DSM 7.3 全新安装：向导、默认 5244、服务用户 `sc-openlist` 正常
- [ ] 自定义 `http_port` 后原地升级到 4.2.10：配置与数据保留，且 `app/config` / INFO / `.sc` 已同步（脚本层）
- [ ] 套件中心图标「打开」与防火墙即时生效（DSM 会话重载边界见 `upgrade.md`）
- [ ] 回滚演练（备份恢复）至少一次

## 候选版本记录（非本轮目标）

- 上游 OpenList 若有 v4.2.11+ 发布，可在后续 PR 更新 `upstream.lock.json` 与 digests；本轮基线固定 **v4.2.10**。