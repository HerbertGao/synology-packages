# AGENTS.md — 维护约定

供人类与自动化 Agent 在本私有仓库协作时使用。

## 提交信息

采用 [Conventional Commits](https://www.conventionalcommits.org/) 简要形式，例如：

- `feat(openlist): bump upstream digest for v4.2.10`
- `fix(openlist): preserve config on upgrade when temp backup missing`
- `docs: clarify DSM INFO port limitation`
- `ci: pin actions and split static checks from spk build`

## 拉取请求

- 默认 **草稿 PR** 审阅；合入 `master` 需维护者明确授权。
- 不在 PR 中合并、打 tag、发 Release、上传可安装 SPK 到公开渠道。
- 实质配方与脚本变更应在 PR 分支完成；`master` 仅保留最小基线（如简短 README）。

## 发布与部署（禁止自动化）

以下操作 **必须** 由用户显式授权后人工执行，Agent 不得擅自进行：

- 合并 PR、创建 GitHub Release、推送套件索引 / Pages
- 在 NAS 上安装 SPK 或访问生产凭据
- 修改仓库可见性或协作者权限

## OpenList 专用

- 上游基线：`packages/openlist/upstream.lock.json` 中的 `spksrc` commit 与 OpenList 版本为唯一真相来源。
- 修改版本时同步：`overlay/**/digests`、`upstream.lock.json`、`scripts/verify-upstream-digests.sh` 可验证性。
- 不得将静态检查或未跑过的构建描述为「已在 DSM 真机验证」。

## 测试命令

```bash
./scripts/ci-run-checks.sh
# 可选（需 Docker + 长时间构建）：
./scripts/build-openlist.sh
```