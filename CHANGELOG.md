## [0.34.4](https://github.com/jwstover/citadel/compare/v0.34.3...v0.34.4) (2026-03-23)


### Bug Fixes

* create draft PR for top-level tasks in agent runner ([d9e7308](https://github.com/jwstover/citadel/commit/d9e73085ac17332c00abf1a6abad7301eb4a8a66))



## [0.34.3](https://github.com/jwstover/citadel/compare/v0.34.2...v0.34.3) (2026-03-19)


### Bug Fixes

* remove workspace_id from task create accept list ([b8e0667](https://github.com/jwstover/citadel/commit/b8e0667f8efcab86ef36d4267552cbe2afe15e83))
* remove workspace_id from task create calls in tests ([f20937e](https://github.com/jwstover/citadel/commit/f20937e41126b226d341d4735fb908add7168c0d))
* use context.tenant for workspace_id in assignee validation ([2b34e44](https://github.com/jwstover/citadel/commit/2b34e44f50225318dd00aeb035a279265d1e5f9c))



## [0.34.2](https://github.com/jwstover/citadel/compare/v0.34.1...v0.34.2) (2026-03-19)


### Bug Fixes

* remove duplicate Home nav item from sidebar ([ec66b5f](https://github.com/jwstover/citadel/commit/ec66b5f8ad7dd410ac1d6fda1bbb85ce53e52498))
* use dynamic workspace task_prefix in dependency input placeholder ([cc392ab](https://github.com/jwstover/citadel/commit/cc392abd860a179fb4543e441f3a0f2742245037))



## [0.34.1](https://github.com/jwstover/citadel/compare/v0.34.0...v0.34.1) (2026-03-17)


### Bug Fixes

* format show.ex template ([b879a33](https://github.com/jwstover/citadel/commit/b879a3308a9d3c53909baa985d131caff2f3e5f2))
* scope capture_commits to only current agent run ([03724dd](https://github.com/jwstover/citadel/commit/03724dd101ba5230ab7f87abde0a45ae3966ff68))
* update tests and migration for {:array, :map} commits attribute ([20985e9](https://github.com/jwstover/citadel/commit/20985e9226c869386267e4f415f4f27db19d1cb0))



# [0.34.0](https://github.com/jwstover/citadel/compare/v0.33.0...v0.34.0) (2026-03-16)


### Features

* **agent:** replace diff field with commits on AgentRun ([e31aa31](https://github.com/jwstover/citadel/commit/e31aa318234168b186035adbfaa6213992dbe436))
* **agent:** wire PR creation to set forge_pr on parent task ([2ed0139](https://github.com/jwstover/citadel/commit/2ed0139b6bfe210b2f54d78c06bbc2744df1e906))
* **api:** expose forge_pr in agent API for reading and updating tasks ([8cee8a4](https://github.com/jwstover/citadel/commit/8cee8a4e8745c8ad8447ad0451a9edbe0bff378c))
* **tasks:** add forge_pr attribute to store associated PR URL ([db32361](https://github.com/jwstover/citadel/commit/db323616ab2bbcc26f0c560f0aafd000aa2db53c))



