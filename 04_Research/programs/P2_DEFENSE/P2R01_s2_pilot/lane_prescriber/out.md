## 처방전 — RF_PAR_B6_36_2nmax (P2R01 s2 pilot · 처방 담당)

> 재료: `analyst_report.md` · `diagnosis_packet.md`(보는 창 2005-02-02 ~ 2022-12-29) · `paper.txt`(arXiv 2002.06975) · `paper_engine.R` · `charter.md` · `toolbox.md`. 인용 수치는 전부 패킷·헌장(R 계약 산출)이며 새로 계산한 값은 없습니다(AX-008). τ_D 이후 정보는 쓰지 않았습니다.

### 0. 들어가기 전 — 재료 기준으로 분석가 판독 2건을 정정합니다

**① 논문 원문이 읽힙니다**(`paper.txt`). 분석가 레인에서 막혔던 부분이 확인됐고, 두 가지가 처방 좌표를 바꿉니다.

- 논문 §3.4: *"While the long-short portfolio cannot take advantage of the stock market growth, it is robust against a large market crisis (i.e., the financial crisis during 2007-2008) **because of its market neutral position**."* → 논문이 위기 내구성을 귀속한 곳은 횡단면 점수가 아니라 **시장중립 포지션**입니다.
- 논문 §3.5: 롱 전용 판의 평가 대상은 `Alpha = 유니버스 전 종목 평균수익 대비 초과`이고, MaxDD 는 `R_strategy = A_t`(= 그 초과수익 누적 경로)의 낙폭입니다(Table 3 DNN5 MaxDD −3.46%). **논문은 절대 낙폭 방어를 주장한 적이 없고**, 벤치가 등가중 유니버스 평균이므로 **크기(EW−CW) 성분은 논문의 알파가 아니라 논문의 벤치 안에 들어 있습니다**. 이 칸에서 측정되는 +3.69%/yr(몫 0.26)은 논문 엣지의 일부가 아니라 롱온리·등가중 집행의 부산물입니다 — 그래도 CAGR 여유가 4.2%p뿐이므로 근거 없이 끄면 안 됩니다.
- 논문 §3.1: 유니버스는 TOPIX500(**대형·중형**), 입력 No.19~33 은 **월말 갱신**. 즉 신선한 입력은 60일 이내 가격·거래량·컨센서스 변화뿐이라는 분석가 판독은 원문으로 확인됩니다.

**② 크기 분위 기여 표(패킷 §4 끝)는 '소형 손실' 서사를 지지하지 않습니다.** MDD 창(2017-11)에서 **분위 1 은 +5.19%(27종)**로 플러스이고 손실은 분위 4 −16.34% · 분위 10 −10.45% · 분위 9 −10.22% · 분위 3 −6.90% 에 있습니다. 2007 은 분위 8 −16.80% · 7 −16.04%, 2011 은 분위 9 −5.86% · 8 −4.15%, 2021 은 분위 2 −4.35% · 6 −3.84%. 손실은 중형·대형 띠에 걸쳐 있고 최소 분위가 손실의 자리인 창은 없습니다. → **정적 `size_band` 처방은 이 패킷으로 정당화되지 않습니다**(§4 참조).

**겨냥 좌표**(헌장 §2 · 패킷 §2·§3): 보는 창 PORT_t 3.938 에서 S ≥ 1 에 필요한 Calmar = **0.528**(현재 0.39) · CAGR 0.202 유지 시 최대낙폭 ≤ 0.383(현재 0.516). 별개 하한으로 **롤링 36M 통과율 45%**(최근 0%) < 0.5. 두 관문이고, 낙폭만 고쳐서는 통과하지 않습니다.

---

## RX1 — 하방 비대칭 축을 종목 선택에 넣는다 (종목축 · 상시)

| 항목 | 내용 |
|---|---|
| **겨냥 약점** | W2(하방 운반 · 하락장 베타 1.15 vs 상승장 1.00) · 보조로 W4 |
| **바꾸는 축** | `factors` 하나 |

**기전.** 논문은 시장 성분을 숏 다리로 중화하고 위기 내구성을 그 중립성에 귀속시켰습니다(§3.4). 이 칸은 롱온리·Σw=1 로 그 중화를 전액 포기했고(패킷 §3·§4: 평균 노출 1.00 · 시장 적재 0.99 · 베타 1.04), 그 대가가 **하락장 1.15 / 상승장 1.00** 입니다. 한편 시장 성분이 초과수익에 보태는 몫은 0.02(0.28%/yr)에 그치는데 위기 손실 상위 종목의 기여 분해에서는 시장 성분이 대개 최대 항목입니다(A004800 −4.65% 중 −3.60% · A091700 −3.85% 중 −1.64% · A006360 −1.59% 중 −1.31%). **수익엔 거의 기여하지 않고 위험만 나르는 적재**가 있다는 뜻입니다.

그래서 깎을 것은 노출 수준이 아니라 **적재의 비대칭**입니다. `D07_Beta_Asymmetry`(= 하방베타 − 상방베타 · lower_better)는 수준 축(변동성·베타 레벨)이 아니라 **차이** 축이라 분석가가 경고한 "저베타·저변동 = 대형주 틸트" 교란을 가장 덜 받고, 정의상 **상방베타를 깎는 이름에는 벌점을 주지 않습니다** — 헌장이 요구하는 비대칭(하락 포착↓ · 상승 참여 유지)과 부호가 정확히 일치합니다. 점수 결합은 기저 가중 0.5 고정 · 나머지 0.5 를 넷이 나누므로 기저 신호 몫은 그대로이고 알파 3종이 0.167 → 0.125 로 희석됩니다.

**구현(delta).** `factors` = M01_Mom_12_1 · V10_FCF_Yield · M08_Residual_Mom · **D07_Beta_Asymmetry**. 그 외 축(비중 entropy · 리밸 buffer_2x · 유니버스 · 오버레이 none · 방어 슬리브 none)은 기저 그대로.

