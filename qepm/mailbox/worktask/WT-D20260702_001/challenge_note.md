# Self-Adversarial Challenge Note — WT-D20260702_001 (alpha-research)

**v8.2 Opus 4.8 native adversarial review** (no external Codex). Finalize 직전 자기 적대검증.
Charter Section 8 (No Silent Override) 의무 기록. AX-008 3-source 중 self-adversarial source.

## Context
- wt_type = discovery. theme = "W2 end-to-end test: consume discovery_seed.json".
- Step 0 seed: family=earnings_rev, H=3, factor_ids=[C01_SUE, C02_EPS_Chg_1m, C04_ESBR,
  C05_ESCR, C06_TP_Gap, C19_Composite_Earnings], proxy_recent_port_t=2.58,
  canonical_recent_port_t=0.6958, caveat="quarterly-marking artifact; recent-only; decay".
- 측정: canonical_screen_bt (contract build_benchmark_compare, NW lag-3), MONTHLY (1M) rebalance
  = WT-mandated basis (request forecast_horizon=1M, rebalance_frequency=monthly). metric_type=canonical_screen.

## Concerns raised (devil's advocate, >=3)

### C-1 [ACCEPT] recent-period edge does NOT exist on monthly basis
- Claim under attack: "earnings-revision is a live alpha".
- Evidence: recent (2021-01+) monthly PORT_t = **-0.32** (p=0.75, IR -0.15, net_sr -0.15).
  Full-period PORT_t 2.10 is driven ENTIRELY by 2010-2015 (PORT_t 3.20); 2016-2020 = -0.42,
  2021-2026 = -0.32. This is cohort-wide **decay-pattern** (measurement-graduation S3), not a
  live edge. Proxy 2.58 was H=3 quarterly non-overlapping marking = artifact (seed caveat confirmed).
- Classification: **ACCEPT**. The candidate FAILS graduation. Reported honestly as decay/screen-tier.
  challenge_flags carries the caveat forward (proxy 2.58 NOT used as evidence anywhere).

### C-2 [ACCEPT] IC t-stat overstates realized alpha (IC != PORT_t)
- Claim under attack: "rank-IC t = 7.63 => strong signal".
- Evidence: rank_ic_full 0.0489 (>0.04 benchmark), rank_ic_t 7.63, icir 0.477 all look strong,
  yet monthly PORT_t only 2.10 full / -0.32 recent. Cycle 2 lesson reproduced: cross-sectional
  rank power does not translate to long-only top-25 realized active return. rank-IC is ADVISORY
  (WS2 severity); PORT_t (hard) is authoritative and it FAILS.
- Classification: **ACCEPT**. alpha_package reports BOTH, flags divergence explicitly.

### C-3 [ACCEPT] single-factor and placebo confirm no residual edge
- Claim under attack: "maybe a component (C19 composite / C01 SUE) carries recent alpha".
- Evidence: C19_Composite_Earnings recent PORT_t -0.95; C01_SUE recent -1.15. Placebo(random)
  full -0.36, recent -1.01 (correctly negative => no leakage / measurement not broken). Neither
  the composite nor its strongest components produce recent edge.
- Classification: **ACCEPT**. No salvageable recent sub-signal.

### C-4 [PARTIAL] PIT / look-ahead integrity of the panel score
- Concern: panel uses pre-C13 raw factor snapshot; I standardize cross-sectionally per month
  (no future info in z-score) and use fwd_ret_1m (forward). BM forward 1M via shift(-1) on
  monthly-compounded daily. Direction = registry higher_better (fixed, not IC-fit -> no C13/C1
  full-sample flip). No lockbox/paper-trade window touched.
- Residual risk: panel factor snapshot PIT correctness inherited from builder (Factor_Date<=sig_d)
  and NOT independently re-audited here. The verdict is FAIL regardless, so look-ahead would only
  make a failing candidate look better — asymmetric; a PIT bug cannot rescue this candidate.
- Classification: **PARTIAL**. Documented; does not change the FAIL verdict.

## Self-rationalization auto-detection
- Scanned my own text for banned phrases ("미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일").
- None used to justify a pass. No rationalization detected. The verdict is FAIL, so there is no
  incentive-to-pass to guard against; the risk would be the reverse (over-claiming failure), and
  the negative placebo + positive 2010-2015 segment confirm the machinery is measuring real signal,
  not noise.

## Q-Lead escalate triggers
- HIGH severity >= 5? No (this is a clean, honest FAIL, not a governance breach).
- AX axiom hard FAIL >= 3? No.
- PIT C1 (lockbox/lookahead) violation? No.
- => No auto-escalate. Reported as decay-pattern screen-tier candidate; NOT capital-grade.

## Verdict
earnings-revision composite (seed candidate) on the WT-mandated **monthly 1M basis**:
- **Graduation: FAIL** (recent PORT_t -0.32 << 2.95 hard; full 2.10 < 2.95; decay-pattern).
- **Screening tier: marginal** (rank_ic 0.049 > 0.04 signal exists cross-sectionally, but no
  realized long-only alpha recently). screen_route = none actionable / DPL_FEATURE at most.
- W2 wiring test: **PASS** (seed consumed in Step 0, factor_ids used in Step 2, caveat carried
  to challenge_flags, canonical<<proxy handled without using proxy as evidence).
