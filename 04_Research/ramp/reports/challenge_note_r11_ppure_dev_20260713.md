# Self-Adversarial Challenge — RAMP R11: P-pure 발전 chain (FQ-024)

- **작성**: 2026-07-13 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체, AX-008 3-source 중 1)
- **대상 산출**: `outputs/ramp/r11_ppure_dev_{prereg,gates,paired,conc,summary}_20260713.*` · runner `02_Infrastructure/ramp/run_ramp_r11_ppure_dev.R` · L-code `L-RAMP-20260713_093129`
- **사전등록**: `r11_ppure_dev_prereg_20260713.json` (config_hash `53403eaf16de7662`, 측정 전 sha256 동결). **selection_type=chain** (sweep 아님 — 각 arm이 R7/R8/R10 진단에 1:1 대응)
- **base parity**: R11 base cap-w PORT_t 2.6124 vs R6 저장 2.6124 → |Δ|=1.39e-5 (bit-consistent)

## 측정 요약 (cap-w authoritative)

| arm | 기전(진단 대응) | cap-w PORT_t | EW-uni | oos | calmar | post17SR | TO | paired full (IS / OOS) |
|---|---|---|---|---|---|---|---|---|
| base (EW×EW) | — | 2.612 | 3.919 | −0.076 | 0.450 | −0.105 | 9.27 | — |
| armF cadence3 | 선별 신선도(풀 staleness) | **2.852** | 4.238 | **+0.121** | 0.471 | **+0.105** | 9.28 | +0.42 (−1.11 / +1.44) |
| armB band2535 | 보유밴드(경계 churn) | 2.414 | 3.665 | −0.121 | 0.448 | −0.183 | 6.81 | −0.57 (−0.26 / −0.62) |
| armV vintage | 선별-vintage 앙상블 | **2.895** | 3.729 | +0.087 | 0.476 | +0.037 | 8.93 | +0.58 (−0.11 / +1.62) |
| comb armV×sqrt | 2차 결합 | 2.848 | — | +0.085 | 0.468 | — | — | (IS −0.116 < 승자 −0.106 → 폐기) |

- **1차 IS-only 승자** = armV_vintage (IS paired −0.106 = 전 arm 중 최소 음수. 전 arm IS<0). chain 규율: OOS 미조회.
- **판정 KILL_chain=TRUE**: max full paired +0.582 < 2.0 · HARD 3종 0/5 · best oos +0.121 << 0.7 target.

## 스스로 제기한 약점 (≥3) — ACCEPT / PARTIAL / REBUTTAL

### C① [task 지정] "armF 선별 cadence 단축 = factor-momentum 타이밍(06-30 NULL)의 재현" **[REBUTTAL]**
- 제기: 갱신 주기를 6→3개월로 당기면 결국 '최근 이긴 팩터를 더 자주 쫓는' factor-momentum 타이밍이 되고, 06-30 factor-of-factors momentum timing NULL과 수렴한다.
- 검증(3중 반증): (a) **풀 churn/refresh는 오히려 감소** — cadence6=0.307 → cadence3=**0.206**. 빠른 갱신은 trailing-36m 창을 3개월씩만 밀어 스텝이 작다(추종이면 churn이 커야 하나 반대). (b) **trailing_t rank 자기상관은 상승** — 0.86 → **0.92**(풀 sticky 유지, 추종 신호 아님). (c) **stock TO는 flat** — 9.27 → 9.28(Δ+0.01). 회전 폭증이 factor-momentum의 지문인데 부재. → armF 개선(oos −0.076→+0.121·cap-w 2.61→2.85·post17SR 부호전환)은 '더 신선한 풀'이지 '최근 승자 추종' 아님. 06-30 prior 부적용.
- **정직 caveat**: armF 연간 누적 회전은 소폭↑(cadence3 0.206×4≈0.82/yr vs cadence6 0.307×2≈0.61/yr)이나 broad 20-팩터 composite + top-25 종목선택이 흡수해 stock TO·비용 중립. 개선은 유의(paired 2.0) 미달·**OOS-집중**(IS −1.11 / OOS +1.44).
- 분류 **REBUTTAL**: factor-momentum 수렴 반증(churn↓·AC↑·TO flat). 단 효과 자체는 non-significant.

