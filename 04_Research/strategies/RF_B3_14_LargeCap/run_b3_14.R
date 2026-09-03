# run_b3_14.R — 규칙기반 고속강화 B3-14 드라이버 (rulefast 14/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=14
# 만다트: 텔레그램·L-code 금지 (병렬 B3 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

emit_lcode <- function(...) {
  cat("[B3-14] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B3_14_LargeCap/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B3_14_LargeCap",
  strategy_idea = paste(
    "규칙기반 고속강화 B3-14: B1-5 승자(모멘텀 12-1 rankZ 50% + Amihud 비유동성 rankZ 50%,",
    "long-only top-25 EW 월간)를 신호·비중 그대로 두고 **적용 유니버스만** 시가총액 상위 1/3",
    "밴드로 교체. 필터순서 = K200∪KQ150 → adv20>=2e8(t-1) → 횡단면 Size 상위 1/3(시변).",
    "B3-13(소형주 밴드)의 대조 셀 — 두 셀이 함께 크기 축의 부호와 단조성을 판정한다."),
  factor_engine_path = "04_Research/strategies/RF_B3_14_LargeCap/fe_b3_14_largecap.R",
  portfolio_spec = list(construction = "top_n_long", weighting = "ew",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://www.sciencedirect.com/science/article/abs/pii/0304405X81900180",
    title = "Banz (1981), The relationship between return and market value of common stocks, JFE 9(1)",
    paper_key = "banz_1981_jfe"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B3_14_LargeCap/stage",
  send_telegram = FALSE
)
cat("\n[B3-14] done. run_id =", res$run_id, "\n")
