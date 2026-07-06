# Self-Adversarial Challenge — WT-D20260706_007

**Value/quality spread-reversion 국면조건부 activation** (Alpha Research, Opus 4.8 self-adversarial per v8.2)

Devil's-advocate 자기비평 5건 제기 → ACCEPT / PARTIAL / REBUTTAL 분류 + 근거 + 합리화 자기검증. finalize 직전 수행.

---

## Concern 1 [ACCEPT] — spread 백분위 look-ahead 위험 (C1)
**비평**: valuation spread 백분위가 full-sample로 계산되면(현 spread가 사상최대라 backward-looking pctile은 자명히 100%) 조건부 activation이 미래참조가 된다.

**처리 (ACCEPT — spec 준수 확인)**: spread 백분위는 **expanding window** `mean(spread[1:i] <= spread[i])`로 계산(`02_build_factors.R` L: `exp_pctile`). 각 시점 t의 백분위는 t까지의 이력만 사용 — full-sample 아님(C1 준수). robustness (iii)에서 확인. 추가로 **lag-1 stress**(C2, `07_adversarial.R`) 수행 — spread 조건을 1개월 추가 지연시켜도 결과 붕괴 없음(concurrent PORT_t 0.06 → lag-1 0.92, 둘 다 unconditional 1.77 하회). look-ahead가 결과를 부풀린 정황 없음. **결론: PIT clean, 위반 아님.**

## Concern 2 [REBUTTAL] — reversion이 value-trap과 구분되는가
**비평**: 극단 spread에서 conditional activation이 실패한 것이 "reversion이 안 일어나서"인지 "reversion은 일어났으나 long-only가 못 잡아서"인지 구분 안 되면 결론이 모호하다. spread가 계속 벌어지는 value-trap이면 애초에 reversion 가설 자체가 틀린 것.

**처리 (REBUTTAL — 정량 근거로 구분 완료)**:
- **학술 근거**: Cohen-Polk-Vuolteenaho (2003, JF) "The Value Spread" + Asness et al. value-timing — value spread가 극단일 때 subsequent value long-short 프리미엄이 상승. 본 실측이 이를 KR에서 재현.
- **정량 3축**:
  1. **Reversion은 실재**: robustness (i) — 극단-spread 월(n=81) 진입 후 6M spread 변화 **−3.8%**(65% narrow) vs 전체평균 **+8.3%**(48% narrow). spread는 실제로 좁혀진다 = reversion 발생, trap 아님.
  2. **그러나 short-side 주도**: 극단-spread 월 내 quintile decomp(`04`) — cheapest Q5 long_side_t=**−0.34**(−4.18% ann), 반면 expensive Q1 short_side_t=**+1.71**(+21.46% ann). LS_spread_t=3.27은 전부 short-side. spread narrowing = **비싼주식 하락**이지 싼주식 상승 아님.
  3. **long-short 방향 확증**: full-period value LS_t=3.26이나 2017+ LS_t=0.38로 붕괴, 그 안에서 long_side 2017+ **−1.18**(value trap) / short_side +1.21.
- **L-code 정합**: [[reference-kr-value-factor-decay]] (KR value spread 사상최대·reversion 미검증) — 본 WT가 그 미검증을 검증 완료.
- **결론**: reversion과 trap을 명확히 구분함 — **spread-level reversion은 실재하나 realized payoff는 short-side. long-only 하베스트 불가.** 이것이 판정 핵심이지 모호성 아님.

## Concern 3 [REBUTTAL] — 개선이 long-side인가 short-side 아티팩트인가 (판정 핵심)
**비평**: 세션 벽(short-side-견인 × long-only = 미하베스트)을 우회하려면 long-side여야 한다. 개선이 short-side에서 온다면 못 잡는다.

**처리 (REBUTTAL — decomp가 명확히 short-side 판정)**:
- **long-side vs short-side 분해**(`04`, `07` C1/C3, 정량 3축):
  1. quintile: 2017+ value long_side_t=**−1.18**, short_side_t=**+1.21** — 최근 payoff 전부 short-side.
  2. top-25 names: full long_t25_t 1.86(+9.1%) 있으나 2017+ **−1.01**(−7.8%), short_b25 +0.85(+10%).
  3. **IC 비대칭**(C3, 결정적): 전체 rank-IC t=5.47이 강하나 이는 **expensive-half IC t=4.29**(2017+ 2.87)가 견인, **cheap-half IC t=2.6(2017+ 1.07 비유의)**. 싼주식 구간(long-only 서식지)의 신호력은 최근 무의미.