**기대 방향**(패킷 기준점 인용 · 새 계산 없음)
- 위기 하락 포착: 중앙 **0.95 → 하락**, 최악 **1.25 → 하락**(1.25 가 움직이는지가 이 처방의 생사).
- 상승 포착: **1.90 유지~소폭 하락**(하한 0.55 대비 여유 큼) · 하락장 베타 1.15 → 1.00 쪽 · 상승장 베타 1.00 유지.
- Calmar **0.39 → 상승** · CAGR 20.2% 에서 희석만큼 소폭 하락 가능(하한 16%) · PORT_t 3.94 소폭 하락 가능.
- MC8: 개선이 **선택·기전 방어**로 기록되기를 기대. D07 상위가 대형에 쏠리면 크기 짝 자체가 바뀌어 `size_defense` 로 남을 수 있음 — 기저 50%(짝 돌파 위기 비율)를 기준으로 읽습니다.

**보존할 강점 · 확인 지표.** 선택 알파의 일별 일관성 → `performance.strategy.port_t` · 강세 참여 → `behavior.summary.bull_up_capture_median` · `behavior.stats.beta_up` · 실력 방어 2건(2007 p 0.025 · 2021 p 0.005) → `controls.attribution.median_placebo_p` · 실력 라벨 유지 → `controls.attribution.share_beats_size_exposure` · 얇은 수익 여유 → `performance.strategy.cagr`.

**반증 조건**(하나라도 참이면 기각) — 아래 JSON 과 동일.
① 상승 포착 중앙 < 0.55 ② CAGR < 0.16 ③ Sharpe < 0.8 ④ PORT_t < 2.0 ⑤ 하락 포착 중앙이 기저 −0.03 보다 개선되지 않음 ⑥ 하락 포착 **최악**이 기저 −0.05 보다 개선되지 않음(W2 자기 반증) ⑦ 하락장 베타가 기저 이하로 내려가지 않음 ⑧ Calmar ≤ 기저 ⑨ 롤링 통과율이 기저 −0.05 미만.

**위험.** ① D07 상위가 대형·저위험 쪽이면 개선이 `size_defense` 로 재라벨 ② 알파 3종 희석(0.167→0.125)이 선택 성분(몫 0.84)을 비례 이상 꺾을 수 있음 ③ **상시 켜진** 방어 틸트라 강세년(2005 +30.9%p · 2007 +43.5%p · 2013 +33.6%p · 2015 +41.0%p 류) 참여를 깎을 수 있음 — 조건부인 RX3 과의 대조가 그 몫을 가릅니다 ④ D07 은 하방·상방 베타 추정 표본에 의존해 신규 상장·단기 이력 이름에서 잡음이 클 수 있음(패킷 밖 · 측정 필요).

---

## RX2 — 회전 상한을 자기 과거 분포에서 세운다 (리밸축 · 비용)

| 항목 | 내용 |
|---|---|
| **겨냥 약점** | W3(지평 불일치 → 회전·비용) · 보조로 롤링 36M 정체 관문 |
| **바꾸는 축** | `rebalance` 하나 |

**기전.** 논문은 5영업일 표적 신호를 **5개 트랜치로 쪼개 매 영업일 하나씩만** 리밸하고 모델은 5영업일마다 갱신합니다(§3.4 · Figure 1) — 그 목적을 원문이 직접 적습니다: *"In order to reduce the chances of having no other good portfolio by holding only one of the five portfolios"* · *"reduces the impact of rebalancing timing on performance"*(§2 끝). 즉 논문의 높은 회전(Table 3 DNN5 TN **56.06%**)은 **분산된 작은 거래**로 치러진 비용이고, 결론에서도 *"DNN models are higher turnover ratio"* 를 한계로 적습니다. 이 칸은 그 구조를 **월 1회 단일 트랜치**로 압축했습니다 — 리밸당 Σ|Δw| **1.27** · 연 회전 **15.43** · 연 비용 부담 **2.33%**(패킷 §5), 비용 몫 **−0.16**(§4). 결정적 수치: **MDD 창에서 비용 −5.2% 의 절대값이 그 창 초과 −3.8% 보다 큽니다**(§4). 네 위기 전부에 비용이 음으로 작용합니다(−2.4 / −0.9 / −5.2 / −2.7) — R6 지속성이 구조적으로 확보되는 유일한 축입니다.

`turnover_cap` + `expanding_median` 은 **월간 결정 시점을 유지**한 채(정보를 한 달 버리는 `interval` 과 다릅니다) 그 달 회전이 자기 과거 회전 분포의 중앙값을 넘을 때 **순위가 낮은 한계 거래만 유보**합니다. 문턱은 상수가 아니라 자기 이력에서 확장창으로 나오므로 하드코딩도, 미래참조도 없습니다.

**구현(delta).** `rebalance` = `{"kind":"turnover_cap","stat":"expanding_median","min_hist":3}`(min_hist = 스펙 하한). ★이 값은 기저의 `rank_buffer 2x` 를 **교체**합니다(한 기전 = 한 축). 버퍼가 빠져 회전 절감이 상쇄되면 아래 반증 ④가 잡습니다.

**기대 방향**
- 연 회전 **15.43 → 하락** · 연 비용 부담 **2.33% → 하락**.
- CAGR **20.2% → 상승 또는 유지**(절감 > 알파 손실일 때만). 상승 포착 **1.90 유지**(노출·선택 방향을 건드리지 않음).
- 위기 하락 포착: 직접 겨냥이 아니라 **간접** — 네 창의 비용 성분이 줄어드는 만큼 중앙 0.95·최악 1.25 가 완화. Calmar 는 주로 CAGR 경로로 상승.
- 롤링 통과율 **0.45 → 상승 기대**(비용 절감은 모든 창에 누적). 세 처방 중 **정체 관문을 직접 건드리는 유일한 처방**입니다.
- MC8: 비용 절감은 크기·노출 짝과 무관 → 귀속 라벨 변화는 작을 것.

