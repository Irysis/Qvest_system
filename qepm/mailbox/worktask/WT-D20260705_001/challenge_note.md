# Self-Adversarial Challenge — WT-D20260705_001 (Alpha Research)

**Agent**: alpha-research (Opus 4.8 native adversarial reasoning, v8.2 — Codex Round 대체)
**Target**: Cross-Sectional Attention 슈퍼팩터 alpha_package (canonical 배포 유니버스)
**Charter §8 No Silent Override 준수**: 각 concern 분류 + 근거 + 합리화 자기검증.

---

## 1. 자기 비평 (devil's advocate) — ≥3 concerns 제기

내 산출물의 가장 약한 지점을 스스로 공격한다.

### C1 [HIGH] Seed 불안정성이 신호를 신뢰 불가로 만든다
canonical per-seed portfolio-alpha t = {0.89, 1.21, 0.65, 1.81, **−0.22**}. seed4는 **음수**. range [−0.22, +1.81]는 신호 강도의 3배 폭. 단일-seed 결과는 사실상 난수. 5-seed ensemble(1.41)로 완화했지만, ensemble도 어떤 5개 seed를 뽑느냐에 따라 다를 수 있다. "재현 가능한 알파"인가?

### C2 [HIGH] Post-2022 감쇠 = 실제 배포 시점에 죽은 알파
canonical 2022+ port_t = **−0.76** (ensemble). allliq도 per-seed 2022+ {+0.86, −1.05, +0.01, +0.22, −0.01} 평균 ≈ 0. rank-IC E3(2020-26)는 여전히 +0.030/+0.064 양수인데 portfolio-alpha는 음/영. **지금 배포하면 최근 국면에서 초과수익 없다.** KR post-2017 cohort decay(6방법 공통 벽).

### C3 [HIGH] 배포 유니버스에서 메커니즘이 작동하지 않는다 (universe mismatch)
가설의 핵심("상대위치/crowding 알파")은 broad universe(allliq port_t 6.06)에서 강하지만, **WT가 지정한 배포 유니버스 K200∪KQ150(canonical port_t 1.41)에서는 약하다.** 대형주 349종목은 peer-dispersion이 부족해 attention이 exploit할 상대구조가 얕다. 즉 "발견한 알파"와 "배포 가능한 알파"가 다른 유니버스에 산다.

### C4 [MEDIUM] Turnover cap 위반 — net alpha가 이미 비용에 잠식
canonical raw turnover 1257% > 헌법 1100% cap. 월 매매 notional이 크다. 15bps net으로 이미 측정했지만, cap 위반 자체가 배포 자격 결격이며, 실제 시장충격(마켓임팩트)은 15bps보다 클 수 있다.

### C5 [MEDIUM] rank-IC 강세를 alpha 강세로 오독할 위험 (attention 과적합)
canonical rank-IC t = 4.41, ICIR 1.16, placebo p=0.000, Bonferroni 통과. 겉보기 강력. **그러나 portfolio-alpha t는 1.41.** attention이 327차원 특성을 96개월 rolling으로 학습 → 횡단면 순위는 잘 맞추나(rank-IC) long-only top-25 실현알파로 전이 안 됨. 고차원 attention의 과적합이 rank-IC를 부풀렸을 가능성.

### C6 [RESOLVED-but-audit] Benchmark 정렬 오염 (ad-hoc 상속 위험)
선행 ad-hoc은 `kns_master_bench.parquet`(1개월 early-shift, clean[t]==master[t+1])로 active-return을 오염시켰다. 내가 이를 상속했다면 모든 2022+/oos 수치가 거짓이다.

---

## 2. 분류 + 처리

| # | Concern | 분류 | 처리 |
|---|---------|------|------|
| C1 | Seed 불안정 | **PARTIAL-ACCEPT** | seed_ensemble이 정당(ADV1: ensemble mean-active = 1.60×seed평균, sd 불변 → 분산축소 artifact 아님 실신호). 그러나 재현성 위험 인정 → challenge_flag HIGH 유지 + judge에 5-seed 전수 공개. |
| C2 | Post-2022 감쇠 | **ACCEPT** | 명백. graduation FAIL 사유로 명시(oos_retention 게이트). KR 구조(6방법 공통) — 은폐 금지. verdict=SCREEN_TIER_FAIL. |
| C3 | Universe mismatch | **ACCEPT** | 배포 유니버스(canonical) port_t 1.41을 authoritative로 보고. allliq 6.06은 "메커니즘 위치"로 라벨(배포 아님). 오도 금지. |
| C4 | Turnover cap | **PARTIAL-ACCEPT** | cap 위반 인정. 단 3M-smoothing 실측(turnover 687%<cap AND port_t 1.93↑) 제시 = 완화 경로 존재하나 여전히 <2.95. constructive note. |
| C5 | rank-IC 오독 | **ACCEPT** | Cycle-2 divergence 명시(rank-IC t 4.41 vs port_t 1.41). judge는 portfolio-alpha t authoritative. challenge_flag 기재. |
| C6 | Bench 오염 | **REBUTTAL (해소 입증)** | 아래 근거. |

