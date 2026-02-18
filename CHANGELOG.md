# [0.17.0](https://github.com/jwstover/citadel/compare/v0.16.0...v0.17.0) (2026-02-18)


### Features

* **P-18:** add :current read action to Workspace resource ([3eca363](https://github.com/jwstover/citadel/commit/3eca363e4f8a423bba2c98908458e441e77c1ff8))
* **P-19:** add AshAi extension and get_current_workspace tool to Accounts domain ([f788819](https://github.com/jwstover/citadel/commit/f788819ac8812a425689cc90188c9f3803a8f0bf))
* **P-20:** register get_current_workspace tool in MCP router ([b17bf44](https://github.com/jwstover/citadel/commit/b17bf44f677d5896a6a1a4f8e63a6bc46a95539c))
* **P-21:** add tests for MCP get_current_workspace tool ([98d71b7](https://github.com/jwstover/citadel/commit/98d71b75ca1c71d10ff546d4a482a29d76d962f3))



# [0.16.0](https://github.com/jwstover/citadel/compare/v0.15.0...v0.16.0) (2026-02-17)


### Bug Fixes

* derive advisory lock namespace from module name ([5733620](https://github.com/jwstover/citadel/commit/573362044298d1500162ad04ba6060f37109fd69))
* prevent credit overdraft ([be5bc60](https://github.com/jwstover/citadel/commit/be5bc6074922496449fc817a59598925874408d9))
* resolve credit race condition ([377a0e2](https://github.com/jwstover/citadel/commit/377a0e20292d73400dfeeb562368472dc9b4dd7f))
* resolve issue resulting in lost credit consumption ([faa37ef](https://github.com/jwstover/citadel/commit/faa37ef53243ddb7e15ba7ec5bc63521ae26d4c1))
* resolve issues with duplicate bg jobs ([4dcfe04](https://github.com/jwstover/citadel/commit/4dcfe04591800b4f8a4a678a50abd275c27bff6a))
* resolve oban job uniqueness issues ([14cc887](https://github.com/jwstover/citadel/commit/14cc887e874046b6fde47c73c9f1d93e3f2f9041))
* resolve remaining workspace vulnerabilities ([5583e52](https://github.com/jwstover/citadel/commit/5583e52aed84ffe2d282f5a71a6ad2373dae6ba4))
* resolve test failures caused by orgs ([fedbd6c](https://github.com/jwstover/citadel/commit/fedbd6c6cc6a52dfa448b1fe9f0cc6b28d7b83ed))
* use existing task states in tests instead of creating duplicates ([68cd037](https://github.com/jwstover/citadel/commit/68cd0376f6535d826369e72664a32024b829995e))


### Features

* add billing resources ([4546c65](https://github.com/jwstover/citadel/commit/4546c65bc739c9a75f8a3327b72bee5fc8832ad0))
* add feature gating ([8152b60](https://github.com/jwstover/citadel/commit/8152b6070f1ff4932e89b114ab093f5d6951e9a2))
* add github mcp tools to ai chat ([41e8234](https://github.com/jwstover/citadel/commit/41e823485192da4a14880abedae355ba3a7e7b96))
* add organizations ([7928b97](https://github.com/jwstover/citadel/commit/7928b977f09257694b3afefa901c5407fa2f4899))
* add template legal ([416f9b8](https://github.com/jwstover/citadel/commit/416f9b8ed41f7b9fde77b904db216f9227386ff3))
* add upgrade UI ([8319405](https://github.com/jwstover/citadel/commit/8319405d99b8c0ab6b0cb0b387c7ebf36375a242))
* implement extensible tier system ([4d5ce73](https://github.com/jwstover/citadel/commit/4d5ce73301b3b532c569a7801743d640a8919a64))
* set user email when initiating checkout session ([8ea9f6e](https://github.com/jwstover/citadel/commit/8ea9f6e6d5740d922b0572a84c018ce58a398c44))



# [0.15.0](https://github.com/jwstover/citadel/compare/v0.14.0...v0.15.0) (2026-01-14)


### Bug Fixes

* **PER-230:** Fix calculation attribute loading in blocked? and blocking_count ([31205fd](https://github.com/jwstover/citadel/commit/31205fd9a3aa3a1c301df6a3d4df07a7708a5530))
* Update task dependency tests to match UI implementation ([2c65ff8](https://github.com/jwstover/citadel/commit/2c65ff8e1fe7145c38794da595f4aed626f754c2))


### Features

* **PER-230:** Implement task dependencies core features ([4716c8b](https://github.com/jwstover/citadel/commit/4716c8bf8fa32fa1ad631762cf7deb1cecc6256e))
* **PER-235:** Add dependencies UI section to task detail view ([96f806b](https://github.com/jwstover/citadel/commit/96f806b921b5a489c8c4f5ed9298cb4c6f189c51))
* **PER-236:** Add soft enforcement warning for completing blocked tasks ([5fadc92](https://github.com/jwstover/citadel/commit/5fadc92fabde091a5efa42b6e12cb0a51210ac31))
* **PER-238:** Add comprehensive LiveView tests for task dependencies ([df33f03](https://github.com/jwstover/citadel/commit/df33f0393de06803fbf031c67c99481ed40071c4))
* **PER-239:** Add dependency support to MCP task tools ([009d658](https://github.com/jwstover/citadel/commit/009d65859f9fd8a4fbb98fdbe580eb52a7cada5d))



# [0.14.0](https://github.com/jwstover/citadel/compare/v0.13.0...v0.14.0) (2025-12-28)


### Features

* add landing page ([5a35576](https://github.com/jwstover/citadel/commit/5a355768b57da63eb4c31cac197b689501bc038b))



# [0.13.0](https://github.com/jwstover/citadel/compare/v0.12.0...v0.13.0) (2025-12-15)


### Features

* make task pages auto update with changes ([956f885](https://github.com/jwstover/citadel/commit/956f88510679754b84b3d4e820fd4efcdfe5bc27))