**보존할 강점 · 확인 지표.** CAGR → `performance.strategy.cagr` · 일별 일관성 → `performance.strategy.port_t` · 강세 참여 → `behavior.summary.bull_up_capture_median` · 비중 분산(유효 23.9) → `profile.eff_n_mean`.

**반증 조건.** ① 상승 포착 중앙 < 0.55 ② **CAGR < 기저**(= 선택 알파 손실이 비용 절감보다 크다 · W3 자기 반증) ③ CAGR < 0.16 ④ 연 회전이 기저 −2.0 보다 줄지 않음 ⑤ 연 비용 부담이 기저 −0.003 보다 줄지 않음 ⑥ Calmar ≤ 기저 ⑦ PORT_t < 2.0 ⑧ 롤링 통과율 < 기저.

**위험.** ① `rank_buffer 2x` 교체로 버퍼 효과가 사라져 절감이 상쇄 ② 5영업일 표적 신호를 느리게 들면 선택 알파가 비용 절감보다 **먼저** 꺼진다 ③ 회전 상한이 위기 중 위험 축소 거래까지 유보해 낙폭을 키울 수 있다 ④ 지평 감쇠(5일 표적의 1·2·3개월 전방 IC)가 패킷에 없다 — **이 처방의 측정이 그 시험을 대신합니다**(분석가 측정 필요 1번).

---

## RX3 — 추세 지속성 상태를 보유 베타 순위로 소비한다 (상태축 · 조건부)

| 항목 | 내용 |
|---|---|
| **겨냥 약점** | W2(하방 운반) — 상태축 판 · 보조로 W1(위기별 크기 부호 반전이 깊이 아닌 지속 국면에 몰림) |
| **바꾸는 축** | `overlay` 하나 |

**기전.** 패킷의 가장 구조적인 사실은 **이 책에 시장 상태에 반응하는 층이 하나도 없다**는 것입니다(§1 오버레이 none · 방어 슬리브 none · 평균 노출 1.00). 논문 기준으로도 그렇습니다: 입력 33(이 칸 31)에 시장 상태 변수가 없고, 입력·출력 모두 **그날 횡단면 순위로 재척도**됩니다(§3.2) — 점수는 설계상 "시장이 위험하다"를 표현할 수 없습니다. 논문은 그 공백을 숏 다리로 메웠고(§3.4), 롱온리 칸에서 그 자리를 메울 수 있는 층은 오버레이뿐입니다. P2_DEFENSE 라운드에서 이 축을 아예 시험하지 않으면 주 가설이 미측정으로 남습니다.

상태를 **낙폭 깊이가 아니라 추세 지속성**으로 읽는 이유: 전기간 MDD 를 세운 창은 **29개월(2017-11-03→2020-03-19 · 전략 −51.6% · 하락 포착 1.25)**이고, 도구 상자가 깊이 기반 계열의 구조적 한계를 그대로 적습니다 — *"느린 침식은 깊이가 극단으로 안 가므로 수중 기간이 가장 긴 국면에서 가장 덜 개입한다"*(그 계열은 스칼라 25회·횡단면 18회로 포화). `trend_persist_tilt` 는 시장이 자기 12개월 추세 아래에 **연속으로 머문 개월수**를 상태로 쓰고(문턱 = 그 연속 길이의 확장창 경험분위 · 상수 없음), 축소량을 **그 달 보유의 시장베타 횡단면 순위**에 비례시켜 배분합니다. 스칼라 축소보다 평균 노출을 덜 깎으면서 축소 몫을 운반이 큰 이름에 몰아주는 구조 — R5 의 노출 짝을 넘을 수 있는 유일한 형태입니다. 신호는 보유 시작 전 데이터만 쓰며 엔진이 집행합니다(C5).

**구현(delta).** `overlay` = `{"kind":"trend_persist_tilt","arm_id":"trend_persist_tilt"}`. 그 외 축은 기저 그대로(Σw ≤ 1 은 오버레이 층에서만 생깁니다).

**기대 방향**
- 위기 하락 포착: 중앙 **0.95 → 하락**, 특히 지속형 창(2007-10 · 2017-11 · 2021-06). **2011(5개월 급락)에서는 상태가 길지 않아 거의 안 켜질 수 있습니다** — R6 지속성이 부분 실패할 수 있는 지점.
- 상승 포착 **1.90 → 하락**(개입 달의 노출 축소 · 하한 0.55 는 여유) · 비대칭(상승÷하락 중앙)은 **개선**되어야 함 — 그게 이 처방의 존재 이유.
- 평균 노출 **1.00 → 1 미만** · Calmar 상승 기대 · CAGR 하락 위험(하한 16% · 여유 4.2%p).
- MC8: 노출이 1 미만이 되는 순간 노출 짝이 **실질 대조**가 됩니다(기저의 "노출 짝 돌파 75%" 는 평균 노출 1.00 이라 사실상 "벤치보다 덜 빠진 위기 3/4"과 같은 말이었습니다). 횡단면 배분이 그 짝을 넘는지가 '기전 방어 vs 노출 방어' 판정 지점.

**보존할 강점 · 확인 지표.** 강세 참여 → `behavior.summary.bull_up_capture_median` · `behavior.stats.beta_up` · CAGR → `performance.strategy.cagr` · 기전 방어 여부 → `controls.attribution.share_beats_exposure` · 과도 축소 감시 → `controls.exposure_profile.mean`.

**반증 조건.** ① 상승 포착 중앙 < 0.55 ② CAGR < 0.16 ③ Sharpe < 0.8 ④ PORT_t < 2.0 ⑤ 하락 포착 중앙이 기저 −0.05 보다 개선되지 않음(노출로 지불하므로 RX1 보다 큰 폭을 요구) ⑥ **비대칭이 기저 이하**(= 하락·상승을 같이 깎았을 뿐) ⑦ 노출 짝 돌파 비율이 기저 미만 ⑧ Calmar ≤ 기저 ⑨ 롤링 통과율이 기저 −0.05 미만.

