# PR Description

## Sprint / Issue
- Sprint: <!-- e.g. v7.0/Sprint 1 -->
- Issue: <!-- link or N/A -->

## Summary
<!-- 1-3 lines describing what changed and why -->

## Type
- [ ] Bug fix (PATCH)
- [ ] Feature (MINOR — backward compatible)
- [ ] BREAKING (MAJOR — wt_advance/cert/state machine API change)
- [ ] CI / docs / internal
- [ ] Refactor (no behavior change)

## Test Plan
<!-- list every check you ran -->
- [ ] `bash 08_Tests/hooks/run_all_hooks.sh` (30/30 PASS)
- [ ] `python3 02_Infrastructure/hooks/qvest_hook_router.py selftest`
- [ ] `python3 02_Infrastructure/hooks/qvest_cert_eval.py selftest`
- [ ] `Rscript -e 'source("02_Infrastructure/worktask/state_machine.R"); qvest_state_machine_selftest()'`
- [ ] `Rscript -e 'source("02_Infrastructure/worktask/cert_rules.R"); qvest_cert_rules_selftest()'`
- [ ] (if execution path 변경) `Rscript 08_Tests/integration/test_execution_path_unified.R` (7/7 PASS)
- [ ] CI green (.github/workflows/qvest-kernel-ci.yml)

## Rollback Plan
<!-- 어떻게 되돌릴 수 있는가? -->
- Branch: `<branch_name>`
- Last safe checkpoint tag: `v7.0-sprintN-end` 또는 `pre-vX.Y.Z-...`
- Default: `git revert <commit_sha>` (atomic commit 권장)
- Destructive: `git reset --hard <tag>` (도훈 명시 승인 후만 — 공유 branch 위험)

## Checklist
- [ ] Atomic commit (1 commit = 1 logical change)
- [ ] CHANGELOG.md updated (Unreleased section)
- [ ] No `05_Production/` 또는 `01_Literature/` 수정 (read-only)
- [ ] PIT C1~C15 미위반 (look-ahead 0)
- [ ] axiom (AX-000~008) 미위반
- [ ] Codex Critic Round 5단계 (agent spawn 시) 또는 N/A
- [ ] Charter v1.X 정합 (Multi_Agent/ 참조)

## Linked Files
<!-- e.g. 02_Infrastructure/worktask/worktask_manager.R:428-470 -->
