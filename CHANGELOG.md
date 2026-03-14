# [0.31.0](https://github.com/jwstover/citadel/compare/v0.30.0...v0.31.0) (2026-03-14)


### Bug Fixes

* **agent:** filter sub-agent events from AgentRunLive stream ([7980c53](https://github.com/jwstover/citadel/commit/7980c536d85ea790a273541cd3c76f9777de7c07))
* resolve Credo warnings in agent run components ([3bca753](https://github.com/jwstover/citadel/commit/3bca7534a1a45b3c5606375fa6272c7e1455dbce))


### Features

* **agent:** add AgentRunComponents for rendering stream events ([462b190](https://github.com/jwstover/citadel/commit/462b190a75dc8d3f16794aa723f4294c5e6bc523))
* **agent:** add AgentRunLive page for real-time stream output ([a8430f3](https://github.com/jwstover/citadel/commit/a8430f3ec2720ae53b6df72aaae282a7007baebf))
* **agent:** add StreamParser module for Claude stream-json output ([bd8c2e1](https://github.com/jwstover/citadel/commit/bd8c2e174076bbcc993c05565a5743ef8518af49))
* **agent:** add Watch link to active agent runs on task show page ([3271daf](https://github.com/jwstover/citadel/commit/3271daf099d6a605347579fb6d01d2671fd9acce))
* **agent:** improve AgentRunLive stream rendering ([710bf62](https://github.com/jwstover/citadel/commit/710bf62f0922165f473f725f45ad280acaf13748))
* **agent:** push stream events to channel as Claude CLI output arrives ([f518f1f](https://github.com/jwstover/citadel/commit/f518f1f401c51fee7057fbf482476ad4409acc0c))
* **agent:** relay stream events from runner to PubSub via AgentChannel ([b316910](https://github.com/jwstover/citadel/commit/b31691019a44cc20664fa6d84e6105de99423dfe))



# [0.30.0](https://github.com/jwstover/citadel/compare/v0.29.0...v0.30.0) (2026-03-14)


### Features

* **agent:** replace multi-step task pickup with atomic claim_task ([258d3d0](https://github.com/jwstover/citadel/commit/258d3d088dd7683814bf9378e9c269e3871760e4))
* **api:** replace next_task/create_run endpoints with atomic claim_task ([d594292](https://github.com/jwstover/citadel/commit/d594292100c03aad2ba730284675aac92866cef5))
* **tasks:** add claim_next action to AgentRun for atomic task claiming ([b60b4e8](https://github.com/jwstover/citadel/commit/b60b4e895db52c85ab4ad8bbacc4c9bc48aa018f))



# [0.29.0](https://github.com/jwstover/citadel/compare/v0.28.0...v0.29.0) (2026-03-14)


### Features

* show task human_id with link in sidebar agent list ([da274d8](https://github.com/jwstover/citadel/commit/da274d8e67185029690d9d4a69cdc5b61dcf6694))



# [0.28.0](https://github.com/jwstover/citadel/compare/v0.27.0...v0.28.0) (2026-03-14)


### Features

* make PR creation idempotent with find-before-create logic ([b5f4917](https://github.com/jwstover/citadel/commit/b5f4917a5792de21b04cb6dc391d73c8c75c22d1))



# [0.27.0](https://github.com/jwstover/citadel/compare/v0.26.0...v0.27.0) (2026-03-13)


### Features

* add Cancelled task state via data migration ([1168ef8](https://github.com/jwstover/citadel/commit/1168ef8b8e70185e52abcad9d9e330955363748c))



