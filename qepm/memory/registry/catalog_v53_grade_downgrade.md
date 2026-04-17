# Catalog v53 — Grade Downgrade 전략 (Session 65~66 확정)

- **세션**: 65 carry → 66 (Pass 1.2 실행)
- **작성자**: Judge teammate
- **작성일**: 2026-04-17
- **근거**: Session 65 Judge sweep v2 AMBIGUOUS_GRADE_LOWER 카테고리
- **목적**: Grade A 명목이었으나 실제 hurdle v2.2 재실행 시 Grade B 기준에 해당하는 전략 기록. EXPEL은 아니며 Grade B로 존속.

## G4 Grade B 정정 (2건)

| 전략 | 이름 | v2 Grade 명목 | v2 Grade 실측 | v2 SR | v2 MDD | Score | 사유 |
|------|------|--------------|--------------|-------|--------|-------|------|
| STR_1555 | score_blend_3factor | A | **B** | 1.095 | 29.28% | 64.0 | hurdle v2.2 재실행 Grade B (JUDGE_PASS_LOWER). 기존 "Grade A_NOVEL" 주장 근거 부족. |
| STR_1571 | c19_v14_d01_l22_dd_regime | A | **B** | NA | NA | 55.7 | SR/MDD 누락. Grade B (JUDGE_PASS_LOWER). hurdle_result 일부 필드 결손. |

## 판정 근거 (hurdle v2.2)

### STR_1555
- CAGR, SR, MDD 모두 **Grade A 경계 미달**
- Grade A 기준: score>=40 && CAGR>=16% && SR>=0.8 → 조건 일부 충족
- Grade A_NOVEL 기준: score>=40 && CAGR>=12% && SR>=0.6 && novelty_bonus>=10 → novelty_bonus 측정 미완
- SR 1.095 > 0.8 ✓, MDD 29.28% < 45% ✓, 그러나 score 64 vs hurdle A 기준 일부 조건 미달
- **최종**: Grade B (수용 가능한 성과이지만 Grade A 기준 아님)

### STR_1571
- hurdle_result.json SR/MDD 필드 누락 — Grade A 판정 불가
- Score 55.7만으로는 Grade A 확정 불가 (score>=40 조건만 충족, CAGR/SR/MDD 조건 unverified)
- **최종**: Grade B (데이터 복구 또는 재실행 시 재판정 가능)

## 영향

- **Session 65 기준 Grade A 카탈로그 명목 34건** → **32건** (Grade B 2건 정정)
- v3 Pass 2 (G8 11건) 대상에서 제외 (애초 PASS_STATIC 분류 아님)
- MEMORY.md "PG2: 2건 (STR_1555 포함)" 주장 **재확인 필요** (STR_1555 Grade B 전환 시 PG2 재평가)

## Grade B 존속 의미

- Grade B는 **hurdle v2.2 완전 미달**이 아닌 **Grade A 경계 미달**
- 참조용 및 비교용으로 유지 (archive 아님)
- PG1 편입 후보에서 **제외** (PG0 gap 해소 기여도 낮음)
- 향후 개선 mutation 시 baseline으로 활용 가능

## Session 66 Pass 2 연계

G4 정정이 Pass 2 실행 범위 축소:
- G8 원 11건 (PASS_STATIC) + G4 2건 재검토 검토 중
- **결론**: G4는 Grade B 확정으로 Pass 2 동적 재검증 대상 아님
- Pass 2는 G8 11건만 집중

Pass 1.2 확정.
