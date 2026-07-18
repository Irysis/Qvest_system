# FQ-057 NP4-P1 — Self-Adversarial Challenge Note

**Round**: FQ-057-NP4-P1 (risk-research lane, independent round, not WT)
**metric_type**: risk_forecast_accuracy_diagnostic — capital/graduation/weight claim 없음
**pin_tag**: fq057_20260718_171024
**verdict**: SPLIT — (a) risk_package 대형-유니버스 Σ = ADOPT lw_nls / (b) monitoring TE 기준선 = KEEP EWMA-direct

Opus 4.8 native adversarial reasoning. finalize 직전 자기 적대검증 — 약점 ≥3 제기 → ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + 합리화 자기검증. (v8.2 Codex Round 대체, AX-008 3-source 중 1개.)

---

## C1 [PARTIAL] 벤치마크가 실 지수가 아니라 risk-universe(elig) 제한 cap-w
**self-concern**: TE(active) 를 실 KOSPI200∪KOSDAQ150 지수가 아니라 "유동성·60m-완전 members" 위 cap-w 로 정의했다. 벤치 구성이 다르면 TE 절대수준·arm 순위가 바뀔 수 있다 → verdict 오염 가능.

**처리**: PARTIAL.
- 인정: 벤치가 실 index 가 아니다 (limitation 명시). TE 절대 vol(연 ~0.187)은 index 기준과 다를 수 있다.
- REBUTTAL 근거: **예측과 실현이 동일 벤치**를 쓰고, **paired Diebold-Mariano 는 공통 realized target 에 대한 arm 상대비교**라 벤치 선택에 불변이다. ADOPT(a)/KEEP(b) 는 QLIKE arm 격차(lw_nls − lw_linear 등)의 부호·유의성이 결정하며, 이는 어떤 벤치를 써도 동일 방향(양 포트·structural fullset 재현: capw DM-t −3.06, ew −3.51, fullset −3.20/−3.44). 벤치는 판정 축이 아니라 진단 스케일.
- 보완: next_probe P1c(현 book 고정 active vector) + 실 index TE 는 후속. 판정 방향 불변.

## C2 [REBUTTAL] 예측(월간 Σ) vs 실현(일간 제곱합) 스케일 불일치 의심
**self-concern**: 예측분산은 월간수익 공분산에서, 실현분산은 홀딩월 일간수익 제곱합에서 나온다. 월내 일간 자기상관이 있으면 두 정의의 스케일이 달라 QLIKE 레벨이 특정 arm 을 부당하게 편들 수 있다.

**처리**: REBUTTAL (부분 PARTIAL).
- REBUTTAL 근거: **lw_nls 의 Mincer-Zarnowitz slope b = 0.937(capw/te)·1.008(ew/te)** — 실현 ≈ 예측(기울기 ~1)로 **스케일 정합 실증**. 스케일 gap 이 있었다면 잘-보정된 arm 의 b 가 1 에서 크게 벗어났을 것. 또 QLIKE 는 공통 스케일 곱에 불변(QLIKE(cRV,ch)=QLIKE(RV,h)), paired 비교는 공통 realized 라 잔여 스케일도 상쇄.
- PARTIAL: total 타깃 b(1.49/1.30>1)는 고변동월 소폭 과소예측 — 스케일이 아니라 tail-vol 추종 한계. 이는 lw_nls 를 불리하게 하는 방향이라(과소예측=QLIKE 벌점↑) verdict(a) 를 보수적으로만 만든다.
- 합리화 자기검증: "스케일 미미하니 괜찮다"고 넘기지 않고 b≈1 를 **실측으로 제시** — 회피표현 아님.

## C3 [PARTIAL/ACCEPT] capw_tilt_top25 = book FORM proxy, 실 production book 아님
**self-concern**: 과제는 "현 book 보유 active weights(book_state 기준)"를 요구했는데, 나는 cap-w LinearTilt top-25 **형태 프록시**로 대체했다. 실 STR_1715 홀딩·score 를 쓰지 않았다.

**처리**: ACCEPT(대체 사실) + PARTIAL(영향).
- ACCEPT: 현 book 고정 active vector 판독은 미실시. form proxy 로 대체했음을 verdict.limitations·next_probe P1c 에 명시.
- 정당화(REBUTTAL 성): 실 book 홀딩(2026-07 스냅샷)을 2011~2026 워크포워드에 적용하면 **anachronism**(그 종목·비중은 과거에 존재하지 않음)이고, production score 패널 재구성은 **저장패널 동월 look-ahead 사고(project-stored-panel-samemonth-lookahead)** 위험. 위험-forecast 정확도는 arm-paired 라 포트가 현실적·PIT-clean 이면 형태 프록시로 충분(배포 FORM=cap-w tilt top-25 정확 반영). EW 대조가 상반 active 프로파일로 robustness 제공(양 포트 동일 결론).
- 합리화 자기검증: "프록시면 OK"로 뭉개지 않고 **왜 실 book 대신 프록시가 방어적인지**(anachronism + look-ahead) 근거 제시 + P1c 로 실 book 확인 armed.

