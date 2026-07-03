# Gate Review Report — RAMP Gate 6→7→8→9 (Investor Agent)

Date: 2026-06-19
Current gate: Gate 9 — Integrated Backtest (Gate 6 M-code Factory + Gate 7 Risk Manager + Gate 8 Investor Agent)
Review status: **FAIL (vs baselines) — documented honestly per guidebook §9**

## Context
도훈 mandate: "가이드북에 따른 자가발전으로 한계돌파. overlay는 명시되지 않았으니 임의 판단 금지."
→ 단일 M_regdd(미완 Gate 6)를 가이드북 정식 Gate 6–8로 대체 구현. 2017+ cohort decay 한계를
가이드북 메커니즘(리스크매니저 decay 플래그 → 인베스터 동적 감액)으로 돌파 시도. 임의 overlay 미사용.

## Required Artifacts
| Artifact | Exists | Notes |
|---|---|---|
| 역할 M-code M0–M4 | yes | 경제군 역할 배정 (M0 전체분산·M1 LowRisk+Quality·M2 Momentum+Growth·M3 Value+Reversal·M4 나머지) |
| 리스크매니저 model_drift_risk 플래그 | yes | trailing-24m active SR<0 발화 (M2 34%·M3 26%·M1/M4 22%·M0 13%) |
| 인베스터 에이전트 (레짐 soft-blend × drift 감액, no hard switch cap 0.40) | yes | 의사결정 로그 포함 (IAES) |
| 통합백테 baselines | yes | M0_only / EW_Mcode / NoRegime |
| `outputs/ramp/gate8_investor_series.csv` | yes | 월별 시계열 |

## Gate 9 결과 (cap-w active IR, n=256, IS=153/OOS=103, book ref 0.795)
| method | full | IS | OOS | port_t |
|---|---|---|---|---|
| INVESTOR | +0.469 | +0.971 | −0.192 | +1.95 |
| **M0_only** (fallback) | +0.570 | +1.101 | **−0.080** | +2.50 |
| EW_Mcode | +0.450 | +0.958 | −0.202 | +1.90 |
| NoRegime | +0.469 | +0.976 | −0.197 | +1.96 |

## 판정 (가이드북 §9: "인베스터가 baseline 미달 시 숨기지 말고 실패 문서화 + fallback 권고")
1. **INVESTOR가 단순 baseline(M0) 미달** — OOS −0.192 < M0 −0.080. 동적배분이 오히려 해로움.
2. **INVESTOR ≈ NoRegime** (레짐 조건화 기여 0) — decay된 팩터엔 활용할 레짐 신호 없음.
3. **역할 분화 유해** — 좁은 역할 M-code는 분산↓·decay 노출↑. M0(전체 분산)이 최선.
4. **전 method OOS 음수** — 2017+ cohort-wide decay가 모든 구성을 끌어내림.

## 근본 진단 (재귀개선 §11)
한계는 Gate 4(순수팩터 자체의 2017+ cohort decay). 하위 게이트(6–8) 아키텍처는 팩터에 없는 알파를
만들 수 없음. drift 플래그는 정상 작동하나 cohort-wide decay라 **갈아탈 비-decay M-code가 없음** —
감액→회전해도 동등하게 죽은 군. 가이드북 §1.3 금지(파라미터 마이닝으로 16% 맞추기) 적용 → 추가 튜닝 중단.

## Decision
**QUARANTINE** (Gate 6–8 아티팩트 보존, 프로덕션 미투입). Fallback = M0(단순 분산), 단 M0도 OOS 음수·book 미달.

## Next Recommended Increment
RAMP 하위게이트 추가 구현 아님. 한계는 Gate 4 데이터(팩터 decay) — 코드로 미해결. 재귀루프 정직 종료.
RAMP는 screen-tier 팩터-소스 / decay-모니터 역할로 확정. (L-code `L-RAMP-…GATE6_8_INVESTOR_20260619`)