- **결론**: 개선의 원천은 **명백히 short-side**. Cycle-2 교훈 재확인 — rank-IC t(5.47) ≫ portfolio-alpha t(1.77)인 이유가 IC의 short-side 편중. **세션 벽 우회 실패.**

## Concern 4 [PARTIAL] — 현 spread 사상최대라 forward analog 희소 (정직 명시 의무)
**비평**: 현재 spread(pctile 1.000, z=+6.99, ratio 274.7)는 **역대 최고**라 "이 정도 극단에서의 forward reversion"에 대한 historical analog이 거의 없다. backtest는 "약한 형태"의 검정이며 현 국면 예측력은 제한적.

**처리 (PARTIAL — 인정 + 정직 명시)**: 인정한다. 본 backtest는 "극단-spread 월들의 subsequent 성과" 분포로 검정했으나 **현재만큼 극단인 관측치는 표본 내 사실상 유일**(202512~202607). 따라서:
- 결론 "conditional activation FAIL"은 **표본 내 극단-spread 월들에 대해 robust**(quintile·top25·placebo 일관).
- 그러나 "현재 274.7 ratio에서의 forward reversion"은 out-of-sample이며 backtest가 직접 커버하지 못함 — **정직 명시**. 만약 이번이 진짜 dot-com급 대반전이면 그 반전조차 short-side일 것(decomp 구조상 KR long-only β≈0.92 시장성분 지배 + 공매도 불가)이므로 하베스트 불가 예측은 유지되나, 이는 구조적 추론이지 이 극단점의 직접 실측 아님.
- challenge_flags에 `RF_forward_analog_sparse` 기록.

## Concern 5 [ACCEPT] — 다중검정(9 variants) 과적합
**비평**: A/B/C/D 9개 변형을 돌려 best를 인용하면 selection bias.

**처리 (ACCEPT — selection_type=chain, 그러나 best조차 FAIL이라 무의미)**: 
- 본 리서치는 sweep이 아닌 **가설주도 chain**(1가설: spread-conditional이 unconditional을 개선하는가). 변형은 argmax pick이 아니라 A(baseline) 대비 B/C/D delta를 보는 대조 설계.
- 그럼에도 **best full PORT_t=1.77(unconditional)조차 2.95 하회**, 모든 conditional delta 음수(−0.42~−1.71), 모든 2017+ PORT_t 음수. selection bias 방향으로 유리하게 골라도 FAIL — 다중검정이 결론을 뒤집지 않음. placebo(ii) p=0.899로 spread-timing이 random 대비 무개선 확증.

---

## Self-rationalization auto-detection
사용 표현 스캔: "미미/관행적/실무적/보수적이면 OK/대부분 동일" — **미사용**. 모든 판정은 정량 수치(PORT_t·IC t·ann%·placebo p) 기반. Concern 4의 "제한적"은 회피가 아니라 표본 희소성의 정직 명시(라벨 `RF_forward_analog_sparse`).

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? → No (본 결과는 clean FAIL, escalation 아닌 정상 emit).
- AX axiom hard FAIL ≥3? → No.
- PIT C1(lockbox·lookahead) 위반? → No (expanding pctile + lag-1 stress clean).
→ **escalate 불필요. 정상 ALPHA_DONE emit.**

## 종합 판정
**FAIL (정직).** value/quality spread-reversion conditional activation은 unconditional 대비 개선 없음(delta 전부 음수). spread-level reversion은 실재하나 payoff가 **short-side 주도**(2017+ long_side_t −1.18 vs short_side +1.21; extreme-spread 월 long −0.34 vs short +1.71) → **long-only 미하베스트 = 세션 벽 재확인**. rank-IC t=5.47의 강함은 expensive-half(short-side) 편중 아티팩트. → DIST-QPM-006/003에 **supporting 강화 emit**(reversion 각도까지 테스트됨, short-side 벽 확증).
