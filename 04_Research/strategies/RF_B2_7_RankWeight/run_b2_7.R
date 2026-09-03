# run_b2_7.R — 규칙기반 고속강화 B2-7 드라이버 (rulefast 7/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=7
# 만다트: 텔레그램·L-code 금지 (병렬 B2/B3 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B2-7] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 러너의 자동 rf_open_entry 를 섀도로 가로챈다 (call-time source 지점).
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B2_7_RankWeight/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B2_7_RankWeight",
  strategy_idea = paste(
    "규칙기반 고속강화 B2-7: B1-5 승자 신호(모멘텀 12-1 rank-Z 50% + Amihud 비유동성",
    "rank-Z 50%)를 그대로 두고 비중만 랭크 선형 가중 w ∝ (26−rank) 으로 교체",
    "(Asness-Moskowitz-Pedersen 2013 rank-weighted 구성의 long-only 25종 절단판).",
    "B2-6 스코어 틸트의 순서통계 판 — 스코어 크기 정보가 값을 하는지 대조한다.",
    "K200∪KQ150 · adv20>=2e8(t-1) · 2005-01~ · 월간 · 15bps."),
  factor_engine_path = "04_Research/strategies/RF_B2_7_RankWeight/fe_b2_7_rankweight.R",
  portfolio_spec = list(construction = "engine_direct", weighting = "rank_linear",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://onlinelibrary.wiley.com/doi/10.1111/jofi.12021",
    title = "Asness, Moskowitz & Pedersen (2013), Value and Momentum Everywhere, JF 68(3)",
    paper_key = "asness_moskowitz_pedersen_2013_jf"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B2_7_RankWeight/stage",
  send_telegram = FALSE
)
cat("\n[B2-7] done. grade =", res$grade %||% "?", "\n")
