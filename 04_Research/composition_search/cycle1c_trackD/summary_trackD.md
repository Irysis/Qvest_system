# Track D — 3-슬리브 동적 배분 (Cycle 1c) Summary

**Mandate**: 도훈 2026-06-12 — "밸류 슬리브까지 추가해서 비중 동적 조절 + 컨센서스 모멘텀 스코어 검토"
**Prereg**: `prereg_trackD.json` (TRACKD_3SLEEVE_DYNAMIC_PREREG_v1, FROZEN 2026-06-12, n_trials=6, selection_type=sweep)
**metric_type**: backtested · 247 calendar months (2005-09~2026-03) · cost v2.4_kr_retail_15bps · overlay 없음 (S0/S1 금지 준수)

## 판정: 축 CLOSED — ALIVE 0/6

alive 기준(사전등록): IS dSR≥+0.10 ∧ OOS dSR≥0 ∧ full dMDD≤+2pp.

| trial | 규칙 | full SR | IS dSR | OOS dSR | full dMDD | 2017+ dSR | w_val평균 | ALIVE |
|---|---|---|---|---|---|---|---|---|
| B_static2 | core65/def35 (baseline) | 0.786 | — | — | — | — | 0 | — |
| T1 | static w_val=10% | 0.803 | +0.037 | −0.019 | +0.012 | −0.040 | 0.10 | FALSE |
| T2 | static w_val=20% | 0.813 | +0.063 | −0.045 | +0.027 | −0.087 | 0.20 | FALSE |
| T3 | EP spread z>+0.5 타이밍 | 0.776 | −0.010 | −0.009 | +0.040 | −0.007 | 0.015 | FALSE |
| T4 | esbr 컨센 사이클 z<0 | 0.767 | −0.008 | −0.040 | +0.024 | −0.032 | 0.037 | FALSE |
| T5 | trailing 12m 상대 SR (control) | 0.828 | +0.073 | −0.008 | −0.007 | −0.013 | 0.088 | FALSE |
| T6 | 36m inverse-vol 3-sleeve (cap 30%) | 0.800 | +0.080 | −0.116 | +0.047 | −0.186 | 0.294 | FALSE |

- 전 trial **(a) IS dSR<+0.10 (최고 T6 +0.080)** + **(b) OOS dSR 전원 음수** (value 비중↑일수록 OOS 악화).
- DSR 전원 ~0.99 (게이트 통과하나 deflate할 alpha 부재 — 무의미).

## 근본 원인 — 직교성 부재 (substrate 실측)

cor(core, value)=**0.593** / cor(def, value)=**0.508** / cor(core, def)=0.695. pre-overlay 슬리브 레벨에서 value는 직교가 아니며(헌법 measurement-graduation §6 재확인), 정교한 조건화로 구제될 천장 자체가 낮다. "동적 배분 방법의 실패"가 아니라 "직교 소스 부재 → 어떤 배합도 한계효익 음전"의 재현.

## T4 부산물 — 컨센서스 모멘텀 메커니즘 역전 (FR 모드 후보)

가정(컨센 약세 → core 굶음 → value 보완)이 데이터에서 역전:

| 국면 | n | core SR | value SR | 평균 core ret |
|---|---|---|---|---|
| esbr z≥0 (컨센 강) | 201 | 0.59 | 0.55 | +1.15% |
| esbr z<0 (컨센 약) | 46 | **1.68** | 0.95 | **+4.10%** |

esbr 약세 월 = 시장 전반 강세 국면 (spearman(esbr_z, 익월 core ret) = −0.109). esbr은 value-tilt trigger로 부적합. 단 "esbr 약세=강세 국면" 관계 자체는 factor-rotation 모드 국면변수 후보로 별도 추적 가치 (본 트랙 범위 밖, 미검증 라벨).

## 엔지니어링 노트 (load-bearing)

`PerformanceAnalytics::Return.portfolio`에 full-period weight xts를 주면 **첫 행을 drop해 N−1행 반환** → 외부 벡터(ym/bm_ret)와 recycle 오정렬 위험. 수정 컨벤션(b1/Track W와 동일): weight xts를 r_idx−1로 dating해 N행 보존 + **반환 xts의 index로 re-merge** (외부 벡터 길이 가정 금지). 본 트랙에서 수정 전 baseline PORT_t 1.77 → 수정 후 3.05 (판정 방향은 수정 전후 동일: ALIVE 0/6).

## 처분

- "value 3rd-sleeve 동적배분" = mode-local negative axiom 후보 (INV-7 provisional failure-ledger — 재도전 대상, 불변 법칙 아님).
- 선행 결과 일관성: 보정 static blend ΔSR≤0 (value_sleeve_combination/corrected/) · FR Rotate<Static · 국면-IR 조건화 4중 기각.
- 산출물: prereg_trackD.json · prep_trackd_substrate.R · run_trackd.R · results_trackD.{csv,json} · intermediate/{sleeve_monthly,value_spread_z,consensus_esbr_z}.csv
