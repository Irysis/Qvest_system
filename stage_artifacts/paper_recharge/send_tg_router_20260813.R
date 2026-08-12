source("02_Infrastructure/telegram/telegram_notify.R")

sections <- list(
  list(
    heading = "Route Summary (20260813)",
    type = "kv",
    kv = list(
      "arXiv candidates" = "35 (new:19, dup/reg:16)",
      "Curated new" = "0 (all 15 processed)",
      "alpha" = "1",
      "optimizer" = "1",
      "risk" = "3",
      "skip" = "14",
      "Factor testable" = "1",
      "Factor uncertain" = "1"
    )
  ),
  list(
    heading = "Autorun Result",
    type = "bullet",
    items = c(
      "T11_CIRCUIT_HIT_UPPER_21D (arXiv:2608.08625) -- Grade F / IC=-0.027 / MDD=64%",
      "Daily continuation effect REVERSED at monthly scale -- QUARANTINE",
      "next_probe (1): daily event-driven impl of upper-limit-close signal",
      "next_probe (2): binary quintile comparison (hit>=1 vs 0)"
    )
  ),
  list(
    heading = "Factor Candidates",
    type = "bullet",
    items = c(
      "[testable] circuit_hit_upper_ratio_21d (2608.08625, alpha route) -- KR price-limit memory",
      "[uncertain] min_eigenvalue_loading_60d (2608.09641, risk route) -- sync de-coupling"
    )
  ),
  list(
    heading = "Mode Queue",
    type = "bullet",
    items = c(
      "[optimizer] OOQI spec-driven pipeline synthesis (2608.10410) -- priority: conditional",
      "[risk] Correlation lower spectrum (2608.09641) -- priority: high",
      "[risk] Capacity/crowding design (2608.08405) -- priority: medium",
      "[risk] Lambda-quantiles (2608.07122) -- priority: low (tail_quantile)"
    )
  )
)

tg_agent_brief(
  agent = "AlphaSearch",
  title = "Paper Router: Source Routing + Factor Mining 20260813",
  sections = sections,
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260813"
)
