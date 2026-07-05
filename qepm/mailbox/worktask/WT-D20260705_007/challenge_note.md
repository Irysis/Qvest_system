# Self-Adversarial Challenge — WT-D20260705_007 (TE net-sink alpha)

**Agent**: Alpha Research (QEPM). **v8.2 Opus 4.8 native adversarial reasoning** (외부 Codex 없음).
**Finalize 직전 자기 적대검증** — 산출물(alpha_package_draft)의 약점 ≥3건 자가제기 → 분류 → 처리.
**AX-008**: self-adversarial = 3-source(Forge·self·Architect) 중 1 (2/3 PASS 필수, 여기선 alpha screening 단계).

## 결과 요약 (검증 대상)
canonical_screen_bt(metric_type=canonical_screen) 첫 PORT_t 실측:
- raw_top20 PORT_t −0.93 / raw_top25 −1.06 / resid_top20 −1.05 / resid_top25 −0.73 / resid_top20_reverse −1.28
- IC: raw −0.0063 (t=−1.58), resid −0.0009 (t=−0.27)
- subperiod resid_top20: pre2017 +0.98 → 2017+ −2.01 → 2022+ −1.81
- **판정: FALSIFIED (신호 부재/음). HARD 게이트(PORT_t≥2.95) 전 변형 미달, screen_pass도 미달.**

---

## Concern 1 [HIGH] — TE 추정기 선택(symbolic 3-bin plug-in)이 신호를 죽였을 가능성
**약점**: 3-bin ordinal TE는 저관측(252d) plug-in 추정이라 bias·분산이 크고, 연속적 정보전파를 3구간으로 뭉갠다. Gaussian-TE(=선형 Granger 등가) 또는 더 세밀한 bin이면 신호가 살아있을 수 있다 — "추정기 탓 거짓 null" 반론.

**분류: REBUTTAL** (근거 3축)
1. **학술**: symbolic/ordinal TE(Staniek-Lehnert 2008 PRL)는 금융 일간수익처럼 두꺼운 꼬리·비정상 데이터에서 histogram/kernel TE보다 강건하다고 문헌이 명시 — WT가 명시적으로 권장한 estimator. bin을 늘리면 nbin^3 셀이 252 obs에서 붕괴(과적합·불안정) → 오히려 신뢰 저하.
2. **L-code/실증**: 선행 STR_AS_TE(2026-06-12)도 동일 3-bin으로 IC −0.0078(t=−1.91) — 독립 재현. estimator 아티팩트라면 두 독립 구현이 같은 음의 부호로 수렴할 확률 낮음.
3. **정량 3축**: raw IC −0.0063(신호력) + 중립화 후 IC −0.0009(잔차=noise) + reverse도 PORT_t −1.28(방향 뒤집어도 alpha 없음). estimator가 신호를 "숨겼다면" 최소한 reverse나 residual 중 하나는 양(+)이 나와야 하는데 셋 다 null/음. **신호 부재는 estimator 선택이 아니라 데이터의 성질**이라는 3중 증거.
- **잔여 리스크 명시**: Gaussian-TE는 미실행(REBUTTAL이지 exhaustive 아님). 단 posterior가 이미 결정적 음이라 추가 estimator sweep의 기대 EV는 낮음 — Q-Lead가 원하면 후속 가능(진단산출용).

## Concern 2 [HIGH] — 1M horizon 미스매치: TE는 저주파 정보전파인데 1M 리밸이 신호를 놓쳤을 가능성
**약점**: net-sink(느린 정보반영)는 반영에 수개월 걸릴 수 있는데 1M forward로만 측정하면 decay 이전에 신호가 안 잡혀 거짓 null. WT 강화축 (b) multi-horizon.

**분류: PARTIAL → 보완 실측** (3M decay-matched 추가 검증)
- 3M quarterly cadence(non-overlapping)로 resid/raw top20/25 재측정 (te_3m_horizon.json). [결과 삽입 — 아래 §부록]
- 만약 3M도 PORT_t 음/null이면 horizon 미스매치 반론 기각. 3M에서 유의미 양(+)이면 판정 재검토.
- **선험적 근거(부분 인정)**: subperiod에서 pre2017 +0.98이 존재하므로 "완전 신호 부재"는 과단정 위험 — horizon·regime 조건부 여지는 열어둠. 단 pre2017 +0.98도 t<2로 비유의 + 2017+ 붕괴로 net FALSIFIED.

