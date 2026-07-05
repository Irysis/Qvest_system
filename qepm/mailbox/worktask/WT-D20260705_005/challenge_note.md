# Self-Adversarial Challenge — WT-D20260705_005 (Alpha Research)

**대상**: RAMP 잔차-직교 sleeve 개별 배포-envelope PORT_t 스크리닝. verdict = 0/11 통과.
**방식**: v8.2 Opus 4.8 자체 적대검증 (외부 Codex 없음). finalize 직전 약점 자가제기 → 분류.

---

## 사전 정정 (request 모델 vs 실제 아티팩트 불일치 — HIGH severity, 정직 보고)

request.json `hypothesis_description`는 "18개 잔차-α 후보"를 `residual_alpha_candidates.parquet`가 담고 있다고
전제했으나, **실측 결과 그 파일은 479개 *기존 풀 전략*(batch_434/catalog STR_AS·ML)을 residual-variance로 랭크한 것**이며
"PC2~10 pure-factor 공간의 잔차-α 후보"가 아니다. 실제 잔차-직교 sleeve 구조는:

- `factor_group_scores.parquet` = **11개 직교 경제군**(Accruals/Composite/Consensus/Credit/Growth_Profit/LowRisk/Momentum/Quality/Reversal/Size_Liquidity/Value), 각 `group_z`, 257월.
- `factor_group_map.parquet` = PC2~PC10(9 PC) → 경제라벨 매핑.

RAMP `run_ramp_r1_sleeve_stack.R`(2026-06-18)가 정확히 "개별 sleeve를 canonical_screen_bt로 배포-envelope
실측"하는 스크립트이며, 그 대상은 이 **11 sleeve**다. 따라서 본 WT의 "개별 배포 스크리닝" = 11 sleeve 개별 실측.
"18"이라는 숫자는 request의 mental model 산물(어떤 아티팩트에도 정확히 18행 없음). **11 sleeve로 재정의하여 수행**했고,
이는 §6 미해결 항목("RAMP 잔차 sleeve 개별 PORT_t 검증")을 정확히 겨냥한다.

> ★ AX-000 정직보고: 후보 개수를 임의로 18에 맞추지 않고 실제 직교군 11개로 수행. 성공/실패 위장 아님.

---

## Concern 1 — rank-IC를 realized PORT_t로 오독했는가? (최대 함정, Cycle 2 교훈)

**자가제기**: Momentum rank-IC 0.040 / ICIR 0.506 / Harvey-t 8.09 (11개 중 최강 신호력). Consensus·Growth_Profit도
ICIR 0.42/0.34 강함. 이걸 "신호 있음 → 알파 있음"으로 오독하면 거짓 통과.

**처리 = ACCEPT-and-guarded**: 판정 권위를 **port_t_capwt (cap-w NW lag-3 net active)** 단일 기준으로 고정.
- 검증: 독립 계산 `port_t_capwt`가 contract 산출 `portfolio_alpha_t_nw_lag3`와 **소수점까지 일치**(Consensus 2.163=2.163,
  Momentum 0.514=0.514, 전 11개). → 계산 오류 없음, contract-grade.
- 결과: Momentum(rank-IC 최강)의 PORT_t는 **0.51**, post2017_t **−2.19**. 전형적 "rank-IC 강·PORT_t 약" 괴리.
  rank-IC를 authoritative로 썼다면 Momentum이 통과했을 것 — **PORT_t 채택이 정확히 이 거짓통과를 차단**.
- 결론: 오독 없음. 신호력(rank-IC)은 실재하나 long-only top-25 배포 alpha로 전이 안 됨(§6 "직교 ≠ 수익").

## Concern 2 — 소형주 틸트 누출 (EW-uni 낙관)

**자가제기**: RAMP EW-uni 헤드라인(Consensus 3.53)이 cap-w보다 훨씬 높음. EW-uni로 보고하면 배포 불가한
소형주 프리미엄을 알파로 착각.

**처리 = ACCEPT**: 두 벤치를 모두 산출하되 **cap-w(Size-weighted 시장프록시)만 authoritative**로 판정.
- Consensus: EW-uni 3.53 vs cap-w **2.16** (Δ≈1.37t = 소형주 틸트). Value: 2.00 vs 1.57.
- cap-w 기준 최댓값 2.16 < 2.95 → 배포 envelope에서 통과 0. EW-uni로 봤다면 Consensus가 "통과처럼" 보였을 위험을 차단.
- forward-return builder(`build_monthly_forward_returns`)가 `(K200|KQ150)` 필터를 내장 → 유니버스도 배포 envelope 준수.

