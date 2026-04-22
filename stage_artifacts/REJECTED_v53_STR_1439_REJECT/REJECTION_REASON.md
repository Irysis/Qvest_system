# H_1677 REJECTED — STR_1439 v53 Repair 전제 무효

## 결정 요약
- **결정**: Path B 폐기 (Path A pivot 아님)
- **일시**: 2026-04-17
- **결정자**: Scout (team-lead 승인 대기)
- **후속 hypothesis**: H_1690 (신규)

## 폐기 근거 (3건)

### 1. Parent strategies MISSING (재현 불가)
- H_1677 원본 설계는 4 sub-signal score-blend 전제
- Sub-strategy parents: **STR_1037 / STR_898 / STR_1035 MISSING** (Judge sweep v3 Pass 2 Tier 1 확정)
- L-149 SYS_FAILURE: "parent sub-sim이 디스크에서 유실되면 run_all.R 자체가 재현 불가능"
- Sub A/C/D의 factor spec (regime factor allocation / OAS minvar weight)을 원본 없이 복원 불가
- score-blend 재설계도 동일하게 factor 명세 부재로 실패

### 2. STR_1439 자체 B_ARCHIVE 확정
- Judge sweep v3 Pass 2 Tier 1: L-484 return-blend 80-stock violation
- FF5 alpha t=2.953 < Harvey 3.0 borderline (L-149 기록)
- 원본이 B_ARCHIVE 격하 → v53 repair 대상으로 부적합

### 3. H_1690 대체 경로 확보
- Judge governor_actions_required[3]: "novelty_bonus=10 is genuine alpha signal that may warrant score-blend redesign as new S0 hypothesis"
- H_1690 신규 가설로 깨끗하게 재시작하는 것이 H_1677 pivot보다 cleaner
- H_1677 pivot 시 원본 4-sub 구조 잔재로 혼란 가능 (parent MISSING 이슈 반복)

## 보존 가치 있는 요소 (H_1690 설계 시 재활용)

1. **Regime-conditional weight smoothing (max 10%p/month)**: STR_1047 TO 3702% → STR_1439 TO 154% 달성 구조. H_1690 score-blend에서 재활용 가능.
2. **Multi-source alpha 다각화 원칙**: 4 독립 economic rationale (momentum / consensus / regime / risk)의 score-level 합성 개념. 단 parent MISSING으로 구체 factor는 재탐색 필요.
3. **Defense anchor 역할 (AX-001 조건부 평가)**: H_1690에서 defense_anchor role 유지 검토 가능.

## H_1690 신규 설계 차별점
- 4 sub parents MISSING → **기존 Factor DB 4 factor 재구성** (C19 consensus + M01 momentum + H_1676 residual consensus + R16 Calmar 후보)
- novelty 원천 구체화: Judge novelty 10 근거 조회 필수 (judge_sweep_v3_STR_1439_verdict.json)
- v53 N<=20 score-blend union
- H_1676 Forge S1 결과 활용 가능 (residual consensus 이미 APPROVE_CONDITIONAL)

## 승인 경로
Q-Lead가 이 REJECTION 승인 시:
- Task #19 (H_1690) in_progress 전환
- Scout 본격 설계 착수 (30~45분)

## Audit trail
- REJECTION 파일: `stage_artifacts/REJECTED_v53_STR_1439_REJECT/s0_record_H_1677_STR_1439_v53_repair_REJECTED.json`
- 참조 Judge 보고서: `stage_artifacts/judge_sweep_v3_pass2_tier1_20260417.json`
- 참조 L-code: L-149 SYS_FAILURE (methodology_memory.md)
