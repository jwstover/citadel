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



# [0.26.0](https://github.com/jwstover/citadel/compare/v0.25.0...v0.26.0) (2026-03-13)


### Bug Fixes

* use detached worktree fallback when feature branch is already checked out ([91f2b29](https://github.com/jwstover/citadel/commit/91f2b294f8e44a9532e6c563b0a993ce03e0a2aa))


### Features

* add generate_pr_description/2 to Runner for AI-generated PR descriptions ([acd296d](https://github.com/jwstover/citadel/commit/acd296df1efb399af2fa3ab62b1e578bbde8fcae))
* add GitHub token preflight check ([eeebb2d](https://github.com/jwstover/citadel/commit/eeebb2d11ac5e6cdaf74b30963e822dd36410be6))
* add GITHUB_TOKEN to agent config ([b154b4e](https://github.com/jwstover/citadel/commit/b154b4e7db1b450c7801d87ec3f6d3e8c1b14897))
* auto-create draft PR when new feature branch is created ([2a1bda6](https://github.com/jwstover/citadel/commit/2a1bda6413f27f9cd692e50aef07a38d0ad2b260))
* make GitHub module testable via configurable Req options ([1a46a0f](https://github.com/jwstover/citadel/commit/1a46a0feda3c5eb3b6c113403ad221ee0b57d25a))



