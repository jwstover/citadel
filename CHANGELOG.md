# [0.52.0](https://github.com/jwstover/citadel/compare/v0.51.1...v0.52.0) (2026-05-11)


### Features

* **agents:** extract agent settings into lazy-loaded LiveComponent ([f19dcbe](https://github.com/jwstover/citadel/commit/f19dcbe4f12a7036e18df73cf08c6f4e6d9dafaa))
* **agents:** move agent settings to dedicated card on workspace details page ([1e48ff4](https://github.com/jwstover/citadel/commit/1e48ff4aed436c47953163d94eeaa5b3265e2e82))
* **agents:** replace inactivity stall timer with workspace-configurable wallclock cap ([437e5ac](https://github.com/jwstover/citadel/commit/437e5acc291dd0677a993445a6a06463f1a0207e))



## [0.51.1](https://github.com/jwstover/citadel/compare/v0.51.0...v0.51.1) (2026-05-05)


### Bug Fixes

* **agent-runs:** use Phoenix.Component.assign for derived todo_panel values ([9d61cf8](https://github.com/jwstover/citadel/commit/9d61cf821346773034075fbfbad7d0b8430e2b18))



# [0.51.0](https://github.com/jwstover/citadel/compare/v0.50.1...v0.51.0) (2026-05-05)


### Features

* **agent-runs:** always link to agent run page, drop logs panel ([7784962](https://github.com/jwstover/citadel/commit/7784962d141c2d7d7e41739d7351f49696f2dad3))
* **agent-runs:** drop logs column from agent_runs ([bdca7aa](https://github.com/jwstover/citadel/commit/bdca7aaca6bc4e469340a464d4433df1c503d9b2))
* **agent-runs:** persist stream events for past-run replay ([d5dee0c](https://github.com/jwstover/citadel/commit/d5dee0c7febb481a59ab884ab5fa87bd066d24c1))



## [0.50.1](https://github.com/jwstover/citadel/compare/v0.50.0...v0.50.1) (2026-04-28)


### Performance Improvements

* **observability:** trace task show async loads to Tempo ([1f0c2f0](https://github.com/jwstover/citadel/commit/1f0c2f05b95b5e0999a24992e01a20d2fb6ce439))
* **task-show:** load task data async and eliminate dependencies N+1 ([0919faf](https://github.com/jwstover/citadel/commit/0919faffd202875afed79fb3b457d7b9fc930759))
* **task-show:** split async loading per section with AsyncResult ([ac01271](https://github.com/jwstover/citadel/commit/ac01271e0e4b98feb309b00e2fa26d6e2ec137fe))



# [0.50.0](https://github.com/jwstover/citadel/compare/v0.49.1...v0.50.0) (2026-04-28)


### Features

* **observability:** capture all error-level logs in Sentry ([e21a088](https://github.com/jwstover/citadel/commit/e21a088cf2a06200ae20ddd7d221af2baa293bb3))