### C② [task 지정] "armB 보유밴드가 oos 개선 없이 IS만 올린다(경계 잡음)" **[ACCEPT — 기전 FALSIFIED]**
- 제기: S3_consensus_band(paired +2.03) 선례를 근거로 밴드를 넣었으나, 밴드가 IS만 부풀리고 oos는 못 올리면 경계 churn은 잡음이 아니라 in-sample 과최적화다.
- 검증: 실측이 제기보다 **더 부정적** — 밴드는 IS도 OOS도 못 올린다. paired **IS −0.259 · OOS −0.615**(둘 다 음·OOS가 더 나쁨) · oos_retention −0.076→**−0.121 악화**. TO는 대폭 절감(9.27→**6.81**, name_churn/reb 7.07)에도 net이 나빠짐 = **경계 churn이 잡음이 아니라 신호**. P-pure top-25 경계의 신규 진입명이 알파를 보유하고, 히스테리시스(이탈 rank>35까지 보유)가 감쇠명을 지연 보유해 손해. S3_consensus_band는 다른 신호(earnings-3m consensus)에서 경계=잡음이었으나 **P-pure composite 경계=신호** — 기전 substrate 의존, 미전이.
- 분류 **ACCEPT**: 밴드 기전 이 substrate서 falsified(경계 churn=신호). 질문의 'IS만 개선'조차 아닌 전면 음(technicality 아닌 실패).

### C③ [task 지정] "armV 코호트 상관이 높으면 분산 축소 실효 없다" **[PARTIAL ACCEPT]**
- 제기: 3개월 offset 두 코호트가 거의 동일한 풀을 고르면 앙상블의 timing-luck 분산 축소는 nil이고 armV의 우위는 우연이다.
- 검증: trailing_t **Spearman 0.923**(코호트 고상관) · K20 pool **Jaccard 0.671**(2/3 중첩). 코호트는 상당히 닮았으나 **동일하지 않다**(1/3 풀이 다름) → 겹치지 않는 1/3이 앙상블 엣지 제공 → armV가 best cap-w(2.895·R10 W-stock 2.930와 사실상 tie). 단 상관 0.92가 높아 분산 축소는 **modest** — full paired +0.58(IS −0.11 winner-by-default)로 marginal. 효과는 실재(Jaccard<1)하나 작다.
- 분류 **PARTIAL ACCEPT**: 분산 축소 실효는 있으나 코호트 고상관으로 modest·non-significant.

### C④ "1차 IS 승자가 전부 음수인데 armV를 '승자'로 부르는 것이 오도" **[ACCEPT — scope 정밀화]**
- 제기: 세 arm IS paired 전부 음(F −1.11 / B −0.26 / V −0.11). IS서 어느 arm도 base를 못 이기는데 armV를 '승자'로 표기하면 개선을 과대.
- 검증: 정확 — **IS-only에선 no arm dominant**(armV는 '최소 음수'). 실신호는 **OOS-집중**(armF/V OOS paired +1.44/+1.62 vs IS 음수). chain 규율(§3 ii: 변형 선택 IS-only)상 OOS로 승자 선택 **불가** → '승자'는 형식적 지목. 정직 프레임: 구조 선별 조정은 **최근/OOS 창서 도움·IS서 약손해 → full 상쇄**(감쇠 추적 target 방향이나 net-불충분). 보고에 '승자=형식·OOS 개선=unselectable' 명기.
- 분류 **ACCEPT**: 승자 지목은 nominal. 개선의 실체=OOS-집중·유의 미달로 정직 병기.