## Concern 3 — 잔차 스코어 look-ahead (full-sample residualization)

**자가제기**: PC/FWL 잔차화가 full-sample loading으로 산출됐다면 C1 위반 → PORT_t가 (거짓)상향, FAIL도 낙관오염 가능.

**처리 = REBUTTAL (근거 제시)**: 코드 실측으로 look-ahead 부재 확인.
- `pure_factor_extraction.R::extract_pure_factor`: FWL 직교화(`fwl_orthogonalize(z, build_fwl_controls(rawdata, sig_d))`)를
  **per-signal_date 횡단면**으로 수행. loading을 미래 데이터로 적합하지 않음.
- `load_month_factors`는 PIT-safe(`data_available_date <= sig_date`, C14/C15). z-score도 월별 횡단.
- → C1(full-sample 금지) 준수. FAIL은 look-ahead 제거의 산물이 아니라 **실제 전이 실패**.
- 방증: RAMP 2026-06-18 감사가 asof-토글 test로 동일 파이프라인 look-ahead 부재 입증(prod 3.66 vs full-sample 4.38,
  코드가 ~0.72t 미래정보 제거) — 본 스코어 소스 동일.

## Concern 4 — 11-way 다중검정(sweep) → DSR

**자가제기**: 11개 sleeve 중 "best" 고르기 = sweep-shaped selection. 단일 통과분을 봤다면 DSR 게이트 대상.

**처리 = ACCEPT (진단 산출)**: DSR 계산.
- best = Consensus, net-active ann SR 0.49. E[max SR|null, N=11] ≈ 0.31. DSR ≈ **0.77** (>0.5 nominal).
- 해석: DSR 통과는 "Consensus가 11-way 선택 하에서도 순수 noise는 아님"을 뜻할 뿐(rank-IC 실재와 정합).
  그러나 **binding 게이트는 PORT_t(2.16<2.95)와 oos_retention(−0.17≪0.7)·calmar(0.39≪0.64)** — 전부 FAIL.
  DSR 0.77은 "신호 실재"이지 "배포 alpha"가 아님(§6 원칙 재확인). 어차피 통과 0이라 sweep-selection 자체가 무의미.

## Concern 5 (추가) — oos_retention 전원 음수: overfit인가 cohort decay인가

**자가제기**: 11개 sleeve **모두** oos_retention 음수(−0.17 ~ −5.16). 활성 Sharpe가 OOS에서 부호반전.
개별 전략 overfit인가, cohort-wide decay인가?

**처리 = 진단 확정 = decay-pattern(cohort-wide)**: **11개 전부** post2017_t 음수(−0.31 ~ −2.44) + 전부 oos 음수 →
전략-고유 과적합(일부만 나쁨)이 아니라 **KR post-2017 팩터 감쇠(cohort-wide)**. measurement-graduation §3 decay-pattern.
16/16 standalone FAIL·RAMP cap-w oos 0.15·6-슈퍼팩터 감쇠벽과 동일 posterior. 자본 졸업은 decay든 overfit이든 불가.

---

## 합리화 자기검증 (grep: 미미/관행/보수적/대부분동일)

본 노트에 "영향 미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일" 사용 없음. 모든 판정은 실측 수치(PORT_t·oos·calmar·post17_t)
+ contract 교차검증(port_alpha_t_contract 일치) 근거. self-rationalization auto-detect: 해당 없음.

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? → Concern 1의 request-모델 불일치 1건이 HIGH(정정 보고). 나머지는 정상 처리. 5 미달 → escalate 불요.
- AX axiom hard FAIL ≥3? → 해당 없음(리서치 verdict FAIL은 axiom 위반 아님).
- PIT C1(lockbox/lookahead) 위반? → Concern 3에서 부재 입증. → **escalate 불요.**

## 최종 verdict
- **0/11 HARD_PASS. 0/11 PORT_t≥2.95. 최대 PORT_t 2.16(Consensus).** screen-tier(≥1.5) 2개(Consensus·Value).
- 전 11개 oos_retention 음수 + post2017_t 음수 → cohort decay 벽 sleeve-레벨 일반화.
- **§6 미해결 항목("RAMP 18[=11]후보 개별 PORT_t 검증") CLOSED = 음성.** 개별 배포 스크리닝도 IC→PORT_t 전이 벽.
- survivors 0 → multi-sleeve 스택·book-marginal ΔIR 후속 **moot**(스택할 통과분 없음). AX-007 multi-sleeve escape route는
  본 후보군에서 미실증(재료 부재).
- Risk/Optimizer로 넘길 α̂ vector **없음**(통과 sleeve 0).
