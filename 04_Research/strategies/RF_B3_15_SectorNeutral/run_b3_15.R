# run_b3_15.R — 규칙기반 고속강화 B3-15 드라이버 (rulefast 15/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=15
# 만다트: 텔레그램·L-code 금지 (병렬 B3 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

emit_lcode <- function(...) {
  cat("[B3-15] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B3_15_SectorNeutral/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B3_15_SectorNeutral",
  strategy_idea = paste(
    "규칙기반 고속강화 B3-15: B1-5 승자 신호(모멘텀 12-1 rankZ 50% + Amihud 비유동성",
    "rankZ 50%)의 랭킹 축을 섹터(Sector_Lv2) 내부 횡단면으로 옮기고 25종을 섹터별",
    "균등 배분 — Moskowitz-Grinblatt(1999) 산업 귀속 검정의 한국 시장 적용.",
    "성과가 남으면 종목 선택, 사라지면 산업 베팅이었다."),
  factor_engine_path = "04_Research/strategies/RF_B3_15_SectorNeutral/fe_b3_15_sectorneutral.R",
  portfolio_spec = list(construction = "engine_direct", weighting = "ew",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://onlinelibrary.wiley.com/doi/10.1111/0022-1082.00146",
    title = "Moskowitz & Grinblatt (1999), Do Industries Explain Momentum?, JF 54(4)",
    paper_key = "moskowitz_grinblatt_1999_jf"),
  commission_paper = 0.0015,
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B3_15_SectorNeutral/stage",
  send_telegram = FALSE
)
cat("\n[B3-15] done. run_id =", res$run_id, "\n")
