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



# [0.44.0](https://github.com/jwstover/citadel/compare/v0.43.4...v0.44.0) (2026-03-31)


### Bug Fixes

* **agent_runner:** restrict commit subprocess to Bash-only tools ([3bce7f5](https://github.com/jwstover/citadel/commit/3bce7f55d2c4efb42dc790e9da67e6ac1211e543))


### Features

* **agent_run:** add :input_requested status, session_id field, and update guard ([2e8b2aa](https://github.com/jwstover/citadel/commit/2e8b2aa2e7f7f1efc74ecafb4e2132677d3f1f3a))
* **agent_run:** add :request_input action to transition running → input_requested ([26b64ed](https://github.com/jwstover/citadel/commit/26b64ed791f56a88d9310bca655b9d0649ac9d5e))
* **agent_runner:** session_id extraction, resume support, and question-answered feedback ([b27fed2](https://github.com/jwstover/citadel/commit/b27fed2c356b5c2e611a642726bfd2e0dd5c4013))
* **agent_work_item:** add :question_answered type and session_id field ([641d451](https://github.com/jwstover/citadel/commit/641d451667cd6e03e19dfd2007a359dfacf88568))
* **mcp:** expose ask_question tool and request_agent_run_input code interface ([8b6507b](https://github.com/jwstover/citadel/commit/8b6507ba77a4bdf6100d60bd0a48c6f01ab5a182))
* **task_activity:** add question/response types, parent linking, and domain actions ([3fb0cf6](https://github.com/jwstover/citadel/commit/3fb0cf638803acb8c276a9da04d5320b27357fec))
* **task_activity:** render agent questions and reply form in activity feed ([1673056](https://github.com/jwstover/citadel/commit/1673056b0ae1da3388e3cec5a4930382b747624d))
* **task_activity:** require agent_run_id in create_agent_question ([f914fd2](https://github.com/jwstover/citadel/commit/f914fd2948a24c1a938e4d0c8f8299d597720df8))



