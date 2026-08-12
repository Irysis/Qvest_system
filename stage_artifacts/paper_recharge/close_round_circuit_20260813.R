source("02_Infrastructure/contracts/close_round.R")

close_round(
  round_id        = "PAPER_ROUTER_20260813_CIRCUIT",
  verdict_type    = "config_scoped_negative",
  mechanism_diagnosis = paste0(
    "Daily t+1 upper-circuit carry effect (Das 2026) reversed at monthly rebal+large-cap config. ",
    "IC=-0.027 (direction reversed). Scale mismatch: daily->21d ratio aggregation averages out signal. ",
    "Universe mismatch: NSE all-stocks->KR large-cap (upper circuit = speculative small-cap sign -> mean-revert). ",
    "metric_type=proxy, Grade F, QUARANTINE."
  ),
  next_probes = c(
    "P1: Binary quintile check -- circuit_hit>=1 vs =0 next-month return t-test (canonical_screen_bt 2-group). Direction test first.",
    "P2: Event-conditional monthly -- hold stock only in the month immediately after upper-circuit event (t+1 mechanism monthly approximation). IC direction retest."
  ),
  consumer_surfaces = c(
    "universe_filter: KOSDAQ sub-sample (higher circuit density)",
    "overlay_input: event-conditional regime entry signal",
    "RAMP_event_sleeve: low-capacity conditional signal"
  ),
  frontier_update = "FQ registration deferred pending P1. If P1 shows positive direction, register new FQ for event-conditional monthly implementation.",
  live_trigger = paste0(
    "Revival conditions: ",
    "(1) Daily rebalance infra added -> re-attempt as daily implementation preserving t+1 mechanism. ",
    "(2) KOSDAQ150-only subsample shows circuit hit density >15% -> bypass large-cap universe limit. ",
    "(3) Additional East-Asian price-limit market evidence (Taiwan/Thailand) published -> cross-market revalidation."
  )
)
