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



# [0.25.0](https://github.com/jwstover/citadel/compare/v0.24.2...v0.25.0) (2026-03-13)


### Bug Fixes

* load project, execution_status, and active_agent_run after inline edits ([e27a3e0](https://github.com/jwstover/citadel/commit/e27a3e08749c9c03de4a1dc5578fd2a182968f88))
* **P-29:** fix agent channel joining and presence tracking ([2b07b08](https://github.com/jwstover/citadel/commit/2b07b08eac1060a31e04a5914cfc869b59366336))
* **P-29:** fix agent presence not showing in sidebar ([39873a6](https://github.com/jwstover/citadel/commit/39873a6f3dbe6c988dd0dae7eb6824c5b4ae82be))


### Features

* **P-27:** add Projects domain with Project resource ([30dcf11](https://github.com/jwstover/citadel/commit/30dcf1119904ba33e2fb2159f3cc4f71c05f0293))
* **P-28:** add project, active_agent_run, and execution_status to Task ([e740c33](https://github.com/jwstover/citadel/commit/e740c33de6bb47e3b8fe8400cb12eae8a3fecdd8))
* **P-28:** show project, execution status, and active agent run in task detail UI ([9547beb](https://github.com/jwstover/citadel/commit/9547beb808147a8725e429031b34e43e52e923a2))
* **P-29:** add agent presence tracking via Phoenix Channels ([5db6385](https://github.com/jwstover/citadel/commit/5db638523ccbde5ea23f2b3fe346fc44bab81b42))
* **P-29:** connect agent to Citadel via WebSocket for presence updates ([3da6f63](https://github.com/jwstover/citadel/commit/3da6f63fabe9182b37db1191e7eaecae1cb0172a))



## [0.24.2](https://github.com/jwstover/citadel/compare/v0.24.1...v0.24.2) (2026-03-13)


### Bug Fixes

* make TaskSummary description attribute non-public ([278d771](https://github.com/jwstover/citadel/commit/278d7719653d3961833e2aa46308fd638bf88a07))



