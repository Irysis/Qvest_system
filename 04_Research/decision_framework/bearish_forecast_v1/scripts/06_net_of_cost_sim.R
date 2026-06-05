#==============================================================================
# 06_net_of_cost_sim.R — Phase 2 RESERVED (Phase 1에서 호출 X)
#
# Plan v0.4.2 정합: Net-of-cost simulation은 Phase 2 (decision system) 단계
# Phase 1 = forecast validity only. 본 script는 stub retain만.
#
# Phase 2 진입 시:
#   - KODEX 200 인버스 (A114800) tracking error + roll yield + tax/slippage 분해
#   - cash_drag_measurement.R (02_Infra/risk/) 활용
#   - Sharpe / Sortino / Calmar / Net Sharpe 산출
#
# 본 script call → stop() with Phase 2 redirect message
#==============================================================================

run_net_of_cost_sim <- function(...) {
  stop("[06_net_of_cost_sim] Phase 2 RESERVED. ",
       "Plan v0.4.2 Phase 1 = forecast validity only. ",
       "Net-of-cost simulation은 Phase 2 (decision system) 진입 시 활성화.")
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  cat("[06_net_of_cost_sim] Phase 2 RESERVED stub. Phase 1 invocation blocked.\n")
}
