# [0.32.0](https://github.com/jwstover/citadel/compare/v0.31.0...v0.32.0) (2026-03-16)


### Bug Fixes

* **tasks:** use to_string/1 for email in format_assignees ([d96cef4](https://github.com/jwstover/citadel/commit/d96cef4736fa12bb0ca656d4086de9a8cd690219))
* **test:** use existing task states and cancel instead of complete work item ([9f2bbaa](https://github.com/jwstover/citadel/commit/9f2bbaa6a460ee5422f719566ebf908b4158e6e4))


### Features

* **agent:** add comment endpoint and work item metadata to claim response ([441fa21](https://github.com/jwstover/citadel/commit/441fa213534c007da9fba951b632ed83f4028161))
* **agent:** handle changes_requested work items with feedback context ([793365d](https://github.com/jwstover/citadel/commit/793365df918fe2bd8b758bf414bef026ad5c5068))
* **tasks:** add AgentWorkItem resource for agent work queue ([c7d486e](https://github.com/jwstover/citadel/commit/c7d486ecd960f88f74773bbf904dd232ea0c0231))
* **tasks:** add request changes action and change_request activity type ([d2e74b6](https://github.com/jwstover/citadel/commit/d2e74b6aef9188b0c9e822953659ea572837682b))
* **tasks:** auto-create work items when tasks become agent-eligible ([63bcac2](https://github.com/jwstover/citadel/commit/63bcac27b98256823834336ece40581ea7a3f2a4))
* **tasks:** rework ClaimNextTask to claim from AgentWorkItem queue ([67f045e](https://github.com/jwstover/citadel/commit/67f045ebeb0a2efaece43314b449e56fefd6649b))
* **tasks:** sync AgentWorkItem status with AgentRun lifecycle ([a997f33](https://github.com/jwstover/citadel/commit/a997f33701947b43c7f808043116ee94f2f22408))
* **ui:** add Request Changes toggle to task activity comment form ([6a71fff](https://github.com/jwstover/citadel/commit/6a71fff5bfb4be5b91b3e4a6edeca0ee50e97334))



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