---

## 3. REBUTTAL 근거 (C6 — 명시적 근거: 학술 + L-code + 정량 3축)

**주장**: 본 검증의 benchmark 정렬은 clean이며 look-ahead 없음.

- **정량 축 1 (offset 진단)**: clean[t] vs master[t+k] corr → k=+1에서 corr=**1.000**, 나머지 ≤0.09. ad-hoc master_bench는 1개월 early-shift 확정. 본 검증은 `.cache/benchmark.parquet`(clean IKS200)를 signal-month t → realization(t+1) 정렬로 재구성.
- **정량 축 2 (F1 timing)**: panel F1(signal월 t의 forward) vs clean[t+1] corr=0.639 (t+0=−0.14, t−1=0.00) → forward return이 t+1에 실현됨 확인, 벤치를 t+1로 매칭.
- **정량 축 3 (look-ahead toggle)**: canonical ensemble을 WRONG(lag0 concurrent) 벤치로 재측정 → port_t 1.01 vs 정렬(correct) 1.41. 정렬이 **inflate 아닌** 방향(오히려 lag0가 낮음 = 신호가 벤치정렬로 만들어지지 않음). 신호는 정렬 무관하게 약(둘 다 ~1) = look-ahead 부재.
- **학술**: Newey-West 1987 (lag-3 t, contract build_benchmark_compare 내장) — 자기상관 보정 t.
- **L-code**: [[reference-book-benchmark-alignment-realized-ym]] (realized_ym 1개월 앞 라벨 = 외부 시계열 merge 전 offset −3..+3 β/corr 스캔 필수) — 본 검증이 그 protocol을 실행.

**결론**: C6 REBUTTAL 성립 — 벤치 오염은 ad-hoc의 결함이며 본 검증에서 수정·입증됨.

---

## 4. Self-rationalization auto-detection

금지 표현("미미/관행적/실무적/보수적이면 OK/대부분 결과 동일") 사용 여부 자기검사:

- 내 산출물에 "영향 미미" / "보수적이면 통과" 류 **사용 없음**. verdict를 명시적 FAIL로 기재.
- 유일하게 완화적 표현이 될 수 있던 지점 = "seed-ensemble이 개선" → 이를 **정량 검증(ADV1 mean-active 1.60×, sd 불변)** 으로 뒷받침. 합리화 아닌 실측.
- "broad universe에선 강함" → 배포 유니버스 아님을 **명시적으로 별도 라벨** 처리(오도 방지). 강세를 배포 근거로 전용하지 않음.
- AUTO RE-VIEW 트리거 없음.

---

## 5. Q-Lead 자동 escalate 판정

- HIGH severity challenge_flags = C1(seed), C2(2022+ decay), C3(universe mismatch) + POST2022_DECAY + UNIVERSE_MECHANISM_MISMATCH = **5건 ≥ 5** → **escalate 트리거 충족**.
- 단, escalate 사유는 "위반"이 아니라 "SCREEN_TIER_FAIL을 정직하게 확정 + 배포 부적격 명확화"이므로, Q-Lead에 **자본급 부적격 + screen-tier 라우팅 권고**로 escalate(REJECT 방향, 은폐 escalate 아님).
- AX axiom hard FAIL 없음. PIT C1(lockbox/lookahead) 위반 없음(C6 REBUTTAL 입증).

---

## 6. 최종 self-verdict

**alpha_package는 배포 유니버스(K200∪KQ150)에서 SCREEN_TIER_FAIL로 정직하게 확정한다.**
- rank-IC/ICIR/placebo advisory-통과 (신호 실재) — but HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64) 전부 미달.
- seed-ensemble denoising은 실질 개선(0.87→1.41)이나 gate 못넘음.
- **자본급 아님. 후속 = screen-route(DPL feature / factor-rotation RCMA input) 또는 broad-universe+overlay 결합 후속(별도 WT).**
- AX-000 정직보고 준수: 성공 위장 없음, 탐색 중단 아님(방향 = broad-universe overlay 결합이 잔여 EV).

**AX-008 3-source triangulation**: self-adversarial(본 문서) = 1 source. Forge(포트폴리오 재측정) + Architect(구조 감사)와 함께 2/3 PASS 필요 — Q-Lead orchestration.
