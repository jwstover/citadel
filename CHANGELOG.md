## [0.50.1](https://github.com/jwstover/citadel/compare/v0.50.0...v0.50.1) (2026-04-28)


### Performance Improvements

* **observability:** trace task show async loads to Tempo ([1f0c2f0](https://github.com/jwstover/citadel/commit/1f0c2f05b95b5e0999a24992e01a20d2fb6ce439))
* **task-show:** load task data async and eliminate dependencies N+1 ([0919faf](https://github.com/jwstover/citadel/commit/0919faffd202875afed79fb3b457d7b9fc930759))
* **task-show:** split async loading per section with AsyncResult ([ac01271](https://github.com/jwstover/citadel/commit/ac01271e0e4b98feb309b00e2fa26d6e2ec137fe))



# [0.50.0](https://github.com/jwstover/citadel/compare/v0.49.1...v0.50.0) (2026-04-28)


### Features

* **observability:** capture all error-level logs in Sentry ([e21a088](https://github.com/jwstover/citadel/commit/e21a088cf2a06200ae20ddd7d221af2baa293bb3))



## [0.49.1](https://github.com/jwstover/citadel/compare/v0.49.0...v0.49.1) (2026-04-22)


### Performance Improvements

* **dashboard:** preload blocked?/blocking_count on top-level tasks ([33f489f](https://github.com/jwstover/citadel/commit/33f489f408561b4544994e97035e8a0f186f0346))



# [0.49.0](https://github.com/jwstover/citadel/compare/v0.48.2...v0.49.0) (2026-04-22)


### Bug Fixes

* **observability:** export PromEx metrics via Fly Prometheus scrape ([5e1cb53](https://github.com/jwstover/citadel/commit/5e1cb53267dd74730dd4f5f5eb659d3fc16bb788))


### Features

* **observability:** auto-upload PromEx dashboards to Grafana Cloud ([a1ad64b](https://github.com/jwstover/citadel/commit/a1ad64b47b40d23daf78ab59d387392a2302dd6d))



## [0.48.2](https://github.com/jwstover/citadel/compare/v0.48.1...v0.48.2) (2026-04-22)


### Bug Fixes

* **observability:** stop double-parsing OTLP headers ([220680e](https://github.com/jwstover/citadel/commit/220680e92513b28c07ec39d73b1c2dcf5ad2c038))



