# run_b3_11.R — 규칙기반 고속강화 B3-11 드라이버 (rulefast 11/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=11
# 만다트: 텔레그램·L-code 금지 (병렬 B2-6~B3-15 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

emit_lcode <- function(...) {
  cat("[B3-11] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B3_11_KOSPI_All/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B3_11_KOSPI_All",
  strategy_idea = paste(
    "규칙기반 고속강화 B3-11: 신호·비중은 RF_B1_5_MomIlliq 완전 동일(모멘텀 12-1 rankZ 50%",
    "+ Amihud L01 aligned-Z rankZ 50%, long-only top-25 EW 월간, 15bps).",
    "바꾸는 것은 적용 유니버스 하나 — K200∪KQ150 지수 멤버십 제약을 제거하고",
    "상장 전수(adv20>=2e8 t-1 유지)로 확장. Hong-Lim-Stein(2000): 정보 확산이 느린",
    "소형·저커버리지 종목에서 모멘텀이 강하다. 기준선과의 차이 = 지수 멤버십이 무엇을 잘랐나."),
  factor_engine_path = "04_Research/strategies/RF_B3_11_KOSPI_All/fe_b3_11_kospi_all.R",
  portfolio_spec = list(construction = "top_n_long", weighting = "ew",
                        n_long = 25L, rebalance = "monthly"),
  universe = "KOSPI_ALL_LISTED_ADV20",   # 러너 멤버십 치환 비적용(엔진이 유니버스 확정)
  source_paper = list(
    url = "https://onlinelibrary.wiley.com/doi/10.1111/0022-1082.00206",
    title = "Hong, Lim & Stein (2000), Bad News Travels Slowly: Size, Analyst Coverage, and the Profitability of Momentum Strategies, JF 55(1)",
    paper_key = "hong_lim_stein_2000_jf"),
  commission_paper = 0.0015,
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B3_11_KOSPI_All/stage",
  send_telegram = FALSE
)
`%||%` <- function(a,b) if (is.null(a)) b else a
cat("\n[B3-11] done. run_id =", res$run_id %||% res$strategy_id %||% "?", "\n")
