# Catalog v53 — HARD EXPEL 전략 (Session 65~66 확정)

- **세션**: 65 carry → 66 (Pass 1.1 실행)
- **작성자**: Judge teammate
- **작성일**: 2026-04-17
- **근거**: Session 65 Judge sweep v2 (`stage_artifacts/nojudge_sweep_v2_final_20260417.json`) + Governor 승인
- **목적**: Grade A 카탈로그에서 영구 제거된 전략의 기록 유지. L-code 인용은 살려두되 PG1/PG2/PG3 편입 후보 pool에서 제외.

## HARD EXPEL 대상 (4건)

### G1 PIT_FAIL_MAJOR (C11_FRED + C5_DD + C11_MRS 3중 오염)

| 전략 | 이름 | v2 SR | v2 MDD | 위반 | 사유 |
|------|------|-------|--------|------|------|
| STR_943 | oc_eps_chg | 1.312 | 22.11% | C11_FRED, C5_DD, C11_MRS | FRED month-end published for full month (lookahead) + DD overlay same-day circular + MRS timing issue. Governor 경고와 일치. |
| STR_944 | oc_sue | 1.429 | 22.76% | C11_FRED, C5_DD, C11_MRS | 동일 3중 오염. |

**참고**: strategy_catalog.md (Session 40) Rank 8/10 "BEST Consensus Score 72.2/69.8"는 구 MRS + FRED lookahead로 **과대추정 확정**. 실질 Grade 불가. Session 65 L-441 (구 MRS 무효 교훈) 적용.

### G3 HURDLE_FAIL (Gate 3 미달 or Grade downgrade)

| 전략 | 이름 | v2 Grade | v2 Score | v2 SR | v2 MDD | 사유 |
|------|------|---------|---------|-------|--------|------|
| STR_1417_esbr_hrp_tc_dd620 | esbr_hrp_tc_dd620 | B | 34 | 1.091 | 28.33% | Grade B 확정 — hurdle v2.2 기준 Grade A 미달. JUDGE_REJECT. |
| STR_1550_consensus_core_alpha | consensus_core_alpha | C | 86.6 | NA | NA | hurdle_result SR/MDD 누락. Grade C. JUDGE_REJECT. 기존 PG2 claim 근거 상실. |

## 영향 (PG2 편입 pool 재평가)

**제거 전**: MEMORY.md "PG2: 2건 (STR_1550 + STR_1555)" 주장 (outdated). 실제 active Grade A 재검증 필요.

**제거 후 (Session 65 기준 실질 PG2)**: 
- STR_1631_SYN_05 80% (v2 PASS PIT clean)
- STR_1656_MLRA_M05 20% (PG2 완료건)
- STR_1550/STR_1555 제거 확정

**portfolio_gap_vector v1.0.3 참조**: STR_1550/STR_1555는 과거 기록일 뿐 실제 active pool 아님 (MEMORY §"PG2" 메모 이전 기록). 본 expel은 기록 정정의 의미.

## L-code 인용 유지 여부

- **STR_943/944**: L-441 (구 MRS) + L-448 (MRS 무효) 인용 유지. 실패 사례로 참고용. 단 Grade A pool 재진입 금지.
- **STR_1417_hrp/STR_1550**: 기존 L-code 인용 유지 (발생 교훈 훼손 금지). Grade A 재진입 금지.

## 재진입 조건 (미래 재검토 시)

HARD EXPEL 전략이 재검토 가능해지려면 다음 4조건 모두 충족:

1. C11_FRED / C5_DD / C11_MRS / C10_LIQ / C15 위반 **zero** (detect_lookahead 0 violation)
2. hurdle v2.2 재실행 + Grade A 확정 (score>=40, CAGR>=16%, SR>=0.8, MDD<45%)
3. Role Honesty Audit PASS (Core/Diversifier/Defense 위장 없음)
4. DSR >= 0.5 (Harvey t>3.0 defense)

단 **STR_943/944은 C11_FRED 원천적 구조** — 수정 시 전략 identity 바뀌므로 사실상 재진입 불가.

## Session 66 Pass 1 Pass 2 연계

- Pass 1.1 (본 문서): HARD EXPEL 4건 확정.
- Pass 1.2 (별도): G4 Grade B 정정 2건 (STR_1555/STR_1571).
- Pass 2: G8 11건 PASS_STATIC 동적 재검증 (DSR + FF5 + Role Honesty + LOO).
- Pass 3: Forge 패치 완료 후 G5/G6/G7/G2 17건 재검증.

v3 완료 시 strategy_catalog.md **전면 재작성** (Session 40 outdated 버전 대체).