**위험.** ① 2011 형 급락에서 미발화 → R6 부분 실패 ② 개선이 '노출 방어'로 기록될 수 있음 ③ 강세 전환 초기에 상태가 늦게 풀리면 반등 참여를 놓쳐 상승 포착·CAGR 이 함께 내려감(헌장 비대칭 위반 방향) ④ 상태가 **시장** 추세라 2016(전략 −17.3% / 벤치 +8.2%) 같은 종목축 실패년에는 작동하지 않음 — 정체 관문은 이 처방이 고치지 않습니다.

---

## 최종 후보 선택 규칙 (보는 창 정보만)

1. 반증을 통과한 처방만 후보.
2. **R6 지속성 필터**: 처방 패킷 3절 위기 표에서 "하락 포착이 같은 판본 기저 대비 **0.03 이상** 개선된 위기"가 **2건 이상**인 처방만 남긴다(한 창 맞춤 배제). 남는 처방이 없으면 **선정 없음**.
3. 남은 후보 중 `performance.strategy.calmar` 최고 1건.
4. Calmar 차가 0.02 이내면 `performance.strategy.cagr` 높은 쪽 → 그다음 `performance.strategy.port_t` 높은 쪽.
5. 그래도 가르지 못하면 **선정 없음**(다음 라운드). 모든 비교는 보는 창(≤2022-12-29) 수치만 사용.

## 안 고른 레버와 이유

| 레버 | 보류 이유 |
|---|---|
| `universe: size_band` | 크기 분위 기여 표가 지지하지 않음 — MDD 창 분위 1 은 **+5.19%(27종)**, 손실은 분위 4·9·10 · 2007 은 분위 7·8. 게다가 크기 성분은 CAGR 원천(+3.69%/yr · 몫 0.26)이고 여유가 4.2%p뿐. |
| **W1 직접 처방** | 도구 상자에 크기 적재를 **시변**으로 바꾸는 축이 없습니다(size_band · cap_core · S01_Size 전부 정적). 정적으로 끄면 2011(+5.6%)·2021(+7.9%) 방어와 수익을 함께 내놓습니다. RX3 가 "크기 부호가 뒤집히는 국면" 쪽에서 간접적으로만 닿습니다. |
| `cap_core` | 벤치 근접으로 낙폭은 줄지만 알파를 희석해 PORT_t 가 내려가고 — 헌장 §2 산술상 **PORT_t 하락은 필요 Calmar 를 올립니다**. 정체 관문(롤링 45%)에 대한 부호도 보는 창 재료로는 예측 불가. |
| `defense_sleeve: factor_topk` | 매달 k 자리 교체가 회전을 늘려 RX2 와 상충하고, 같은 라운드에서 둘의 순효과를 가르기 어렵습니다. RX1 이 기각되면 "어떤 방어 특성이 듣는가"를 as-of IC 규칙에 맡기는 이 레버가 다음 라운드 1순위입니다. |
| 추세 계열 팩터 추가 | 기저 18/31 + M01 + M08 이 이미 추세 — 새 기전이 아닙니다(R3). |

## 측정 필요 (패킷 밖 · 이 라운드가 답하는 것/못하는 것)

- **답한다**: 지평 감쇠(RX2 의 측정이 곧 시험) · 하방 비대칭 축의 종목 선택 효과(RX1) · 상태축 개입이 노출 짝을 넘는지(RX3).
- **여전히 못 답한다**: ① 위기 직전 달 보유의 하방베타·베타 비대칭 횡단면 분포(RX1 기전의 직접 확인) ② 2017-11 창의 침식 구간 vs 2020-03 급락 구간 낙폭 몫(RX3 상태 선택의 근거) ③ 롤링 36M 통과 기준의 정의와 실패 창 시점 분포(`rolling_grade.R`) ④ 선택 성분 0.84 의 내부 귀속(기저 DNN 몫 vs 결합 팩터 몫) — RX1 의 희석 위험 크기를 여기서만 알 수 있습니다.

