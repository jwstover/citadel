# [0.47.0](https://github.com/jwstover/citadel/compare/v0.46.1...v0.47.0) (2026-04-13)


### Bug Fixes

* resolve Svelte build pipeline path and API compatibility issues ([ba41fe9](https://github.com/jwstover/citadel/commit/ba41fe9f2e52788e96f828c6e87fe029c4e390c4))


### Features

* add custom node styling, detail panel, and active runner animation ([b53c5ba](https://github.com/jwstover/citadel/commit/b53c5ba35ce5361e9ccba60e565a988bf49d2467))
* add Node-based Svelte build pipeline alongside esbuild ([fdbeb77](https://github.com/jwstover/citadel/commit/fdbeb77875397db030d2624098ee8132c39fdb57))
* add Svelte and XYFlow npm dependencies ([7123af8](https://github.com/jwstover/citadel/commit/7123af8e987ff6429cbc5b402aa8726401b0a696))
* add workflow_editor feature flag and gated dev route ([a0d9b72](https://github.com/jwstover/citadel/commit/a0d9b72787b28b07e4b55208dceea5dbb8df63d4))
* add WorkflowGraph Svelte component and WorkflowEditor LiveView hook ([e59465d](https://github.com/jwstover/citadel/commit/e59465d0d77581ba67cdd45f5f5e4c7bf13bee4d))



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



