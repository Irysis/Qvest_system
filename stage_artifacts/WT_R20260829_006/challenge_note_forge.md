# challenge_note_forge — WT-R20260829_006 (JT1993 강화 6/20, EL2022 스패닝 검정)

Self-Adversarial Challenge (v8.2 — 외부 Codex 라운드 없음). forge 산출물을 스스로 적대적으로 검증한다.
대상: fabrication risk(schedule fidelity / SR provenance) + 측정 basis 약점.

권위 수치 정본 = `authoritative_remeasure.json`. 아래 어떤 항목도 등급을 손으로 바꾸지 않는다.

---

## F-01 [ACCEPT · HIGH] `detect_lookahead` CLEAN 은 거의 공허하다 — 양성 대조 1/3

양방향 대조 실측(`forge_pit_bidirectional.json`):
- 양성(선언 idiom 주입) **1/3 발화** — `sd(x)*sqrt(252)` 만 잡고 `quantile(dt$Ret_1m, .9)` · `scale(dt$score)` 는 **미발화**.
- 음성(비선언 idiom 주입) **0/5** — 전 표본 `mean()` · `cov()` · `shift(-1)` · 비중 재정규화 · `which.max` 전부 미발화.

5/20 forge 는 "선언 idiom 2/2 발화" 로 기록했는데 **본 라운드 재측정은 1/3** 이다. 즉 계기의 실효 커버리지는
문서가 시사하는 것보다 좁다. **CLEAN 을 PIT 증명으로 인용하지 않는다.** 실제 논거는 구조다:

| 구조 논거 | 실측 |
|---|---|
| forge 가 종목·비중을 만들지 않음 | 집행 (date,ticker) 6,200 쌍 = weights.csv 6,200 쌍, 초과 **0** |
| t → t+1 집행 | exec−sig 간격 min 1 · median 3 · max 11일, **0 이하 0건**/248 |
| 전 표본 통계 0 | 일별 NAV = 보유 주식수 × 당일 종가의 경로 누적 |
| top-N 재선택 부재 | `head()` 0회 · `setorder()` 2회는 (Date,−w,Ticker)/(nav,Date) 정렬 · `alpha_scores` 1회는 금지 주석 |

## F-02 [ACCEPT · HIGH] DSR 시행수 5 는 **이 라운드 안쪽만** 센다 — 사다리 누적을 세지 않는다

`n_trials_cumulative = 5` 는 optimizer 의 비중방법 5종 열거만 반영한다. 그러나 본 건은 **JT1993 강화 6/20**,
즉 같은 기저 논문 위 6번째 시도다. 진짜 누적 시행은 최소 6라운드 × 각 라운드의 내부 열거이며 DSR 0.436 은
**낙관 방향으로 치우쳐 있다**.

★판정 불변: DSR 은 이미 `dsr_min` 0.5 미달이고, PORT_t 1.002 가 B 문턱 2.0 에도 못 미쳐 등급은 시행수와
무관하게 C 다. 그러나 **"5" 를 누적 시행수로 인용하는 것은 사실이 아니다** — 라벨을 이 문서가 정정한다.

## F-03 [ACCEPT · MEDIUM] 실현 회전 9.386 > 상류 선언 8.739 (+7.4%)

optimizer 의 8.739 는 Σ\|Δw\| 연속 규약이고, forge 는 **정수 주식수 · 리밸 간 비중 표류 · 라운딩 잔여현금**
아래에서 실제 매매 명목을 센다. 실현 비용도 1.31% → **1.41%/yr** 로 커진다.

- 실격게이트 `turnover ≤ 11.0` 은 실현치에서도 통과(9.386)하므로 **선택은 뒤집히지 않는다**.
- 그러나 "회전 27% 감축" 이라는 상류 서술은 연속 규약 기준이며, share-based 실현에서는 **감축폭이 더 작다**.
  비용 절감 −0.486%p/yr 라는 회계적 확정치도 실현 basis 에서는 그만큼 축소된다.

## F-04 [ACCEPT · HIGH] 벤치 계열이 PORT_t 격차의 지배항 — 상류 1.221 과 권위 1.002 는 **다른 양**