```json
{"prescriptions": [
  {"id": "RX1",
   "name": "하방 비대칭 축(D07)을 결합 팩터에 추가 — 종목축 상시",
   "targets": ["W2", "W4"],
   "mechanism": "논문은 위기 내구성을 횡단면 점수가 아니라 롱숏의 시장중립 포지션에 귀속한다(paper §3.4 'robust against a large market crisis because of its market neutral position'), 롱 전용 판의 MaxDD 는 유니버스 등가중 평균 대비 초과수익 경로의 낙폭이다(paper §3.5 · Table 3) — 즉 논문은 절대 낙폭 방어를 주장하지 않는다. 이 칸은 롱온리로 그 중립성을 전액 포기했고(패킷 §3·§4 평균 노출 1.00 · 시장 적재 0.99 · 베타 1.04 · 하락장 1.15 vs 상승장 1.00) 시장 성분의 초과수익 몫은 0.02(0.28%/yr)뿐인데 위기 손실 상위 종목 기여의 최대 항목은 대개 시장 성분이다(A004800 -4.65% 중 -3.60% · A091700 -3.85% 중 -1.64%). 따라서 노출 수준이 아니라 적재의 비대칭을 깎는다. D07_Beta_Asymmetry = 하방베타 - 상방베타(lower_better)는 수준 축(변동성·베타 레벨)이 아닌 차이 축이라 대형주 틸트 교란이 가장 작고, 상방베타를 지키는 이름에 벌점을 주지 않아 헌장의 비대칭 요구와 부호가 일치한다. 기저 신호 가중 0.5 는 고정이고 나머지 0.5 를 넷이 나눈다.",
   "implementation": {"factors": [{"kind": "db", "id": "M01_Mom_12_1"}, {"kind": "db", "id": "V10_FCF_Yield"}, {"kind": "db", "id": "M08_Residual_Mom"}, {"kind": "db", "id": "D07_Beta_Asymmetry"}]},
   "expected": {"crisis_dd_capture": "중앙 0.95 기준 하락 · 최악 1.25 가 내려가는지가 핵심(소폭~중폭)",
                "bull_up_capture": "1.90 유지~소폭 하락(하한 0.55 대비 여유 큼) · 하락장 베타 1.15 는 상승장 1.00 쪽으로, 상승장 베타는 유지",
                "calmar": "0.39 기준 상승(낙폭 축소 경로) · 목표 0.528 까지 단독으로 닿을지는 미지",
                "port_t": "3.94 기준 유지~소폭 하락(알파 3종 0.167→0.125 희석) · CAGR 20.2% 에서 소폭 하락 가능(하한 16%)",
                "mc8": "선택·기전 방어로 기록되기를 기대. D07 상위가 대형에 쏠리면 크기 짝이 바뀌어 size_defense 로 남을 수 있다 — 기저 짝 돌파 50% 를 기준으로 읽는다"},
   "preserve": [{"what": "선택(특이) 알파의 일별 일관성 — 패킷 §4 선택 11.96%/yr · 몫 0.84 의 대리", "check": "performance.strategy.port_t"},
                {"what": "강세 참여(상승 포착 중앙 1.90) — 복리의 원천", "check": "behavior.summary.bull_up_capture_median"},
                {"what": "상승장 베타 1.00 — 상방 적재를 깎지 않았는지", "check": "behavior.stats.beta_up"},
                {"what": "무작위 크기 짝을 넘은 실력 방어 2건(2007 p 0.025 · 2021 p 0.005)", "check": "controls.attribution.median_placebo_p"},
                {"what": "실력 라벨 — 개선이 크기 방어로 되돌아가지 않는지(기저 0.50)", "check": "controls.attribution.share_beats_size_exposure"},
                {"what": "얇은 수익 여유 — CAGR 20.2%(하한 16%)", "check": "performance.strategy.cagr"}],
   "falsification": [{"field": "behavior.summary.bull_up_capture_median", "op": "<", "value": 0.55},
                     {"field": "performance.strategy.cagr", "op": "<", "value": 0.16},
                     {"field": "performance.strategy.sharpe", "op": "<", "value": 0.8},
                     {"field": "performance.strategy.port_t", "op": "<", "value": 2.0},
                     {"field": "behavior.summary.crisis_dd_capture_median", "op": ">=", "ref": "base", "delta": -0.03},
                     {"field": "behavior.summary.crisis_dd_capture_worst", "op": ">=", "ref": "base", "delta": -0.05},
                     {"field": "behavior.stats.beta_down", "op": ">=", "ref": "base", "delta": 0},
                     {"field": "performance.strategy.calmar", "op": "<=", "ref": "base", "delta": 0},
                     {"field": "behavior.rolling.pass_life", "op": "<", "ref": "base", "delta": -0.05}],
   "risks": ["D07 상위가 대형·저위험 쪽이면 크기 분포가 바뀌어 개선이 size_defense 로 재라벨된다(R5 에서 실력으로 세지 않음)",
             "결합 팩터 3종이 0.167→0.125 로 희석되어 선택 성분(몫 0.84)이 비례 이상 꺾일 수 있다",
             "상시 켜진 방어 틸트라 강세년(2005 +30.9%p · 2007 +43.5%p · 2013 +33.6%p · 2015 +41.0%p) 참여를 깎을 수 있다 — 조건부인 RX3 과의 대조가 그 몫을 가른다",
             "D07 은 하방·상방 베타 추정 표본에 의존해 단기 이력 이름에서 잡음이 클 수 있다(패킷 밖 · 측정 필요)",
             "정체 관문(롤링 36M 45%)은 이 처방이 직접 고치지 않는다"]},

  {"id": "RX2",
   "name": "회전 상한을 자기 과거 회전 분포의 확장창 중앙값으로 — 리밸축 비용 절감",
   "targets": ["W3"],
   "mechanism": "논문은 5영업일 표적 신호를 5개 트랜치로 쪼개 매 영업일 하나씩만 리밸하고 모델을 5영업일마다 갱신한다(paper §3.4 · Figure 1), 그 목적을 원문이 직접 적는다 — 'In order to reduce the chances of having no other good portfolio by holding only one of the five portfolios' · 'reduces the impact of rebalancing timing on performance'(§2). 즉 논문의 높은 회전(Table 3 DNN5 TN 56.06%)은 분산된 작은 거래로 치른 비용이고 논문 스스로 결론에서 'DNN models are higher turnover ratio' 를 한계로 적는다. 이 칸은 그 구조를 월 1회 단일 트랜치로 압축했다 — 리밸당 Σ|Δw| 1.27 · 연 회전 15.43 · 연 비용 부담 2.33%(패킷 §5) · 비용 몫 -0.16(§4) · 결정적으로 MDD 창에서 비용 -5.2% 의 절대값이 그 창 초과 -3.8% 보다 크다(§4). 비용은 네 위기 전부에서 음이다(-2.4/-0.9/-5.2/-2.7) → R6 지속성이 구조적으로 확보되는 유일한 축. turnover_cap + expanding_median 은 월간 결정 시점을 유지한 채(정보를 한 달 버리는 interval 과 다르다) 그 달 회전이 자기 과거 분포 중앙값을 넘을 때 순위가 낮은 한계 거래만 유보한다 — 문턱은 상수가 아니라 자기 이력의 확장창 통계다(하드코딩·미래참조 없음).",
   "implementation": {"rebalance": {"kind": "turnover_cap", "stat": "expanding_median", "min_hist": 3}},
   "expected": {"crisis_dd_capture": "직접 겨냥 아님 — 네 창의 비용 성분(-2.4/-0.9/-5.2/-2.7)이 줄어드는 만큼 중앙 0.95·최악 1.25 가 간접 완화",
                "bull_up_capture": "1.90 유지(노출·선택 방향 불변) — 상승 포착을 깎지 않는 유일한 축",
                "calmar": "0.39 기준 상승, 주로 CAGR 경로(연 비용 2.33% 절감분)",
                "port_t": "3.94 유지~상승(일별 순수익 평균이 올라가고 분산은 비슷) · 롤링 통과율 0.45 → 상승 기대 = 세 처방 중 정체 관문을 직접 건드리는 유일한 처방",
                "mc8": "비용 절감은 크기·노출 짝과 무관 → 귀속 라벨 변화는 작을 것(기저 size_defense 유지 예상)"},
   "preserve": [{"what": "선택 알파 — 회전을 늦춰도 5일 표적 신호가 살아 있는지(W3 의 자기 반증 지점)", "check": "performance.strategy.cagr"},
                {"what": "일별 초과수익 일관성 PORT_t 3.94", "check": "performance.strategy.port_t"},
                {"what": "강세 참여 1.90 — 이 축은 상승 포착을 깎지 않아야 한다", "check": "behavior.summary.bull_up_capture_median"},
                {"what": "비중 분산(유효 종목 23.9/25.0) — 회전 통제가 책을 좁히지 않았는지", "check": "profile.eff_n_mean"}],
   "falsification": [{"field": "behavior.summary.bull_up_capture_median", "op": "<", "value": 0.55},
                     {"field": "performance.strategy.cagr", "op": "<", "ref": "base", "delta": 0},
                     {"field": "performance.strategy.cagr", "op": "<", "value": 0.16},
                     {"field": "profile.turnover_annual", "op": ">=", "ref": "base", "delta": -2.0},
                     {"field": "profile.cost_drag_annual", "op": ">=", "ref": "base", "delta": -0.003},
                     {"field": "performance.strategy.calmar", "op": "<=", "ref": "base", "delta": 0},
                     {"field": "performance.strategy.port_t", "op": "<", "value": 2.0},
                     {"field": "behavior.rolling.pass_life", "op": "<", "ref": "base", "delta": 0}],
   "risks": ["이 delta 는 기저의 rank_buffer 2x 를 교체한다 — 버퍼 효과가 사라져 회전 절감이 상쇄될 수 있다(반증 4·5 가 잡는다)",
             "5영업일 표적 신호를 느리게 들면 선택 알파가 비용 절감보다 먼저 꺼진다 = 2.33% 는 엣지의 필요 경비였다는 결론",
             "회전 상한이 위기 중 위험 축소 거래까지 유보해 낙폭을 키울 수 있다",
             "지평 감쇠(5일 표적의 1·2·3개월 전방 IC)가 패킷에 없다 — 이 처방의 측정이 그 시험을 대신한다",
             "위기 방어를 직접 겨냥하지 않으므로 하락 포착 개선이 작으면 최종 선택 규칙의 지속성 필터(2건 이상)에서 탈락할 수 있다"]},

  {"id": "RX3",
   "name": "추세 지속성 상태를 보유 베타 순위로 소비하는 횡단면 오버레이 — 상태축 조건부",
   "targets": ["W2", "W1"],
   "mechanism": "이 책에는 시장 상태에 반응하는 층이 하나도 없다(패킷 §1 오버레이 none · 방어 슬리브 none · 평균 노출 1.00). 논문 기준으로도 그렇다 — 입력 33(이 칸 31)에 시장 상태 변수가 없고 입력·출력 모두 그날 횡단면 순위로 재척도된다(paper §3.2), 점수는 설계상 '시장이 위험하다'를 표현할 수 없다. 논문은 그 공백을 숏 다리로 메웠고(§3.4 market neutral position), 롱온리 칸에서 그 자리를 메울 수 있는 층은 오버레이뿐이다. 상태는 깊이가 아니라 추세 지속성으로 읽는다: 전기간 MDD 를 세운 창은 29개월(2017-11-03→2020-03-19 · 전략 -51.6% · 하락 포착 1.25)이고, 도구 상자가 깊이 기반 계열의 구조적 한계를 적는다 — '느린 침식은 깊이가 극단으로 안 가므로 수중 기간이 가장 긴 국면에서 가장 덜 개입한다'(그 계열은 스칼라 25회·횡단면 18회로 포화). trend_persist_tilt 는 시장이 자기 12개월 추세 아래 연속으로 머문 개월수를 상태로 쓰고(문턱 = 그 연속 길이의 확장창 경험분위 · 상수 없음) 축소량을 그 달 보유의 시장베타 횡단면 순위에 비례 배분한다 — 스칼라 축소보다 평균 노출을 덜 깎으면서 축소 몫을 운반이 큰 이름에 몰아주는 형태라 R5 노출 짝을 넘을 여지가 있다. 신호는 보유 시작 전 데이터만 쓴다(C5 · 엔진 집행).",
   "implementation": {"overlay": {"kind": "trend_persist_tilt", "arm_id": "trend_persist_tilt"}},
   "expected": {"crisis_dd_capture": "중앙 0.95 기준 하락 — 특히 지속형 창(2007-10 · 2017-11 · 2021-06). 2011(5개월 급락)은 상태가 길지 않아 거의 미발화할 수 있다(R6 부분 실패 위험)",
                "bull_up_capture": "1.90 → 하락(개입 달의 노출 축소 · 하한 0.55 는 여유). 비대칭(상승 중앙 ÷ 하락 중앙)은 반드시 개선되어야 한다 — 그게 존재 이유",
                "calmar": "0.39 기준 상승 기대(낙폭 축소가 CAGR 손실보다 커야 한다) · 평균 노출 1.00 → 1 미만",
                "port_t": "3.94 기준 하락 가능(개입 달 초과수익 평균·분산 동시 축소) · CAGR 20.2% 에서 하락 위험(하한 16% · 여유 4.2%p)",
                "mc8": "노출이 1 미만이 되는 순간 노출 짝이 실질 대조가 된다(기저 돌파 75% 는 평균 노출 1.00 이라 '벤치보다 덜 빠진 위기 3/4'과 같은 말이었다). 횡단면 배분이 그 짝을 넘으면 기전 방어, 못 넘으면 노출 방어로 기록"},
   "preserve": [{"what": "강세 참여 — 조건부 개입이 반등 참여를 삼키지 않았는지", "check": "behavior.summary.bull_up_capture_median"},
                {"what": "상승장 베타 1.00", "check": "behavior.stats.beta_up"},
                {"what": "CAGR 20.2%(하한 16% · 여유 4.2%p) — 방어 비용의 상한", "check": "performance.strategy.cagr"},
                {"what": "기전 방어 여부 — 노출 짝(벤치 x 평균 노출)을 넘은 위기 비율 기저 0.75", "check": "controls.attribution.share_beats_exposure"},
                {"what": "과도 축소 감시 — 평균 노출 1.00 에서 얼마나 내려갔는가", "check": "controls.exposure_profile.mean"}],
   "falsification": [{"field": "behavior.summary.bull_up_capture_median", "op": "<", "value": 0.55},
                     {"field": "performance.strategy.cagr", "op": "<", "value": 0.16},
                     {"field": "performance.strategy.sharpe", "op": "<", "value": 0.8},
                     {"field": "performance.strategy.port_t", "op": "<", "value": 2.0},
                     {"field": "behavior.summary.crisis_dd_capture_median", "op": ">=", "ref": "base", "delta": -0.05},
                     {"field": "behavior.summary.asymmetry", "op": "<=", "ref": "base", "delta": 0},
                     {"field": "controls.attribution.share_beats_exposure", "op": "<", "ref": "base", "delta": 0},
                     {"field": "performance.strategy.calmar", "op": "<=", "ref": "base", "delta": 0},
                     {"field": "behavior.rolling.pass_life", "op": "<", "ref": "base", "delta": -0.05}],
   "risks": ["2011 형 짧은 급락(5개월)에서 '추세 아래 연속 개월' 상태가 길지 않아 개입이 약하다 → R6 지속성 부분 실패",
             "노출이 1 미만이 되어 개선이 노출 방어로 기록될 수 있다(R5 에서 실력으로 세지 않음)",
             "강세 전환 초기에 상태가 늦게 풀리면 반등 참여를 놓쳐 상승 포착과 CAGR 이 함께 내려간다 — 헌장이 금지하는 방향",
             "상태가 시장 추세라 2016(전략 -17.3% / 벤치 +8.2%) 같은 종목축 실패년에는 작동하지 않는다 — 정체 관문(롤링 45%)은 고치지 못한다",
             "2017-11 창의 침식 구간과 2020-03 급락 구간의 낙폭 몫이 패킷에서 분리되지 않아 상태 선택의 사전 근거가 도구 상자 서술에 의존한다(측정 필요)"]}
 ],
 "final_selection_rule": "① 반증을 통과한 처방만 후보로 둔다. ② R6 지속성 필터 — 처방 패킷 3절 위기 표에서 '하락 포착이 같은 데이터 판본으로 다시 잰 기저 대비 0.03 이상 개선된 위기'가 2건 이상인 처방만 남긴다(한 창 맞춤 배제). 남는 처방이 없으면 선정 없음. ③ 남은 후보 중 performance.strategy.calmar 가 가장 높은 처방 1건을 고른다(등급 S 의 위험 축). ④ Calmar 차가 0.02 이내로 동률이면 performance.strategy.cagr 가 높은 쪽, 그다음 performance.strategy.port_t 가 높은 쪽. ⑤ ③④로도 가르지 못하면 선정 없음 — 다음 라운드로 넘긴다. 모든 비교는 보는 창(≤2022-12-29) 수치만 쓰고 τ_D 이후는 쓰지 않는다. 최대 1건 선정.",
 "notes": "자료: paper.txt(pdftotext)가 이 레인에서 읽혔으므로 논문 근거는 원문을 직접 인용했다(분석가 레인은 엔진 머리말에 의존했다). 원문에서 추가로 확인되어 처방 좌표를 바꾼 사실 2건 — ① 논문 롱 전용 판의 Alpha·MaxDD 는 '유니버스 전 종목 평균(등가중) 대비 초과수익' 경로의 수치다(§3.5 · Table 3 DNN5 MaxDD -3.46%) → 논문은 절대 낙폭 방어를 주장한 적이 없고, 크기(EW-CW) 성분은 논문의 알파가 아니라 논문 벤치 안에 들어 있다. ② 논문 유니버스는 TOPIX500(대형·중형)이고 입력 No.19~33 은 월말 갱신이다(§3.1). 패킷 판독 정정 1건 — 새로 실린 위기별 크기 분위 기여 표는 '소형 손실' 서사를 지지하지 않는다(MDD 창 분위 1 = +5.19%(27종) · 손실은 분위 4 -16.34% · 10 -10.45% · 9 -10.22% · 3 -6.90% / 2007 은 분위 8 -16.80% · 7 -16.04%), 그래서 정적 size_band 처방을 넣지 않았다. W1(상시 최대 크기 적재 0.94)은 직접 처방하지 않았다 — 도구 상자에 크기 적재를 시변으로 바꾸는 축이 없고(size_band·cap_core·S01_Size 전부 정적), 정적으로 끄면 2011(+5.6%)·2021(+7.9%) 방어와 CAGR 원천(+3.69%/yr)을 함께 내놓는다. cap_core 는 PORT_t 를 떨어뜨려 필요 Calmar 를 올리는 방향이라(헌장 §2: PORT_t 3.938 → 필요 Calmar 0.528) 보류했고, defense_sleeve(factor_topk · ic_bad_rank_asof)는 매달 k 자리 교체가 RX2 의 회전 축과 상충해 같은 라운드에서 순효과를 가를 수 없어 보류했다 — RX1 이 기각되면 다음 라운드 1순위다. 세 처방은 축이 각각 factors / rebalance / overlay 로 겹치지 않으며 한 처방당 한 축만 바꾼다(R3 시행 3건). 관문은 둘이다: Calmar 0.39 → 0.528 과 롤링 36M 45%(최근 0%) → 0.5 — 정체 관문을 직접 건드리는 것은 RX2 뿐이고, RX1·RX3 가 Calmar 를 고쳐도 롤링 하한은 별개로 남는다. 패킷 밖 측정 필요(남는 것): 위기 직전 달 보유의 하방베타·베타 비대칭 횡단면 분포 · 2017-11 창의 침식 vs 2020-03 급락 낙폭 몫 · rolling_grade.R 의 통과 기준 정의와 실패 창 분포 · 선택 성분 0.84 의 기저 DNN 몫 vs 결합 팩터 몫."}
```
SessionEnd hook [DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}; bash "$DIR/02_Infrastructure/hooks/auto_commit_on_stop.sh" 2>>/tmp/auto_commit_on_stop.log || true] failed: Hook JSON output validation failed — hookSpecificOutput.hookEventName: expected one of "PreToolUse" | "UserPromptSubmit" | "UserPromptExpansion" | "SessionStart" | "Setup" | "PreModelSwitch" | …

