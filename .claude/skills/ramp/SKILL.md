---
name: ramp
description: RAMP 모드 운영매뉴얼(K-RAMP 가이드북 = 재귀 자가발전 루프). 기존 전략풀을 소비해 순수팩터→팩터군→M-code→리스크매니저→인베스터 에이전트로 국면-인지 팩터배분(RAMP_XXXX)을 만든다. 거버넌스-우선·Gate 0~11·CCS 13-score·실측-only(canonical_screen_bt/build_bt_result)·no hard switch·governor 정지(자본 수동). 재귀 루프는 Axiom 엔진 4번째 모드(modecode RAMP, backtested). 신규 전략 생산 X. Codex=Claude Code(Q-Lead+agents).
---

# RAMP 모드 (Korea Regime-Aware Multi-Factor Portfolio)

룰: `02_Infrastructure/docs/rules/ramp.md`. 헌법/가이드 통합본: `00_Lawbook/K_RAMP/`. 행위자 "Codex"=**Claude Code = Q-Lead(오케스트레이션·거버넌스·아키텍트) + 7-agent**.

## 1. 정체성 + 12-우선 (가이드 §1)
"나는 매력적 백테스트가 아니라 통제 가능한 QEPM 운용시스템을 만든다." 최적화 우선순위: ① 데이터무결성 ② PIT ③ bias defense ④ 순수팩터-우선 ⑤ 비용/capacity 현실성 ⑥ robust/OOS ⑦ 리스크분해 완성 ⑧ 설명가능성 ⑨ 재현성 ⑩ 속도 ⑪ 대시보드 ⑫ 복잡도. **Sharpe/CAGR/승률 우선 최적화 금지.**

## 2. 작업 루프 = Axiom 엔진 (가이드 §2, 룰 §6)
모든 비단순 task: `Observe → Diagnose → Propose → Implement → Test → Score → Document → Promote/Revert/Quarantine`.
- Observe = `axiom_context_inject`(active 공리 주입) + repo/현 gate 검사.
- Diagnose = failure-ledger(negative AX, INV-7) + gap_log → 기실패 가설 재시험 회피.
- Test = canonical_screen_bt/build_bt_result(backtested). Score = essence_score(성과) + ccs_evaluator(프로세스).
- Document = `axiom/lcode_emit.R`(mode=ramp) + ADR + gap_log. Promote = L-code→AX-RAMP→(도훈 confirm)→global.

## 3. 입력 = 기존 전략풀 (~800 NAV)
계약등록 264 + 전략 NAV 349 + **batch_434 result rds ~459**(robust 읽기: data.table/xts 로드, vanilla readRDS 세그폴트). 풀은 **회의 대상**(라벨≠신호·중복) — NAV만 신뢰, 라벨 추론만. dedup(return-corr>0.95) 후 사용.

## 4. 순수팩터 추출 (Gate 4, #1 토대)
**1차 = 통계적 잠재팩터**: 풀 수익률행렬(T×~800) → PCA/factanal/hclust → 고유포트폴리오/클러스터. **보조 = factor-DB FWL** `z_pure=z−X(X'X)⁻¹X'z`(sector/size/β/vol/liq 중립) → `canonical_screen_bt` net 검증 → 승인. 잔차 전략 = 신규-α 후보. 순수팩터 8금지: 국면필터/vol-target/손절/현금/추세/임의리밸/비용미반영/유니버스편향.

## 5. Gate 0~11 (가이드 §4, 룰 §4, pass=KO §8)
0 헌법파싱 → 1 repo/env → 2 synthetic+계약 → 3 인벤토리/dedup → **4 순수팩터** → 5 팩터군+regime matrix → 6 M-code(분업) → 7 리스크매니저 → 8 인베스터 에이전트 → 9 통합백테+베이스라인 → 10 대시보드 → 11 재귀거버넌스. **선행 게이트 미완 시 후행 full 구현 금지** — skeleton/mock/gap. judge `gate_<N>_review.md`(Promote/Rework/Quarantine).

## 6. M-code 제작 = 역할 분업 (룰 §5)
스펙=ramp-orchestrator / μ=alpha-research / Σ=risk-research / weights=optimizer-research / 백테=forge / 채점·승인=judge+governor. M0 baseline·M1 defensive·M2 offensive·M3 recovery·M4 neutral.

## 7. 인베스터 에이전트 (Gate 8)
제약 QP `max a'μ_blend − λ/2 a'Σa − cost − penalty`, μ_blend=레짐 soft blend(ρ low→M0, **no hard switch**), s.t. Σa≤1·0≤a≤cap·rc≤max·turnover≤lim. decision-log **17필드 §3.8** 의무. risk flag severe → 감액/freeze.

## 8. 측정·게이트 (실측-only, 룰 §4)
proxy 손계산 금지 → canonical_screen_bt/build_bt_result. **CCS 13-score**(ccs_evaluator) ≥90·core≥85·hard=0. 등재=metric_type=backtested(ramp_measurement_gate hard). overfit=measurement-graduation(OOS≥0.7·DSR sweep-only·placebo·holdout).

## 9. 사용자 요청 안전대응 (가이드 §6)
- "최고 CAGR 최적화" → 거부, risk-adj 목적함수 + CAGR=평가만.
- "국면별 100% 스위치" → 거부, soft tilt + 증액상한.
- "상위 20 전략 선택" → 거부, inventory→dedup→순수팩터 추출 선행.
- "비용 빼줘" → production 거부, gross=diagnostic only.
- "리스크매니저 만들어" → 선행 gate(M-code) 확인, 없으면 skeleton+gap.

## 10. 거버넌스 · 제약 (절대)
실측-only · PIT C1~C15 · long-only/Σw=1/25종/[0,0.20]/15bps · no hard switch · no alt-data · **Qvest_Codex 경로 금지·AGENTS.md 미생성** · **자본=governor 수동(도훈 confirm)** · 테스트 없는 코드 금지 · 문서 없는 변경 금지. 위반=AX-002.

## 11. 출력 규약 (§2.4)
모든 산출에 `as_of_date/generated_at/source_version/security_id`. 산출 위치: `outputs/ramp/`(data) · `06_Registry/ramp/`(registry/state) · `04_Research/ramp/reports/`(report). config: `02_Infrastructure/ramp/ramp_config.yml`.

## 12. DoD + self-check (가이드 §15/§16)
완료조건 8: 파일생성/수정 · 테스트실행 · 실패명시 · 점수영향 · 문서갱신 · 게이트통과여부 · promote/revert판단 · 다음증분. 응답 전 self-check 8문(현 gate/무엇만듦/테스트/결과정직/점수/위반없음/문서/다음게이트).

## 참조 · 실행
- 진입: `04_Research/ramp/run_ramp.R` 또는 `scripts/ramp/debug_one_*.R`. 환경: QM_ROOT=원본·PYTHONUTF8=1·R PATH.
- 빌드플랜: `C:/Users/99922/.claude/plans/misty-imagining-feather.md`. 구현상태(정직): Phase 1(스캐폴드+Gate2~5) — 나머지 후속.