2×2 귀속 실측(248개월, `forge_baseline_reconciliation.json`):

| basis | PORT_t | net_IR |
|---|---|---|
| upstream_strategy × alpha_BM (상류 보고) | 1.2211 | 0.2987 |
| upstream_strategy × forge_BM | 0.8934 | 0.2223 |
| forge_strategy × alpha_BM | 1.1881 | 0.2910 |
| **forge_strategy × forge_BM (권위·월별)** | **0.8695** | **0.2165** |

분해: 1.2211 → **벤치 교체 −0.3277** → 전략실현 교체 −0.0239 → 0.8695.
248개월 누적 벤치가 **4.983(production) vs 3.996(alpha panel)** 로 서로 다른 구성물이다. 5/20 과 같은 기전.

★그래도 판정은 불변이다 — 네 basis 전부 B 문턱 2.0 미만. 벤치 선택은 등급을 옮기지 않는다.
★권위 basis 는 production harness BM(`canonical_screen_bt`·`run_alpha_search`·essence 코퍼스 공통)이다.
  상류 PORT_t 를 권위 PORT_t 자리에 놓지 말 것.

## F-05 [PARTIAL] MDD 0.610(권위) vs 0.534(상류) — 해상도 차이지 악화가 아니다

권위 MDD 는 **일별 경로**, 상류는 **월말** 기준이다. 월말 basis 는 월중 낙폭을 못 본다. Calmar 는 이 MDD 를
분모로 쓰므로 권위 Calmar(0.216)가 상류(0.243)보다 낮게 나오는 것은 정상이다.

- 이것이 불공정한 페널티는 아니다 — essence 코퍼스 전체가 같은 일별 basis 이므로 비교 가능성이 유지된다.
- ★그러나 **MDD 는 등급을 접지 않는다**(도훈 지시 2026-08-24). 위험 축은 Calmar 하나이고,
  `structural_drawdown = FALSE` 이므로 구조 낙폭 라벨도 붙지 않는다. Calmar 0.216 < 0.64 로 탈락한 것이지
  MDD 61% 때문에 탈락한 것이 아니다.

## F-06 [ACCEPT · MEDIUM] deploy 연장 18거래일은 통계적 내용이 사실상 0

마지막 리밸(2026-07-31 신호 → t+1 집행) 이후 비중 동결로 2026-08-28 까지 **18거래일**을 연장 측정했다.
Deploy Extension Mandate 는 형식적으로 충족되나, 18일은 어떤 OOS 주장도 지탱하지 못한다.
**이 구간을 OOS 증거로 인용하지 않는다.** 진짜 OOS 축은 아래 F-07 이다.

## F-07 [REBUTTAL 불가 · 이 후보의 구속 축] OOS retention −0.78 은 측정 아티팩트가 아니다

- 권위: `oos_retention = −0.78`, `oos_band_status = fail`, 분할 3점 **[−0.484, −0.780, −1.272]**.
- 상류 근사(−0.458)와 **부호가 일치**하고, 분할이 뒤로 갈수록 단조로 악화한다.
- 부기간 IR 도 권위 basis 에서 재현: P1 0.833 / P2 0.283 / **P3(2020+) −0.369**.

세 계열(권위 essence · 상류 근사 · 부기간 분할)이 **같은 방향**을 가리킨다. 벤치 basis 를 바꿔도(F-04)
전략계열을 바꿔도(−0.024) 이 축은 움직이지 않는다. 회전 제어는 상류 주장대로 **감쇠를 완화만** 했다
(−0.376 → −0.301, 권위 재현 −0.369).

## F-08 [ACCEPT · 자기참조 고지] SR provenance 대조의 반쪽은 내가 만든 값이다

optimizer 는 SR 을 선언하지 않았다(`method_comparison` 에 sr 필드 없음). 그래서 `sr_factor_engine_continuous`
0.5787 은 **forge 가 `weighted_screen_bt` 로 상류 basis 를 재현한 값**이다. 즉 divergence
(same-frequency **+0.0070**, NEGLIGIBLE)는 독립 두 계열의 대조라기보다 **같은 비중을 두 집행 규약으로 돌린 대조**다.
- 그래도 유효한 정보가 있다: 연속-비중 집행과 정수-주식수 집행의 격차가 SR 0.007 수준이라는 것 —
  즉 share-based 실현이 성과를 만들거나 죽이지 않았다. fabrication 신호 없음.
