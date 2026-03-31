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



## [0.43.4](https://github.com/jwstover/citadel/compare/v0.43.3...v0.43.4) (2026-03-31)


### Bug Fixes

* **mcp:** return 404 instead of 401 for OAuth discovery under /mcp ([7664451](https://github.com/jwstover/citadel/commit/7664451f6b97c514d7f4280db2c8ff9d3480aca9))



## [0.43.3](https://github.com/jwstover/citadel/compare/v0.43.2...v0.43.3) (2026-03-31)


### Bug Fixes

* **mcp:** add OAuth protected resource discovery endpoint ([d675e63](https://github.com/jwstover/citadel/commit/d675e6322fbe3fb831bfc74b021a16b9d55c20b4))



## [0.43.2](https://github.com/jwstover/citadel/compare/v0.43.1...v0.43.2) (2026-03-23)


### Bug Fixes

* preserve agent status across server redeploys ([5e5d54d](https://github.com/jwstover/citadel/commit/5e5d54d482d8dec44b5efe651261c137fcea285e))



## [0.43.1](https://github.com/jwstover/citadel/compare/v0.43.0...v0.43.1) (2026-03-23)


### Bug Fixes

* expose create_task_dependency as MCP tool ([ab2c21d](https://github.com/jwstover/citadel/commit/ab2c21d12acf8cb586f3998ea9a0cea6e9c6c132))
* pass AshAi pre-check in TaskWorkspaceMember ([30f101c](https://github.com/jwstover/citadel/commit/30f101cf16b7146e2107cd34c89627498e709a5f))



