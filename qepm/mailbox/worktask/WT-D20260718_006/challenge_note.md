# Self-Adversarial Challenge — WT-D20260718_006 (직접 exogenous forecasting + ML 조합 발굴)

**규율**: v8.2 Self-Adversarial (Opus 4.8 native, 외부 Codex 없음). finalize 직전 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL 분류 + 근거. Charter §8 No Silent Override.
**판정 요약**: 직접 E[r_factor] forecasting (6 경제논리 × ML 조합발굴) = **NEGATIVE (config-scoped)**. factor-momentum baseline을 OOS에서 이기지 못함 + 전 config oos_retention<0.
**Vintage pin**: RAWDATA_pin20260703 + benchmark_pin20260703 + exog_pin20260718wt006. 유니버스 KOSPI200∪KQ150 (~313/mo), top-25 EW long-only, cap-w KOSPI200 벤치, 15bps, liq 2e8, OOS 2012-12~2026-06 (163mo, WT-005와 동일).

---

## Concern 1 — [ACCEPT] "best" config를 OOS port_t로 사후 선택 = OOS-peeking (DSR/lag 진단에)
**약점**: DSR·lag-1 stress를 "best forecasting config"(GBM_seed0, OOS port_t 최대)에 대해 산출 = OOS를 보고 고른 것. 순수 protocol 위반 소지.
**처리 (판정 불변 실측)**: 선택-peeking은 **진단 리포팅에만** 적용되고 **VERDICT는 peeking-invariant**. 핵심 판정 = "어떤 config도 momentum baseline을 OOS에서 못 이긴다" — 이는 사후선택과 무관하게 **전 9 config paired_vs_mom_t<0** (best조차 -0.359, ensemble -0.736, EN들 -1.4~-2.4). oos_retention도 전 config <0. 모델 학습·feature/combo 선택은 walk-forward IS-only(train fold 내 CV lambda, beta=2 고정 — OOS 무조회)로 clean. DSR/lag를 최상위 config에 산출한 것은 "가장 유리한 후보조차 게이트 통과 못 함"을 보이는 **보수적(불리한 방향) 진단** — 판정을 부풀리지 않음. ACCEPT하되 결론 영향 없음 명시.

## Concern 2 — [ACCEPT] rich 외생변수인데 momentum 못 이김 = feature-poor가 아니라 방법 미달 아닌가 (더 강한 모델?)
**약점**: EN/GBM은 저용량 모델. transformer/deep-net·더 많은 상호작용이면 momentum을 이길 수도.
**처리 (REBUTTAL 근거로 ACCEPT-bounded)**: 
- WT-005가 **from-scratch transformer를 이미 측정** — momentum에 seed 전부 열위(paired_vs_mom -0.65~-1.70), HKS OOS-fragility. 즉 "더 큰 모델"은 이미 부정 실측 — 재시도 저EV.
- 본 WT는 의도적으로 **parsimonious(EN/GBM)** — HKS 교훈(고용량=IS강/OOS취약)에 맞춘 legitimate 선택. GBM이 static은 확실히 이김(paired_vs_static 1.85) → 신호력은 실재하나 **OOS-realize가 벽** (momentum tilt가 이미 그 realize 가능분을 포착).
- 병목 진단: oracle ceiling(WT-005) 12.894 → headroom은 있으나 **모든 timing 방법이 OOS서 감쇠**. 이는 모델 용량이 아니라 **post-2020 cohort-wide 팩터 감쇠**(smart-beta 13-agent 실측 = "2017+ 팩터 감쇠 근본벽"). rich exog로도 감쇠 견디는 조합 부재.
**처리**: "방법 미달" 가능성 인정하되, 상위 용량(transformer)은 WT-005서 부정 확인 + 병목이 방법 아닌 감쇠임을 per-logic 전멸(6/6 oos_ret<0)로 실증. next_probe에 "non-return 팩터-timing predictor"(용량 아닌 **새 정보원**)를 남김.

## Concern 3 — [PARTIAL] macro/credit conditioning의 PIT (동월 누출 / 미래 macro)
**약점**: 신용스프레드·VIX·fin-stress를 month-end level로 쓰면 동월 정보 흘림 가능. forward-macro 예측 금지(settled-null) 위반 소지.
**반증**:
- macro/credit = **conditioning-only** (현재 관측 level at month-end t, market-observable 일간 시계열의 <=t 최종값 rolling-join). **미래 macro 예측 없음** — 모델은 현재 조건 하 팩터수익을 예측. forward-macro null 준수.
- **lag-1 PIT stress(의무)**: best config 1.127 → +1lag 0.766. **완만 감쇠, 붕괴 없음** — 동월 누출이면 lag1서 ~0 붕괴(BearProb 사건 패턴). 누출 부재 실증.
- 재무 lag C4 = factor_db@t 상속. trailing 팩터수익 shift(1) 실현<t.
**처리**: PIT-clean. 단 macro month-end level이 "완벽 t-1"보다 관대할 여지(신용지표 공표 지연 수일) 인정 → lag-1 stress가 방어. kill_3 미발화.