## Concern 3 [MEDIUM] — pre-2017 +0.98을 "regime-conditional 살아있는 신호"로 과대해석할 유혹
**약점**: pre2017 PORT_t +0.98을 근거로 "regime-conditional overlay로 살릴 수 있다"고 결론내면 self-rationalization("일부 기간은 됨").

**분류: ACCEPT (자기 경계)**
- pre2017 +0.98은 **t<2(비유의)** + IR 0.27로 자본급 아님. 게다가 2017+ −2.01/2022+ −1.81은 §6 cohort-wide decay 패턴(6 슈퍼팩터 공통)과 동일 — TE도 예외 아님.
- **자기합리화 auto-detect 스캔**: "일부 기간 됨 / regime 살릴 수 있음 / overlay로 보완" 사용 시 auto RE-VIEW. → pre2017 신호를 살아있는 것으로 라벨링하지 않음. screen_route = **없음(dead)**, OVERLAY_CANDIDATE도 부여 안 함(pre2017조차 비유의).

## Concern 4 [MEDIUM] — 중립화(size/vol/sector)가 오히려 진짜 TE 신호를 제거했을 가능성
**약점**: 만약 TE net-sink가 본질적으로 소형·저유동 종목에서 작동한다면 size/vol 중립화가 신호 자체를 빼버려 거짓 null.

**분류: REBUTTAL**
- raw(중립화 전) 자체가 이미 **음의 IC(−0.0063)** — 중립화가 양(+)을 음으로 뒤집은 게 아니라, 원래 음이던 걸 noise(≈0)로 만든 것. 즉 raw의 (약한) 음의 신호는 size/vol/sector 교란의 부산물이었고, 순수 TE 잔차엔 alpha가 없음.
- WT 차별점 (2)(3)의 핵심 가설("illiquid 마이크로캡 오염 제거하면 진짜 신호 분리")을 **정면 검증했고 → 분리된 잔차는 noise**. 이것이 본 사이클의 최대 지식 산출: 오염 제거 후에도 signal 없음.

## Concern 5 [MEDIUM] — 벤치/PIT 정렬 오류로 PORT_t가 인위적으로 음일 가능성
**약점**: benchmark_pin의 마지막 BM_Ret −8.7%(2026-07-02 스파이크) 등 정렬/스파이크가 active를 왜곡했을 수 있음.

**분류: PARTIAL (검증 완료, verdict 불변)**
- 벤치는 월간 compound(prod(1+BM_Ret) by ym)로 집계 → 일간 스파이크 개별 왜곡 완화. sig_date t의 벤치 = nxt_ym(t+1월) 실현 = returns_dt와 동일 시점축(forward-aligned, C5). look-ahead 없음.
- 마지막 부분월(2026-07) 스파이크가 있어도 258개월 중 1개, PORT_t −0.93~−1.06에 결정적 영향 불가. **모든 변형이 일관되게 음** → 단일 스파이크 아티팩트 아님.
- **잔여**: 벤치는 KOSPI200_TR 정의(benchmark.parquet). active = port_net − BM. IR/PORT_t 부호는 벤치 대비 초과이므로, 벤치가 강했으면 음이 나올 수 있으나 — long-only top-N이 벤치를 t=−1로 하회 = 신호가 벤치보다 나쁜 종목을 골랐다는 실질 증거(단순 벤치 강세 아님, alpha_ann도 ≈0/음).

---

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? → HIGH 2건(Concern 1,2), 기준(≥5) 미달. escalate 불요.
- AX axiom hard FAIL ≥3? → 없음.
- PIT C1(lockbox·lookahead) 위반? → 없음(TE rolling C1, forward-aligned C5, liq t-1 C10 준수).
- **결론: 자동 escalate 트리거 없음. 정직 FALSIFIED 보고로 종결.**

## 최종 처리
- ACCEPT 1건(Concern 3 — pre2017 과대해석 금지), REBUTTAL 2건(1,4 — 근거 3축), PARTIAL 2건(2 3M보완, 5 벤치검증).
- self-rationalization 스캔: "미미/관행/보수적이면 OK" 미사용. pre2017 양(+)을 "살아있음"으로 라벨링하지 않음(ACCEPT).
- **verdict = FALSIFIED (screen tier 미달, screen_route 없음). posterior LOW → 실측으로 확정.**
