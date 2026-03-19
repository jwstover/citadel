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



# [0.33.0](https://github.com/jwstover/citadel/compare/v0.32.0...v0.33.0) (2026-03-16)


### Bug Fixes

* **agent:** move PR creation to after feature branch merge ([152faa2](https://github.com/jwstover/citadel/commit/152faa2d5b9f972aeaf02332671cf07abd0ca1e7))


### Features

* handle dependency unblocking in MaybeEnqueueAgentWork ([ba3788a](https://github.com/jwstover/citadel/commit/ba3788a0a98a546dc1470f87fa0677441717e744))



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



