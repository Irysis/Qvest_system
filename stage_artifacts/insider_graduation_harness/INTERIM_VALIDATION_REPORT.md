# DART 임원 순매수 하네스 — INTERIM 검증 리포트 (비권위)

**작성**: 2026-07-06 · alpha-research (QEPM) · **verdict_level = INTERIM_NONAUTHORITATIVE**
**목적**: 하네스 *작동 검증* — 판정 아님. 현 커버리지는 부분데이터+갭이라 검정력 부족(underpowered).
정직 고지(AX-000): 아래 PORT_t~2.4 는 **성공도 실패도 아닌 interim 관측**. 졸업 판정은 backfill contig≥60 후.

---

## 1. 현 커버리지 (실행 시점, backfill 진행 중)

- signal 월수: **23** (sig_month 2009-07 ~ 2024-12), 갭 **163월**, **최장 연속 15월** (2015-01~2016-03).
- report 흐름: raw ok 17,905 → officer 7,518 → clean(mechanical 제외) 2,059 → firm-month 이벤트 **948**.
- ★ backfill 이 본 세션 중 실시간 확장(checkpoint 72→75, 2016-01/02/03 추가) → 하네스가 자동 반영
  (contig 13→15). **재발화·멱등 입증**. 하네스는 backfill 무접촉(읽기 전용).
- **커버리지 gate**: 15 < 60월 → `INTERIM_NONAUTHORITATIVE`. 대부분 2010-2014·2016-2024 미수집(백필 대기).

## 2. Canonical screen (PIT_LAG=1, top-25 EW long-only, 15bps, LIQ 2e8, NW lag-3)

| 변형 × 시대 | n | **PORT_t** (p) | IR | rank-IC (t) | oos | calmar | TO/yr | HARD |
|---|---|---|---|---|---|---|---|---|
| krw × contiguous_run | 15 | **+2.41** (.016) | 1.74 | +0.052 (0.99) | 1.23 | 1.19 | 1584% | ✗ |
| krw × combined_all | 23 | **+2.48** (.013) | 1.46 | +0.059 (1.34) | 2.18 | 1.52 | 1634% | ✗ |
| nflow × contiguous_run | 15 | +1.24 (.216) | 0.97 | +0.084 (1.54) | 3.80 | 0.49 | 1610% | ✗ |
| nflow × combined_all | 23 | +1.35 (.177) | 1.05 | +0.083 (1.89) | 6.32 | 0.99 | 1571% | ✗ |

- **metric_type = canonical_screen** (screening-tier, NOT forge-authoritative).
- **HARD 3종 (PORT_t≥2.95 · oos≥0.7 · calmar≥0.64) 전부 미달** → 현 데이터로도 졸업 아님(정직).
  PORT_t 방향 양(+)·krw 변형 p<0.02 이나 gate 2.95 미달 + 검정력 부족(n=15~23, SE 큼).
- rank-IC vs PORT_t: nflow 는 rank-IC 강(0.08)·PORT_t 약(1.2~1.4), krw 는 반대 — **rank-IC≠PORT_t**
  (Cycle 2 교훈). 졸업 binding = PORT_t → krw 변형이 우세.
- oos·calmar 값이 degenerate(oos>1, calmar>1)한 것은 소표본 아티팩트 — 비권위 근거.

## 3. ★ Anti-look-ahead 스트레스 (핵심 PIT 검증) — PASS

`lag_stress_comparison.json` verdict = **`NO_LEAKAGE_graceful_degrade`**.

| 변형 | PORT_t (lag=1) | PORT_t (lag=2, 신호 +1월 지연) | 누출? |
|---|---|---|---|
| krw × contiguous_run | +2.41 | +1.95 | 아니오 |
| krw × combined_all | +2.48 | +1.18 | 아니오 |
| nflow × contiguous_run | +1.24 | +2.09 | 아니오 |
| nflow × combined_all | +1.35 | +1.58 | 아니오 |

**해석**: 신호를 1개월 추가 지연해도 PORT_t 가 붕괴(양→음)하지 않음 → 동월 look-ahead 누출 없음.
(오늘 BearProb faith 버그는 lag 추가 시 신호가 죽었어야 하는 유형 — 여기선 graceful degrade.)
insider 정보의 2~3개월 완만 확산(Cohen-Malloy-Pomorski)과 정합. `pit_audit.py` 5/5 PASS 병행.

## 4. ★ 구조적 caveat (deployment 관점, 정직)

- **turnover ~1,580%/yr** = 스파스 이벤트 신호의 월별 full-rebalance 결과. **screening turnover
  hard-fail 1,100% 초과**. 실배포엔 holding-band/decay overlay 필수(현 EW 매월 재선정은 milestone
  자격 미달 요인). 이는 신호력 문제가 아니라 *구현 규율*(research_philosophy ⑥) 문제 — 후속 overlay 탐색 대상.
- **officer 커버리지 2009+ 한정**(pre-2009 sparse) + 갭 163월 → combined_all 도 시대 편중.
- **mechanical 정제 = report-level n_mechanical==0 근사**(disc_change_qty NULL). 장외 소량 잔류 가능
  (신호 *약화* 방향, 낙관 편향 아님).
- book-marginal ΔIR: krw 변형 +0.03~+0.32(참고용), nflow 음수. 소표본·screening-tier 라 비권위.

## 5. 결론

**하네스 READY.** 현 커버리지 = 최장 연속 15월(interim/비권위, underpowered).
PIT 무결(스트레스+감사 통과)·재발화 가능(멱등)·계약경유 실측(canonical_screen_bt).
**backfill 완주(≥60월 contiguous) 시 `run_harness.py` 재실행 → 졸업 판정 발화.**
현 interim 신호는 방향 양(+)이나 HARD 3종·turnover gate 미달 — milestone 확정 아님(정직 보고, AX-000).
