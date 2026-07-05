# Directional Disclosure-Event Feasibility Probe (screening-tier, NOT a WT)

**Date**: 2026-07-06
**Mandate**: self-contained feasibility probe. Light-touch (parallel insider/exec_netbuy DART backfill running). No wt_create/advance, no book_state, governor untouched.
**Question**: Are directional **long-side** disclosure-event signals (major supply/sales contract 단일판매ㆍ공급계약체결, provisional earnings 영업(잠정)실적) (a) cheaply extractable and (b) showing IC→PORT_t life signs — as a route *around* the short-side-driven IC→PORT_t wall that killed return-derived/consensus/sizing/construction this session?

---

## Phase 0 — cheap-kill feasibility (DECISIVE)

### 0.1 Are the events in DART OpenAPI? — YES (cheap metadata channel exists)
`list.json?pblntf_ty=I` (거래소공시 / KRX fair-disclosure) returns these `report_nm` (verified live, 2024-05 window):
- `단일판매ㆍ공급계약체결` (single supply/sales contract) — directional long-side (winning a contract = positive news)
- `연결재무제표기준영업(잠정)실적(공정공시)` (provisional operating earnings)
- `연결재무제표기준영업실적등에대한전망(공정공시)` (earnings guidance/outlook)
- bonus: `매출액또는손익구조30%이상변동` (30%+ revenue/profit change) — but 0 universe hits in sample

Metadata (`rcept_no`, `corp_code`, `stock_code`, `report_nm`, `rcept_dt`) is free from `list.json` — the SAME cheap channel the insider collector uses for its list step.

### 0.2 Is there a STRUCTURED detail endpoint (magnitude without parsing)? — **NO**
Tested plausible endpoint names for the contract amount (계약금액): `cntrctSttusEtc.json`, `majrCntrct.json`, `salesCntrct.json`, `prvsrTrmMttrCptl.json`, `fnnrSttus.json`, `estmPrfmnc.json` → **all return `status 101 잘못된 URL`** (endpoint does not exist).
- Contrast: buyback DOES have a structured endpoint (`tsstkAqDecsn.json`, 30 fields incl. amounts) because it is a 주요사항보고서. Supply-contract & provisional-earnings are 거래소 자율/공정공시 — **DART exposes them only as `document.xml`** (zip, ~3KB/doc, verified http-200).
- **⇒ The signal MAGNITUDE (계약금액/시총; actual-vs-guidance) requires document.xml parsing = the SAME heavy document-parse wall as the insider (elestock) channel.**

### 0.3 Coverage (cheap channel, universe K200∪KQ150 n=348) — PASSES
2024-05 (a Q1-earnings-reporting month):
| event | universe distinct tickers/mo |
|---|---|
| supply contract | 20 (continuous stream) |
| provisional earnings | 121 (episodic — clusters at quarter-end) |
| combined | **136 / 348 = 39%** |
Coverage is sufficient for a monthly cross-sectional signal.

### 0.4 Build cost of the heavy path (measured, not estimated)
`list.json?pblntf_ty=I` page counts per month (observed live):
- 2023-01: 25 pages (2,406 disc) · 2023-02: **66 pages** (6,565) · 2023-03: **122 pages** (12,148, annual-report+Q4 season)
- Earnings-season months (Feb/Mar/May/Aug/Nov) flood to 60–120 pages. A full 2005–2026 (~250-month) `list.json` sweep alone ≈ thousands of paged calls; **then** each supply/earnings event needs a `document.xml` fetch+parse for the amount.
- At the mandated 0.7–0.8s/call this is a multi-hour job **concurrent with the running insider backfill** → quota + memory contention (my probe R process segfaulted twice at exit-1 on the 12k-row month, consistent with known R-segfault-under-memory-pressure). **This is the "무거운 build를 blind로 돌리지 말 것" case.**

---

## Phase 1 — occurrence-only IC micro-characterization (cheap, no doc parse)
Because magnitude needs the heavy path, I tested the ONE thing that IS cheap: does the **mere occurrence** (binary, no amount) of a directional event carry forward-return info? (3 cached months 2023-01..03; SIGN characterization only, NOT a graduation t-stat.)

| signal (occurrence) | mean monthly IC | event-vs-rest fwd1 diff | Welch t (p) |
|---|---|---|---|
| supply contract | +0.003 (sign flips −0.06/−0.03/+0.10) | +1.06%/mo | 0.59 (p=0.55) |
| provisional earnings | −0.011 | **−0.00%** | **0.00 (p=0.997)** |

- **Earnings occurrence ≈ exactly zero** — expected: announcing earnings is not directional without the beat/miss (= the numbers you must parse or join to consensus).
- **Supply-contract occurrence** hints weakly positive (+1.06%/mo) but **not significant** and sign-unstable — and any real edge lives in the *magnitude* (a KRW 5B contract vs a KRW 5T contract), which is behind the document-parse wall.
- Consistent with sibling probe `probe_longside_harvest_20260705`: directional long-side signals (target-price upside, DPS growth) hit `full_PORT_t≈0.48`, `rec2017_PORT_t≈−1.40` — the long-side + top-25 long-only IC→PORT_t transition wall.

---

## VERDICT: feasibility **CONDITIONAL NO-GO for separate light-touch build** (heavy-parse required; cheap occurrence signal is null)

1. **Cheap metadata channel exists** (list.json), coverage OK (39%), but the **directional content (magnitude/beat) is ONLY in document.xml** — identical heavy document-parse wall to the insider channel that a parallel session is already grinding.
2. **Occurrence-without-magnitude is measurably null** (earnings t=0.00; supply t=0.59 sign-unstable) → the cheap version does not clear the cheap-kill IC gate.
3. Therefore a standalone build now = (a) heavy document.xml parsing that (b) duplicates the insider document-parse effort already in flight (quota/memory contention) to chase (c) a signal facing the same already-measured long-side IC→PORT_t wall. **Low EV; do NOT start a separate heavy build in parallel with the running backfill.**

### Honest caveats / where it is NOT closed
- This does **not** falsify a directional-disclosure *alpha* — it was only measured in the cheap **occurrence** form on 3 months. The **magnitude-scaled** contract signal (계약금액/시총, PIT t-1) is genuinely untested and is the only version with a real prior.
- **Recommended sequencing (not abandonment)**: defer to *after* the insider backfill finishes (frees the DART document-parse pipeline + quota), then reuse the same `document.xml` parser infrastructure to extract 계약금액 for supply-contracts (the continuous, inherently-directional stream — earnings needs a consensus join and is episodic, lower priority). Run it through canonical_screen_bt (top-25 EW, 15bps, NW lag-3) with placebo + lag1 PIT. That is a proper QEPM-adjacent measurement, not a light-touch probe.

## Files
- `events_raw_2023_2024.csv` (partial — 3 months cached in `months/`; fetch intentionally stopped for light-touch)
- `months/{202301,202302,202303}.csv` — supply+earn event metadata (list.json)
- `ic_micro3.R` + inline results above · `fetch_events*.R` (collectors) · `fetch2_log.txt` (page-count evidence)
