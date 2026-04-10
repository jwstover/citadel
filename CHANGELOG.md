## [0.46.1](https://github.com/jwstover/citadel/compare/v0.46.0...v0.46.1) (2026-04-10)


### Bug Fixes

* restrict tool access in commit/pr subprocesses ([bbc6823](https://github.com/jwstover/citadel/commit/bbc68233bdc294fef3283482ef7367ab55e20a60))



# [0.46.0](https://github.com/jwstover/citadel/compare/v0.45.2...v0.46.0) (2026-04-10)


### Bug Fixes

* upgrade Oban migration to v14 to add suspended job state ([8f78b13](https://github.com/jwstover/citadel/commit/8f78b132e44e37cd20b2053155577779a363ed8b))


### Features

* auto-create TaskActivity when agent run is created ([3f6ab94](https://github.com/jwstover/citadel/commit/3f6ab940b6ec5eacba6496d143ab0ed2b20fa56d))



## [0.45.2](https://github.com/jwstover/citadel/compare/v0.45.1...v0.45.2) (2026-04-07)


### Bug Fixes

* use uuid_generate_v7() for backfilled activity records ([7ec2272](https://github.com/jwstover/citadel/commit/7ec227255011dc3eb52a5382db08b5887ca311cd))



## [0.45.1](https://github.com/jwstover/citadel/compare/v0.45.0...v0.45.1) (2026-04-01)


### Bug Fixes

* resolve duplicate agent_run_id migration failure in prod ([3893051](https://github.com/jwstover/citadel/commit/3893051175acc67e34438a18592365aa81f5172a))



# [0.45.0](https://github.com/jwstover/citadel/compare/v0.44.0...v0.45.0) (2026-04-01)


### Bug Fixes

* remove duplicate agent_run_id column from migration ([681f337](https://github.com/jwstover/citadel/commit/681f337ccea885cedee03fccb7bdf38573aea33a))
* update agent run tests to match activity-based UI ([80d977b](https://github.com/jwstover/citadel/commit/80d977bb27a598dc1d868ef0ec1855ed1cea46f4))


### Features

* add :agent_run activity type and relationship to TaskActivity ([5605c54](https://github.com/jwstover/citadel/commit/5605c542c392e0885106b2b12be348947043bede))
* add backfill migration and tests for agent run task activities ([4cce8db](https://github.com/jwstover/citadel/commit/4cce8db186d8214c3c6593d702c6e31cb5b7a328))
* render agent run activities in TaskActivitySection with full detail ([47b57e0](https://github.com/jwstover/citadel/commit/47b57e027289ac889f4f185398ba73d78b35ddda))