## Concern 4 — [PARTIAL] ML 조합발굴 = sweep인데 DSR만으로 충분한가 / n_trials 과소계상
**약점**: EN 7 + GBM 1 + val 1 = n_trials=9로 셌으나, 실제 탐색공간(31 feature × 상호작용 × lambda grid × 3 seed)은 훨씬 큼. DSR 과대(관대)평가 가능.
**반증**: 
- feature/lambda 선택은 **walk-forward fold 내부 CV** = 각 fold의 IS 데이터로만 → OOS 다중검정 아님(fold-internal). 외부 다중검정 단위 = "내가 canonical A/B로 판정한 config 수" = 9가 정직.
- 그럼에도 DSR **0.419 < 0.5 FAIL** — n_trials를 더 크게 잡으면 DSR 더 낮아짐(더 FAIL). 즉 과소계상이어도 **판정 방향 불변**(오히려 강화).
- **바인딩 게이트는 DSR이 아니라 oos_retention** (전 config <0) + paired_vs_mom (<0). DSR은 보조.
**처리**: n_trials=9는 "canonical-판정 config 수" 정의로 정직. 방향 보수적. PARTIAL 인정하되 결론 강건.

## Concern 5 — [REBUTTAL] static base가 약해(OOS -0.047) forecasting이 쉽게 이긴 착시 아닌가
**약점**: base가 약하면 아무 tilt나 static은 이김 → paired_vs_static 1.85가 과대.
**반증**: 핵심 판정은 static 대비가 아니라 **momentum 대비**. momentum(port_t 1.277)은 강한 baseline이고 forecasting은 이를 **못** 이김. static 약함은 momentum 문턱을 낮추지 않음(둘 다 같은 OOS). paired_vs_static은 "신호력 실재" 보조증거일 뿐 graduation 근거 아님.
**처리**: 결론 불변. static-peeking으로 부풀린 것 없음.

## Concern 6 — [ACCEPT] Ret_1m sanity 방화벽 78건 격리 = 데이터 vintage 우려
**약점**: canonical_screen_bt가 78 물리불가 월수익(Ret_1m>5.0) 격리 경고 — pin vintage에 sanitize 미적용분.
**처리**: 격리는 **전 config 동일 적용**(같은 grid_returns) → paired 비교 basis-invariant. 격리 대상 = non-index microcap 아티팩트(메모리 project-rawdata-ret-firewall). top-25 지수종목 포트에 물질 영향 미미(라이브 무관, 실측 확립). WT-005도 동일 vintage. ACCEPT하되 paired 판정 불변.

---

## 자기-합리화 auto-detection
"미미/관행적/보수적이면 OK/대부분 동일" 점검: Concern 6서 "물질 영향 미미" 사용 → **근거 강화**: 격리 78건 전부 Ret>5.0(비지수 microcap), top-25 EW 지수종목 선택에 미포함 확률 지배적 + 전 config 동일 basis → paired-delta 불변(수학적). 합리화 아닌 basis-invariance 논거. 그 외 회피표현 미사용. NEGATIVE 판정 = pre-registered kill_1(momentum 미달)+kill_2(oos_retention<0)+DSR FAIL 실측 근거.

## Q-Lead escalation trigger 점검
- HIGH severity ≥5: NO
- AX axiom hard FAIL ≥3: NO (AX-001 v2는 조건부 소폭 개선 — hard fail 아님)
- PIT C1(lockbox·lookahead) 위반: NO (lag-1 clean, macro conditioning-only, IS-only)
→ **escalate 불요.**

## Next-probe (continuity, ≥2)
1. **factor-momentum(유일 실신호, 감쇠)을 overlay/FR regime 입력으로** — WT-005 상속. EW-uni/regime-conditional서 oos_retention 회복 여부(2020+ 감쇠 = mega-cap 레짐 아티팩트인지).
2. **Non-return 팩터-timing predictor** — DART insider 집계 포지셔닝·팩터별 공매도잔고 등 return/valuation/credit-파생 아닌 새 정보원. return/valuation/credit/dispersion 파생 timing은 본 WT로 OOS-bounded 종합 특성화 완료.
**부활조건**: 임의 config oos_retention ≥0.7 (EW-uni/regime framing) OR non-return predictor가 momentum paired_vs_mom_t>1.7.
