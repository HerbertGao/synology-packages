# Release manifests

Each **release PR** adds `.release/<tag>.json` describing which SPK files to upload and default GitHub Release flags (`prerelease: true`, `make_latest: false`).

These files are **not** used until [`.github/workflows/release.yml`](../.github/workflows/release.yml) is enabled by setting the repository variable `RELEASE_AUTOMATION_ENABLED=true` and a maintainer merges the corresponding release PR.