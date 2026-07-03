# Challenge Note — Example Fixture

**codex_critic_skip_waiver**: examples/qvest_workflows/ fixture는 production WT이 아닌 reference 자료입니다. v6.0 Codex Critic Round 면제 (도훈 v7.1-lite Sprint 4 명시 — production mailbox 무손상 + schema-valid synthetic year 9999).

이 디렉토리의 모든 *_package.json / judge_verdict.json / governor_admission.json은 도훈이 직접 읽고 학습할 수 있도록 작성된 reference fixture입니다. 실제 Codex Critic Round를 거친 draft + critic_response 산출물이 아닙니다.

## 사유

- production lifecycle WT가 아님 (examples/ prefix path)
- synthetic Year 9999 ID (production mailbox에 leak 시 `_e2e_cleanup_guard.sh --check` 자동 차단)
- v7.1-lite Sprint 4 plan 명시: 14 schema 통과 + reference 가치만 보존, 실제 lifecycle 실행 X
- v7.0 kernel contract 위반 0건 (examples/는 production scope 외부)

## Reference

- Plan: `/home/quant/.claude/plans/v7-1-cheerful-balloon.md` Sprint 4
- 정책: `examples/qvest_workflows/README.md` "Synthetic ID 정책" 섹션
