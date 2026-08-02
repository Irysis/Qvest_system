# WT-D20260802_017 — Self-Adversarial Challenge Note (v8.2)

finalize 직전 자가 적대검증. Concern 5건 — ACCEPT 2 / PARTIAL 2 / REBUTTAL 1.

## C1. 커버리지 절단 — 7월 폭락월 미포함이 판정을 뒤집을 수 있다 [PARTIAL]

**공격**: carrier가 2026-05 홀딩월에서 끝난다. 2026-06월말 라벨=CRISIS(실측)이고 7월 벤치 −23.6% — 후보는 7월을 g=0.40으로 방어해 그 한 달에 큰 +active를 얻었을 것. 하락 직전 월을 빼고 negative 판정하는 건 라벨에 불리한 절단 아닌가.

**처리 (PARTIAL)**: 인정 — 7월 포함 시 point estimate는 개선 방향. 단 (i) 라벨은 2026-02부터 6개월 연속 CRISIS로 켜져 있었고 그중 4~5개월이 +12.7~+33.4% 멜트업 — 표본 내 CRISIS 라벨월 누적 active 악화 −64.1%/yr(연율)로, 한 달의 방어 이득이 상쇄하기엔 in-window 손실이 큼(stopped-clock 구조: 항상 켜져 있으면 언젠가 맞음). (ii) 창 안 판별력 검정(fisher p=1.0, BM<−8%에서도 p=0.196)은 단월 편입과 무관한 라벨 성질 판정. **보완**: revival_conditions에 carrier 2026-07+ 재생성 시 순액 재판정을 등재 — 판정은 config·window-scoped로 라벨.

## C2. g 스케줄 단일값(0.40/0.70)이 임의적 — 더 온건한 축소면 중립·양(+)일 수 있다 [REBUTTAL]

**공격**: g=0.85 같은 온건 스케줄이면 상승월 비용이 줄어 paired t가 0 근처나 +로 갈 수 있다. 단일값 사전 고정이 결론을 과장한 것 아닌가.

**반박 근거 3축**: ① **수리**: 한계 시리즈 d_t = (g(c_t)−1)·e_book,t·r_t^book-ish 형태로, g→1 수렴은 d_t를 균일 축척할 뿐 부호·t의 방향을 바꾸지 못한다(두 라벨 g 비율이 바뀌면 미세 변동은 있으나, CRISIS·CAUTION 각각의 조건부 한계 t가 둘 다 음수 — −1.90/−1.20 — 라 어떤 볼록결합도 양수가 될 수 없음). ② **정량**: 판별력 자체가 0(recall 0.10 < base 0.41, fisher p=1.0) — 방향 없는 신호는 축소폭과 무관하게 기대 기여 ≤ 0 (비용 양수). ③ **규율**: 폭 열거→argmax는 사전등록이 금지한 sweep(measurement-graduation §3) — L-code 선례: WT-015 동일 규율. 학술: Harvey-Liu-Zhu 2016 다중검정 관점에서 사후 폭 탐색은 t 인플레 경로.

**합리화 자기검증**: "어차피 결과 동일" 류 어휘 미사용 — 반박은 조건부 t 부호(실측)와 판별력 검정(실측)에 근거. PASS.

## C3. e_book을 2-1 layer5 CSV의 lag 컬럼에서 재구성 — 현행 2-3 book의 실현 β와 파리티 미검 [ACCEPT]

**공격**: 2-3 noLayer4 공식(m4×β_R05_V5)은 맞지만, 최근 월의 R05 z 소스 동결 이슈(memory: z=NA→β 0.30이 0.50으로 무뎌짐)처럼 기록값과 실제 배포값이 어긋난 구간이 있을 수 있다.

**처리 (ACCEPT — 스펙 명시로 수정)**: alpha_validation.carrier.parity에 근거(§7b 선례·검증앵커 일치)를 기록하되, e_book 충실도는 "production 기록 lag 컬럼 기준"으로 한정 명시. 핵심 방어: e_book 오차는 BOOK·CAND에 **곱셈으로 동일 적용**되어 한계기여 paired t에는 1차적으로 상쇄 — 판정 통계는 강건. 절대 수치(BOOK PORT_t 6.18 등)는 이 한정 하에 해석.

## C4. BM<0 이진화가 '위기'의 조잡한 proxy — 라벨은 tail 위기용인데 월간 마이너스로 채점했다 [ACCEPT → 보강 실측으로 해소]

**공격**: 라벨 엔진은 심각한 위기 탐지용이므로 mild한 월간 마이너스 포착 실패는 정당한 채점이 아니다.

**처리 (ACCEPT — 보강 실측 완료)**: probe_deepdown.R로 문턱 3단 채점 — BM<−5% recall 0.17(p=0.161), BM<−8% recall 0.20(p=0.196). 깊이를 어떻게 잡아도 유의한 판별력 없음. 결정타는 CRISIS 라벨월 연대기: 발화가 2009-01~05·2020-05/06·2026 — 전부 위기 '후' 반등 또는 멜트업 구간. 채점 방식의 문제가 아니라 라벨의 지연 지표 성질.

## C5. paired t −1.85는 사전규칙상 '유해'(−2.0) 미달 — negative 단정이 과잉 아닌가 [PARTIAL]

**공격**: 사전등록 문자대로면 '중복·노이즈' 구간이다. "점추정 유해"까지 쓰는 건 규칙 밖 해석.

**처리 (PARTIAL)**: 인정 — 공식 판정은 사전규칙 문자대로 "독립 한계기여 없음(중복·노이즈 구간)"으로 기재(alpha_validation.verdict). 단 방향 증거의 일관성(EW기저 −2.04는 문턱 초과, lag2 −2.57, 비용반영 −1.87, ΔIR −0.22, CRISIS 조건부 −1.90)은 진단으로 병기 — 이는 규칙 재해석이 아니라 사전등록된 대조군·스트레스의 보고 의무 이행. 채택 방향으로의 규칙 이동이 아니므로(더 부정적으로 읽는 쪽) selection 오염 없음.

## 종합

- 사전등록 규칙 이동 없음, sweep 없음(n_trials=1), OOS 반복조회 없음.
- PIT: assert HARD PASS + 위반 주입 발화 실증 + lag 스트레스 + strict A/B(동일) — BearProb 사고 lane 방어 완료.
- 측정 결함 2건(가중 그룹핑 붕괴·sprintf passthrough)은 실행 중 지문으로 적발·수리·가드 배선 — alpha_validation.repairs 기록.
- Q-Lead escalate 조건(HIGH ≥5 / AX hard FAIL ≥3 / C1 lockbox) 해당 없음.