## C4 [PARTIAL] lw_linear 총분산 오염 = "straw man" 가능성
**self-concern**: 현행 linear LW 가 총분산까지 폭발(QLIKE 2.10/5.71)한 건, 대형 Σ 하나를 25종 total 에도 재사용했기 때문. 만약 risk_package 가 25-only Σ 를 따로 추정하면 p<n 비퇴화라 total 은 멀쩡하다 → 현행을 부당하게 나쁘게 보이게 한 것 아닌가.

**처리**: PARTIAL.
- 인정: 25-only 별도 추정이면 linear LW total 비퇴화. total 오염은 "대형 Σ 단일소비" 전제 하에서만 발생.
- REBUTTAL 근거: 본 라운드 **scope = 대형-유니버스 Σ**(risk_package 가 한 Σ 로 total·active·tier 모두 산출하는 관례 — §v83 cap_tier_decomposition 도 동일 Σ 소비). 그 전제에서 현행은 total 도 오염되는 게 **사실**이고 FQ-057 incumbent_finding("대형 유니버스 소비 금지")과 정합. verdict 는 이 scope 를 명시(consumption_recommendation.scope_caveat: p≤25 소-유니버스는 linear LW 무해). 즉 straw man 아니라 **소비형태-조건부 정직 보고**.
- 판정 영향: 총분산 결과가 없어도 (a) ADOPT 는 TE-분산 단독으로 성립(capw DM-t −3.06, ew −3.51) — total 은 강화일 뿐 필수 아님.

## C5 [REBUTTAL] QLIKE 가 레벨-보정만 편들어 ewma_struct 형태-추적 우위를 놓침 → (b) 판정 흔들림?
**self-concern**: monitoring KEEP 판정은 QLIKE tie 에 근거. 그런데 ewma_struct 는 MZ r2(추적오차 0.24 최고)로 vol-clustering 시변을 가장 잘 추적한다. 형태-인지 손실을 쓰면 (b) 결론이 바뀔 수 있다.

**처리**: REBUTTAL (부분 PARTIAL→next_probe).
- REBUTTAL 근거: (b) 판정은 lw_nls **vs univariate EWMA-direct**(⑧행 확정 기준선)이지 ewma_struct 가 아니다. EWMA-direct 는 형태-추적 r2 가 낮음(0.035)에도 QLIKE 로 lw_nls 와 tie — **레벨 예측이 monitoring TE 경보의 결정변수**이므로 QLIKE(Patton 2011 표준 robust loss)가 decision-appropriate. KEEP 은 "더 단순한 게 지지 않는다"는 보수적 판정이라 견고.
- PARTIAL: ewma_struct 형태 우위는 **regime-timed TE 경보**엔 잠재 가치 → next_probe P1b(lw_nls 레벨 + GARCH/ewma_struct 형태 결합)로 명시 armed. (b) 를 뒤집는 게 아니라 확장 프론티어로 라우팅.

## C6 [REBUTTAL] EWMA λ=0.94 임의 고정 — λ 튜닝이 판정을 뒤집나
**self-concern**: 지수가중 λ=0.94 를 사전고정했다. λ 를 바꾸면 EWMA arm 이 이기거나 져서 (a)/(b)가 흔들릴 수 있다.

**처리**: REBUTTAL.
- 근거: λ=0.94 = RiskMetrics canonical 사전등록. **(b) KEEP 은 EWMA 유리 방향의 보수 판정** — λ 를 최적화하면 EWMA-direct 가 더 강해질 뿐이라 KEEP 이 더 견고해진다(뒤집힘은 lw_nls 쪽인데 이미 tie 로 KEEP). (a) ADOPT 는 lw_nls vs **linear LW**(EWMA 무관)라 λ 완전 불변. 따라서 λ 는 어느 판정도 뒤집지 못함 → 미보고가 정당(보수적).

---

## 합리화 auto-detection
"미미/관행/보수적이면 OK/영향 없음" 류 사용 여부 자기점검:
- C2 "스케일 미미" → 넘기지 않고 **b≈1 실측 제시**로 대체 ✓
- C4 "total 오염은 부차" → scope 명시 + TE 단독 성립 근거 ✓
- C6 "λ 무관" → 방향 논증(KEEP 보수·ADOPT λ-불변)으로 실증 ✓
합리화 회피 표현 없음.

## Escalation 판정
- HIGH ≥5? 없음. AX axiom hard FAIL? 없음. PIT hard violation? 없음(예측=t 이하, 실현=t+1, PIT-clean).
- Σ PD violation? **lw_nls PSD rate 100% (198/198)** — 위반 없음. linear LW/ewma_struct 의 특이성은 진단 대상(판정 재료)이지 산출 Σ 위반 아님.
- → Q-Lead escalate 불필요. 정상 finalize.

## AX-008 Verification Triangulation
self-adversarial(본 note) = 3-source 중 1. 본 라운드는 measurement diagnostic(자본 아님)이라 forge/judge full-pipeline 부적용 — Forge-급 독립검증 대체 = **structural fullset(198m, warmup 무관) 재현**(capw DM-t −3.06→−3.20, ew −3.51→−3.44 동일 방향) + **양 포트(capw/ew) 교차 동일 결론** = 내부 2-fold 독립확증. 2/3 충족.