The hook's output was: {
  "hookSpecificOutput": {
    "hookEventName": "SessionEnd",
    "additionalContext": "[OK] [auto-commit] 6e7e58884 - 26 files committed → branch=main tree=primary:Quant_Module_Moltbot src=CLAUDE_PROJECT_DIR. Push는 milestone/cron으로 자동."
  }
}

Expected schema:
{
  "continue": "boolean (optional)",
  "suppressOutput": "boolean (optional)",
  "stopReason": "string (optional)",
  "decision": "\"approve\" | \"block\" (optional)",
  "reason": "string (optional)",
  "systemMessage": "string (optional)",
  "terminalSequence": "string (optional)",
  "hookSpecificOutput": {
    "for PreToolUse": {
      "hookEventName": "\"PreToolUse\"",
      "permissionDecision": "\"allow\" | \"deny\" | \"ask\" | \"defer\" (optional)",
      "permissionDecisionReason": "string (optional)",
      "updatedInput": "object (optional) - Modified tool input to use"
    },
    "for PermissionRequest": {
      "hookEventName": "\"PermissionRequest\"",
      "decision": {
        "to allow": {
          "behavior": "\"allow\"",
          "updatedInput": "object (optional) - Modified tool input to use",
          "updatedPermissions": "array (optional) - Permission updates"
        },
        "to deny": {
          "behavior": "\"deny\"",
          "message": "string (optional)",
          "interrupt": "boolean (optional)"
        }
      }
    },
    "for UserPromptSubmit": {
      "hookEventName": "\"UserPromptSubmit\"",
      "additionalContext": "string (optional)"
    },
    "for PostToolUse": {
      "hookEventName": "\"PostToolUse\"",
      "additionalContext": "string (optional)"
    },
    "for PostToolBatch": {
      "hookEventName": "\"PostToolBatch\"",
      "additionalContext": "string (optional)"
    },
    "for Stop / SubagentStop": {
      "hookEventName": "\"Stop\" | \"SubagentStop\"",
      "additionalContext": "string (optional) - Feedback for the model; the conversation continues so the model can act on it"
    }
  }
}
SessionEnd hook [DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}; bash "$DIR/02_Infrastructure/hooks/auto_push_on_stop.sh" 2>>/tmp/auto_push_on_stop.log || true] failed: Hook JSON output validation failed — hookSpecificOutput.hookEventName: expected one of "PreToolUse" | "UserPromptSubmit" | "UserPromptExpansion" | "SessionStart" | "Setup" | "PreModelSwitch" | …

