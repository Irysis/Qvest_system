# run_b1_5.R — 규칙기반 고속강화 B1-5 드라이버 (rulefast 5/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=5
# 만다트: 텔레그램·L-code 금지 (병렬 B1 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B1-5] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 미달 등급 시 러너가 rf_open_entry 로 공유 원장에 신규 entry 를 쓰는데,
# 본 시도는 기존 rulefast entry attempt n=5 에 이미 사전 등록됨(병렬 배치 — 원장 기입은
# 세션 소관). .RP_INFRA 를 섀도로 재지정해 line 342 의 call-time source 만 가로챈다.
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B1_5_MomIlliq/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B1_5_MomIlliq",
  strategy_idea = paste(
    "규칙기반 고속강화 B1-5: 모멘텀(12-1, JT1993) rank-Z 50% + 비유동성(Amihud 2002,",
    "L01_Amihud aligned-Z) rank-Z 50% 컴포짓 — long-only top-25 EW 월간,",
    "K200∪KQ150 · adv20>=2e8(t-1) · 15bps. L-family 를 통제에서 신호로 승격하는 시험."),
  factor_engine_path = "04_Research/strategies/RF_B1_5_MomIlliq/fe_b1_5_momilliq.R",
  portfolio_spec = list(construction = "top_n_long", weighting = "ew",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://www.sciencedirect.com/science/article/pii/S1386418101000246",
    title = "Amihud (2002), Illiquidity and Stock Returns: Cross-Section and Time-Series Effects, JFM 5(1)",
    paper_key = "amihud_2002_jfm"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B1_5_MomIlliq/stage",
  send_telegram = FALSE
)
cat("\n[B1-5] done. run_id =", res$run_id %||% "?", "\n")