### C⑤ "armV 2.895가 R10 W-stock 2.930과 tie — R11이 다른 축으로 같은 near-miss를 재발견한 낭비" **[REBUTTAL]**
- 제기: R10(비중축)과 R11(선별축)이 둘 다 cap-w ~2.9·oos 부호전환에서 멈추면 R11은 새 정보 없이 같은 벽을 재확인했을 뿐.
- 검증: 이것이 오히려 **정보값** — 선별 신선도(F)·vintage 앙상블(V)·비중 틸트(R10 W-stock) 세 **독립 construction 축**이 전부 cap-w ~2.85-2.93 천장·oos 부호전환에서 정확히 멈춘다 = 바인딩 제약이 **construction 디테일 불변(basis-invariant)**임을 입증. 벽의 위치가 construction-invariant라는 것은 "다음에 무엇을 바꿔야 하는가"(=construction 아니라 substrate/재료)를 확정하는 진단. R7/R8 cap-tier 국소화×cap-w 미스매치 확증과 정합.
- 분류 **REBUTTAL**: 독립 축의 동일 천장 = 벽의 construction-invariance 확증(낭비 아닌 방향 확정).

### C⑥ "OOS paired +1.44/+1.62(F/V)가 실재 신호인가, 2020+ 레짐 우연인가" **[ACCEPT caveat]**
- 제기: IS 음·OOS 양의 프로파일은 OOS 구간(2020+ 메가캡 반도체 레짐)의 국소 행운일 수 있다. n_OOS=77서 +1.4~1.6은 2.0 미달.
- 검증: 정확 — OOS paired 둘 다 2.0 미만(non-significant, n=77). '개선'은 방향성 진술이지 유의 주장 아님. 2020+ 레짐 얽힘(reference-kr-2025-megacap-semi-regime) 배제 불가. 보고서 '유의 미달·방향성만' 명기.
- 분류 **ACCEPT caveat**: OOS 개선 = 방향성, 유의·레짐-독립 주장 안 함.

## 자기합리화 detect
- **거짓 성공 차단**: armV 2.895·armF oos +0.121을 'graduation 근접'으로 승격 금지 — cap-w<2.95·oos<<0.7·paired<2.0·HARD 3종 0/5·KILL=TRUE 명시. best-ever oos near-miss는 방향성이지 자본 자격 아님.
- **문턱 이동 없음**: IS_FRAC 0.65·paired 2.0·HARD 3종 전부 prereg(config_hash 53403eaf16de7662) 측정 전 동결. base parity Δ=1.4e-5 bit-consistent.
- **chain 규율 준수**: 승자 지목 IS-only(OOS 미조회) · 2차 결합 승자 확정 후 · IS 악화로 결합 폐기(사전등록 규칙 그대로) · DSR 진단용(chain → 게이트 부적용).
- **과대판결 차단**: armB '밴드=신호' 결론은 이 substrate 한정(S3 선례 부정 아님). armF 'factor-momentum 아님'은 이 측정 지문(churn/TO) 근거 — 일반 명제 아님.

## 최종 분류
**PARTIAL** — chain은 규율대로 완주(base parity·IS-only 승자·결합 폐기). 라운드 target(oos·감쇠 추적)은 **방향성 개선 실측**(armF oos −0.076→+0.121·post17SR 부호전환·armV cap-w 2.895)이나 **net-불충분**(full paired +0.582<2.0·HARD 3종 0/5·oos<<0.7·개선 OOS-집중·IS 음). 적대 라운드가 판정을 못 뒤집고 scope 정밀화: **(C①) armF≠factor-momentum(churn↓·AC↑·TO flat); (C②) armB 밴드 기전 falsified(경계 churn=신호); (C③) armV 분산축소 실효는 modest(코호트 0.92 고상관); (C④) 승자 지목은 nominal, 실개선=OOS-집중·unselectable; (C⑤) 세 독립 construction 축의 동일 ~2.9 천장 = 벽 construction-invariant.** 메타: **P-pure 구조 개선 chain(선별 신선도/밴드/vintage/비중)은 소진** — cap-tier 국소화×cap-w 벽은 본 라운드가 못 풂(사전 명시대로). 남은 발전 경로 = **재료**(R9 DART insider 비-수익 패널, FQ-001). return-derived substrate 위 construction 튜닝은 R4~R11 일관 벽.