The hook's output was: {
  "hookSpecificOutput": {
    "hookEventName": "SessionEnd",
    "additionalContext": "[OK] [auto-push] main @ 6e7e58884 - 1 commits pushed."
  }
}

Expected schema:
{
  "continue": "boolean (optional)",
  "suppressOutput": "boolean (optional)",
  "stopReason": "string (optional)",
  "decision": "\"approve\" | \"block\" (optional)",
  "reason": "string (optional)",
  "systemMessage": "string (optional)",
  "terminalSequence": "string (optional)",
  "hookSpecificOutput": {
    "for PreToolUse": {
      "hookEventName": "\"PreToolUse\"",
      "permissionDecision": "\"allow\" | \"deny\" | \"ask\" | \"defer\" (optional)",
      "permissionDecisionReason": "string (optional)",
      "updatedInput": "object (optional) - Modified tool input to use"
    },
    "for PermissionRequest": {
      "hookEventName": "\"PermissionRequest\"",
      "decision": {
        "to allow": {
          "behavior": "\"allow\"",
          "updatedInput": "object (optional) - Modified tool input to use",
          "updatedPermissions": "array (optional) - Permission updates"
        },
        "to deny": {
          "behavior": "\"deny\"",
          "message": "string (optional)",
          "interrupt": "boolean (optional)"
        }
      }
    },
    "for UserPromptSubmit": {
      "hookEventName": "\"UserPromptSubmit\"",
      "additionalContext": "string (optional)"
    },
    "for PostToolUse": {
      "hookEventName": "\"PostToolUse\"",
      "additionalContext": "string (optional)"
    },
    "for PostToolBatch": {
      "hookEventName": "\"PostToolBatch\"",
      "additionalContext": "string (optional)"
    },
    "for Stop / SubagentStop": {
      "hookEventName": "\"Stop\" | \"SubagentStop\"",
      "additionalContext": "string (optional) - Feedback for the model; the conversation continues so the model can act on it"
    }
  }
}