- 재현 자체는 검증력이 있다: 상류 선언 PORT_t 1.219 를 **1.2211 로 재현**했다(소수 3자리).

## F-09 [ACCEPT · MEDIUM] as_of book 은 한 번도 측정되지 않았다

역사 248 리밸만 백테스트했고 as_of(2026-08-28) 25행은 제외했다 — 실현수익이 없으므로 옳다.
그러나 실제로 배포될 명부는 그 as_of book 이고, 상류 실측에 따르면 as_of 의 모멘텀 노출은
**+0.615σ** 로 역사 평균(+0.226σ)보다 크게 기울어 있다. **역사 248개월의 성질을 as_of book 에
그대로 전이하지 말 것** — 이 라운드의 어떤 수치도 as_of book 을 측정하지 않았다.

## F-10 [ACCEPT] 계기 세 개가 공허하게 PASS 했거나 무발화했다

| 계기 | 상태 | 대체 증거 |
|---|---|---|
| `schedule_fidelity_check.sh` | settings.json 미등록 + 필드명 불일치 → **무발화** | 산출물에서 직접 재도출: 248/248 = **1.000** |
| audit Check 16 (nav cadence) | `manifest$frequency` 가 `rebalance_frequency`('monthly')에서 채워져 월간 리밸 전략에선 **원리적 미발화** = 공허 PASS | 직접 재도출: nav 중앙 간격 1.0일 · 5,091 일별 관측 · af=252 |
| audit Check 13 (T+1) | 정규식이 `t+1`/`t1` 만 인식 → `t_plus_1` 표기는 skip | `execution_date_rule` 에 "T+1" 명시해 **실제 발화**시킴(sample 1건) + 248건 간격 실측으로 보강 |
| `wt_validate_package(.., "forge_package")` | **valid=TRUE 인데 switch 에 forge 분기가 없다** → `required_fields = character(0)` → 내용 무관 무조건 TRUE. 통과가 아니라 **검사 부재** | schema.json `forge_package` 정의의 required 10필드를 forge 가 직접 대조 — missing **0** |
| `schema.json:17` / `wt_list` 정규식 | `^WT-[DPSH][0-9]{8}_[0-9]{3}$` 와 `^WT-?[DP]?[0-9]{8}_[0-9]{3}$` 둘 다 v10 접두 `R` 미포함 → WT-R 계열 INVALID. `wt_type` enum 에도 `reinforcement` 없음 | 우회 없이 기록만(`forge_schema_probe.json`). 내용 기반 검증은 완주 |

★5/20 이 남긴 교훈("WARN skip 은 위반 없음이 아니라 미측정")을 처음부터 적용해 `factor_engine_path` 를
배선했다 — 그 결과 Check 8/14/15 가 실제로 돌았다(Check 14: lmf=0/align=0 hits · Check 15: 318줄 스캔).

---

## 종합

- **Hard Constraint 위반 0** — 25종/248리밸 전건, long-only, Σw=1(dev 2.2e-16), 회전 9.386 ≤ 11.0.
- **pure function 준수 실증** — 3-package md5 시작/완료 동일.
- **fabrication 신호 없음** — schedule density 1.000, SR divergence NEGLIGIBLE.
- **미해결 HIGH**: F-01(계기 커버리지) · F-02(DSR 시행수 라벨) · F-04(벤치 basis 혼동 위험) — 셋 다
  **판정을 뒤집지 않는다**(등급 C 는 네 basis·모든 시행수 가정에서 불변). Q-Lead escalate 불필요.
- **다음 층으로 넘기는 것**: RF-R1 시장 노출 68.8%(오버레이 층) · as_of book 미측정(F-09) ·
  OOS 소멸(F-07)이 이 계열의 구속 축이라는 사실.
