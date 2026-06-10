# Qvest 헌법 변경 이력 (CLAUDE.md에서 분리, 2026-06-10 P2 다이어트)

> CLAUDE.md는 "현재 유효한 헌법"만 담는다. 버전 연혁·릴리스 상세는 본 파일이 SOT.
> 최신 릴리스 상세: `qvest_v8_1_sot.md` (v8.1) · `qvest_v8_0_upgrade_plan.md` (v8.0)

## Release Status (v6.4.0 → v8.1.1)

| Release | 일자 | 핵심 |
|---|---|---|
| ✅ **v8.1.1** | 2026-06-10 | 완벽 수리 + P2 구조 개편. OneDrive canonical 단일화(도훈 mandate) · hook 47/47 부활 · Python/arrow/codex 체인 복구 · env 3중 안전망(QM_ROOT/QVEST_PY/.Renviron) · 헌법모순 일소(max25/TO11 전 계층) · 게이트 2계층(screening tier 신설) · rules autoload 16→6 다이어트 · axiom harvest 백필(corpus 95). |
| ✅ **v8.1.0** | 2026-06-05 | 3-Mode 헌법(각자 평가·자가발전) + 실측-only 거버넌스 + register_module 자동흐름 + Axiom r7 복원. |
| ✅ **v8.0.0** | 2026-05-29 | R+Python 1급 · SR 2.5 · measurement-graduation(WS1/2/3) · agent effort · Dynamic Workflow. |
| ✅ **v7.2.1** | 2026-05-02 | Memory Knowledge Hardening. Axiom JSON SOT (8 active) + memory_health 12-check + 15 readiness + auto-push hook. 도훈 audit 32 critical 모두 반영. |
| ✅ **v7.2.0** | 2026-05-02 | v8 readiness gate 14-check write mode strict PASS + CHANGELOG + 3-day soak. |
| ✅ **v7.1.0-lite** | 2026-05-02 | Solo Operator productivity 5 sprint (qvest_search + qvest_wt + INDEX.md + 3 workflow examples). 15 atomic commits. |
| ✅ **v7.0.1** | 2026-05-02 | 도훈 흠 4건 fix (synthetic cleanup / cert_rules data layer / harness_health hook 제거 / qvest_observe error masking). |
| ✅ **v7.0.0** | 2026-05-02 | Hardening 7 sprint. "검증 가능한 소프트웨어 커널" — 우회 불가능한 실행 계약. 14 schema + sm_validated_advance + events.jsonl + qvest_observe + legacy_write_block. E2E 12/12 PASS. |
| ✅ **v6.4.0** | 2026-05-01 | Harness Kernel Stabilization. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine. |

**검증 기록**: v7.2.1 strict run (2026-05-02, 구 WSL 머신): 30/30 hooks · 15/15 readiness · memory_health hard 0. **v8.1.1 (2026-06-10, 현 머신)**: hook 47/47 + 차단 4종 실증 · readiness pass 12/fail 0 · bootstrap BOOT_FAILS=0 · memory_health hard 0 (HARD_7 신설 포함).

**v8 후속 (이연)**:
- v7.3 candidate: AX-002/003/004/005 advisory → block 강화 / AX-007/008 hook hard-block 검토
- v7.x ext: SQLite event DB (현 JSONL fallback) / Daily brief Telegram SLO / Dashboard Shiny UI
- v8.x: qvest_hook_router 단일 진입 전환(이벤트당 1 spawn — 1주 soak 후), daily_refresh 구조 전환

## 변경 이력 (상세)

- **v8.1.1** — 2026-06-10 — 완벽 수리(아키텍처 전수 감사 → hook 전멸·메모리 단절·인터프리터 전멸 복구) + P2 구조 개편(게이트 2계층 / rules 다이어트 / 측정 사다리 / axiom 3축 충전 / MCP 재구축). 커밋 95ad9513 · 93da0bbf 외.
- **v8.1.0** — 2026-06-05 — 3-Mode 헌법 승격 + alpha-search 표준(논문 완전 복제·K200∪KQ150·2005~) + bootstrap 패치.
- **v8.0.0** — 2026-05-29 — Axiom 엔진 리뉴얼(r7 복원) + 측정 무결성 + Graduation 허들 재설계.
- **v7.2.1** — 2026-05-02 Session 76 — Memory Knowledge Hardening release (도훈 audit 32 critical 반영). Axiom JSON SOT (active 8건) + memory_health 12-check + 15 readiness + auto-push Stop hook. 신규 SOT `qvest_v7_2_1_sot.md` 발행. L-273~L-275.
- **v7.2.0** — 2026-05-02 — v8 readiness gate 14 check write mode strict PASS + CHANGELOG v7.2.0 entry + 3-day soak.
- **v7.1.0-lite** — 2026-05-02 — Solo Operator productivity (qvest_search + qvest_wt + INDEX.md + 3 examples). 15 atomic commits.
- **v7.0.1** — 2026-05-02 — Hardening patch (도훈 흠 4건 fix).
- **v7.0.0** — 2026-05-02 — Hardening 7 sprint release. "검증 가능한 소프트웨어 커널" 패러다임 (Codex 외부 평가 "SW 아키텍처 약함" → 우회 불가능한 실행 계약). L-272.
- **v6.4.0** — 2026-05-01 Session 75 — Harness Kernel Stabilization release. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine + dry-run 30/30 + E2E 10/10. L-269~L-271.
- **v6.4 Sprint 1** — 2026-05-01 Session 75 — Active SOT 단일화 + CLAUDE.md 경량화 (436 → ~270 lines) + skills/rules 8 신규.
- **v6.3.3** — 2026-05-01 — v6.0 Codex Critic Round 3중 장치 영구 정착 (L-269)
- **v6.3.2** — 2026-05-01 — Cert Auto-Issuance Paths 명문화 + Layer 4 deferred
- **v6.31** — 2026-04-28 — Charter v1.2 §10 Certification System
- **v6.0** — 2026-04-23 — QEPM 3-Agent WorkTask 도입
- **v5.5** — 2026-04-19 — v55 strict
- **v5.3** — 2026-04-13 — v53 TeamCreate + Hook 17종

(구 plan 참조였던 `/home/quant/.claude/plans/nifty-tickling-hinton.md`는 WSL 시대 경로 — 도달 불가, 내용은 v6.4 SOT에 흡수됨.)
