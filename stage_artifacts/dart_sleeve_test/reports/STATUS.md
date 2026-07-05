# DART Insider Sleeve — Book-Marginal Test Status

작성: 2026-07-05 20:20 KST. 격리 산출(기존 파일 무수정).

## 1. 백필 커버리지 (현재)

- **연대순 run (bw9c1hhv0)**: 2005-01 .. **2009-02** 완료(50월) + isolated 2024-12(parity).
  - 오늘 4000-call budget cap 소진 후 **HALTED** (200903 에서 정지, checkpoint 미기록 → 다음 run redo).
  - 2009 초 월당 report 폭증(200902=1817건 ≈ 1817 doc call) → 월당 call 비용 높음.
- **panel**: insider_netbuy_monthly.parquet = 2329 ticker-months, 235 tickers, 2005-01..2024-12.
- **officer 분류**: 2005-2009 **전무**(nonzero 0/2329). 2024-12 만 85. README 경고대로 pre-2010 sparse.
  → **officer 신호(가장 sharp) 는 2010+ 에서만 유효** = 감쇠구간(2015-2024) 수집이 결정적.

## 2. API budget (DART 10k/day, 공유)

- 오늘 누적 소비 ~9000+ call (crash refetch + 연대순 run 4000). **잔여 헤드룸 ~1000** = 감쇠구간 수집 불가.
- **결정(정직)**: 오늘 동시 priority run 발사 금지. 2nd concurrent consumer = 020 rate-limit → 양쪽 halt.
- **우선 백필 = daily reset(00:05 KST, 07-06) 후 scheduled task 발사.** 신규 10k budget.

## 3. 우선 백필 준비 완료

- `code/gated_priority_launch.sh` — G1(chrono idle) ∧ G2(reset 경과) 게이트 + single-runner lock.
  발사 후 consolidate → sleeve rebuild → eval 자동 체인. BF=2015-01..2024-02, budget=6000.
- Windows scheduled task **DART_Priority_Backfill_2015_2024** (07-06 00:05) = 신뢰 backstop.
- 파일 무충돌: 연대순(2009) vs priority(2015+) 다른 월 checkpoint. 공유 자원 = API cap 뿐(게이트가 순차화).

## 4. Book harness 준비 완료

- `code/eval_dart_sleeve.R` — eval_lag1.R 재사용. BASE=STR_1715 score_eff + PG2 overlay,
  canonical LinTilt top-20 recon (자체합성 없음), blend(ym+Ticker, **LAG=1** PIT-safe single-lag).
  metrics: book_ir · dIR_win(window-restricted PG2 대비) · paired NW-t · book_port_t · **oos_v2** · calmar · mdd.
- sleeve 4종: DINSD_OFF(임원 net) · DINSD_OFFB(임원 breadth) · DINSD_NET(전체 net) · DINSD_BRD(전체 breadth).

## 5. 예비 실측 (2005-2009 pre-decay 51월 — 감쇠벽 test 아님, 파이프라인 smoke)

| sleeve | bw | dIR_win | paired_NW_t | oos_v2 | acor_pg2 |
|---|---|---|---|---|---|
| DINSD_NET | 0.9 | **−0.017** | −0.97 | 1.99 | 0.45 |
| DINSD_NET | 0.7 | −0.016 | −0.93 | 2.03 | 0.45 |
| DINSD_BRD | 0.9 | −0.007 | −0.63 | 1.92 | 0.34 |
| DINSD_BRD | 0.7 | −0.133 | −2.17 | 2.10 | 0.34 |
| DINSD_OFF/OFFB | — | SKIP (officer coverage 0) | | | |

**해석 (엄격 bounded)**:
- 2005-2009 window 에서 DART 전체-net sleeve = **book-marginal 개선 없음**(dIR ≤ 0), breadth 는 가중↑ 시 유의하게 악화.
- ⚠ **이 window 는 질문의 대상이 아님**: (a) officer 신호(sharp) 부재, (b) 감쇠벽(2017+) 이전이라 oos_v2≈2.0 은 무의미.
- standalone active-cor vs PG2 = **0.45(NET)/0.34(BRD)** → PG2 active 와 중간 상관 = 잔차 직교 여지 존재(감쇠구간 검증 가치).
- **감쇠벽(oos 0.52) 돌파 여부는 미결** — officer sleeve × 2015-2024 실측 필요.

## 6. 다음
- 07-06 00:05 priority backfill 발사 → 2015-2024 수집(~6000 call/day, 감쇠구간 ~110월 → budget 여러 날 분할).
- 충분 축적(예: 2015-2020 ≥ 24 officer-signal month) 시 eval 자동 실행 → results_dart_priority_*.csv.
- **확정 실측 예상**: priority budget 6000/day, 감쇠구간 110월 × ~150 call/월 ≈ 16,500 call → **~3 run-day** (연대순과 cap 공유 시 지연 가능).
