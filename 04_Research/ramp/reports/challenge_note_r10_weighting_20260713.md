# R10 Self-Adversarial Challenge Note (v8.2 — 메인 자체 적대검증)

- **대상**: RAMP R10 (FQ-023) — P-pure(W36_K20) 동일가중 → 점수/성과-비례 가중 교체 실측
- **판정**: KILL_axis=TRUE (전 config paired NW-t < 2.0 문턱; max +1.782 = W-stock-sqrt) → P-pure 비중 축 소진, 동일가중 유지 확정
- **L-code**: L-RAMP-20260713_084821 · **config_hash**: 1648fada1bd7f4f8 · **base parity**: Δ=1.4e-5 (R6 2.6124 bit-consistent)
- **작성**: 2026-07-13. 외부 Codex 호출 없음(v8.2 — Opus 자체 적대검증). 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL.

## 측정 요약 (cap-w authoritative)
| config | cap-w PORT_t | oos | calmar | paired vs base | TO | eff-N | OTHER비중 |
|---|---|---|---|---|---|---|---|
| base (EW×EW) | 2.612 | −0.076 | 0.450 | — | 9.27 | 25.0 | 0.906 |
| W-stock (종목 z-선형) | 2.930 | +0.015 | 0.499 | +1.60 | 9.57 | 19.8 | 0.912 |
| W-factor (팩터 t-비례) | 2.520 | −0.145 | 0.506 | −0.17 | 9.32 | 25.0 | 0.876 |
| W-both | 2.890 | −0.037 | 0.546 | +1.13 | 9.71 | 19.9 | 0.878 |
| W-stock-sqrt (완만화) | 2.808 | −0.025 | 0.476 | +1.78 | 9.42 | 23.7 | 0.909 |

## 약점 자가제기

### W1 — "축 소진" framing이 사상 최근접(2.93) near-miss를 매몰하는가? → **PARTIAL ACCEPT**
사전등록 KILL 규칙(paired<2.0)은 정확히 발동했다(최고 1.78). 그러나 3/4 config가 일관되게 양(+1.1~+1.8)이고 headline cap-w를 2.61→2.93으로(P-pure 사상 2.95 hard gate 최근접) 끌어올렸으며 oos가 −0.076→+0.015로 부호전환했다. "완전 소진"으로만 보고하면 방향성 양의 신호를 매몰한다. **교정**: 자본 판정(KILL)은 불변으로 유지하되, "종목 점수-비례는 방향성 양의 가장 순한 레버 — 유의(2.0) 미달로 자본 판정 불변, 그러나 substrate 개선 시 유의 도달 가능"으로 이중 서술. L-code lesson (1)항에 반영.

### W2 — W-stock 개선이 소형주 농축/집중 잡음의 부산물인가? (challenge2) → **REBUTTAL**
증거가 반증한다: (a) cap-tier 구성 거의 불변 — OTHER(소형) 비중 base 0.906 → W-stock 0.912 (+0.6pp). 개선은 소형 이동이 아니라 **동일 tier 내 고점수명 재가중**. (b) 완만한 sqrt 틸트(eff-N 23.7)가 강한 linear(eff-N 19.8)보다 paired 높음(1.78>1.60) — 집중 잡음이 견인이라면 강한 틸트가 더 커야 하나 반대. 개선은 집중도가 아니라 **신호(composite 횡단 순위력)**가 견인. eff-N/HHI/cap-tier 표로 disproof 제시.

### W3 — 강한/결합 틸트가 실패한 standalone(단일팩터 top-25)로 수렴하는가? (challenge3) → **ACCEPT(정신) / degradation 부재(사실)**
결합 틸트(W-both, 팩터+종목)는 종목 단독(W-stock 1.60)·완만화(1.78)보다 paired 낮음(1.13) — **팩터-가중(W-factor, 단독 −0.17)이 종목-틸트 이득을 희석**. 즉 "틸트를 더 쌓을수록 좋다"는 거짓. 단 config가 degenerate 집중(1~2종)으로 붕괴하는 standalone-FAIL 수렴은 아니다(최소 eff-N 19.8, cap 0.20 거의 미바인딩). 결론: 최순한 stock 틸트(sqrt)가 가장 견고 — 강도-단조 개선 부재는 확인, FAIL 수렴은 부정.

### W4 — 회전비용 반영 후에도 개선이 생존하는가? (challenge1) → **REBUTTAL(생존)**
가중변형은 매월 |Δw| 재조정으로 회전 증가(base 9.27→W-both 9.71) 경향이나 1,100% 한도 대비 미미. 모든 수치는 weighted_screen_bt delta-based 15bps **내장 차감 후 net** — 즉 보고된 W-stock 2.93은 이미 추가 회전비용 차감 후 값. 개선(방향성)은 비용 생존. 단 유의(2.0) 미달은 비용과 무관한 신호력 한계.

### W5 — positive-shift floor_frac=0.25는 자유 파라미터 — 다른 값이면 판정 뒤집히나? → **REBUTTAL(robust)**
floor_frac은 사전등록·sha256 동결. sqrt config가 틸트 강도 축을 이미 span(더 순함) — linear/sqrt 모두 paired 1.6~1.8 band에 안착(2.0 미달). 다른 floor는 이 band 내부를 움직일 뿐. 최강 합리적 틸트(linear, eff-N 19.8)도 1.60에 그쳐 판정(KILL)은 floor 선택에 robust.

### W6 — 팩터 성과-비례(W-factor)의 음(−)이 신뢰 가능한가? PIT 안전한가? → **ACCEPT(교차확증)**
W-factor는 sel_traj의 trailing NW-t(선별 시점 값, PIT-safe — 결정일 이전 trailing 창 실현수익만)로 팩터를 가중. 결과 악화(cap-w 2.52<2.61, paired −0.17)는 정직 — trailing 팩터성과가 forward 팩터성과를 못 예측, EW 팩터결합이 우월. 이는 **factor-of-factors momentum timing NULL(06-30)의 독립 재확인**으로, 신규 발견이 아니라 기존 settled-negative 교차확증. 유용한 sanity.

## 자기합리화 탐지
- "2.93이니 거의 성공" → **차단**: paired 1.60/1.78 < 2.0는 유의 미달이 실체. headline 근접을 유의로 승격 금지(§8.3 판정평문). 자본 판정 KILL 불변 유지.
- "EW보다 나으니 채택 권고" → **차단**: 자본 게이트 HARD 3종 0/4, governor 정지. book 무변경. 어떤 배분 변경도 권고 아님.
- paired cap-w == EW-uni 동일값은 오류 아님 — 두 포트 active 차분서 벤치가 상쇄(paired는 벤치 무관), 정합 확인.

## 종합
자본 판정 **KILL(EW 유지 확정) 불변**. 방향성 양(+)의 순한 레버 존재를 정직 병기(자본 승격 아님). 소형농축·강틸트degradation·비용 3 challenge 모두 통과(REBUTTAL 3·PARTIAL 1·ACCEPT 2). 잔존 frontier: 점수-비례 틸트 × 비-수익 패널(FQ-001).
