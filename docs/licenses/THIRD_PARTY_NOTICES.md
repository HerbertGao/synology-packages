# 第三方许可证与归属

## SynoCommunity spksrc

- 仓库：<https://github.com/SynoCommunity/spksrc>
- 用途：交叉编译与 SPK 打包框架（本仓库通过固定 commit + overlay 使用，非 fork 全量副本）
- 基线 commit：见 `packages/openlist/upstream.lock.json`
- 许可证：以 SynoCommunity/spksrc 仓库声明为准（非标准 SPDX 单一许可证）

## OpenList

- 项目：<https://github.com/OpenListTeam/OpenList>
- 版本：v4.2.10（`upstream.lock.json`）
- 许可证：**AGPL-3.0**
- 官方文档：<https://docs.oplist.org/>

## OpenList Frontend

- 项目：<https://github.com/OpenListTeam/OpenList-Frontend>
- 版本：v4.2.10（预构建 dist  tarball）
- 许可证：**MIT**

## 说明

本仓库产出的 SPK 为**私人维护**构建，非 SynoCommunity 官方发布渠道。对外分发 AGPL 覆盖的软件时，须遵守相应源代码提供义务。