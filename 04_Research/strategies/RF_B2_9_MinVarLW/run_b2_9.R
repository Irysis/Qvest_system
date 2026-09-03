# run_b2_9.R — 규칙기반 고속강화 B2-9 드라이버 (rulefast 9/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=9
# 만다트: 텔레그램·L-code 금지 (병렬 B2 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B2-9] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 미달 등급 시 러너가 rf_open_entry 로 공유 원장에 신규 entry 를 쓰는데,
# 본 시도는 기존 rulefast entry attempt n=9 에 이미 사전 등록됨(병렬 배치 — 원장 기입은
# 세션 소관). .RP_INFRA 를 섀도로 재지정해 call-time source 만 가로챈다.
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B2_9_MinVarLW/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B2_9_MinVarLW",
  strategy_idea = paste(
    "규칙기반 고속강화 B2-9: 신호는 B1-5 승자 그대로(모멘텀 12-1 rankZ 50% +",
    "Amihud 비유동성 rankZ 50%) 고정하고, 비중만 EW → Ledoit-Wolf(2004 JMVA)",
    "축소 공분산 하 long-only 최소분산으로 교체. 공분산 창 = 직전 60개월 월수익,",
    "창 종점 = 시그널월 직전월(C1/C2). K200∪KQ150 · adv20>=2e8(t-1) · 15bps ·",
    "Σw=1 · w>=0. 가설 = 위기 동조 낙폭(MDD 59.3%)을 비중 축에서 줄일 수 있는가."),
  factor_engine_path = "04_Research/strategies/RF_B2_9_MinVarLW/fe_b2_9_minvar_lw.R",
  portfolio_spec = list(construction = "engine_direct", weighting = "minvar_ledoit_wolf",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://www.sciencedirect.com/science/article/pii/S0047259X03000964",
    title = "Ledoit & Wolf (2004), A well-conditioned estimator for large-dimensional covariance matrices, JMVA 88(2):365-411",
    paper_key = "ledoit_wolf_2004_jmva"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B2_9_MinVarLW/stage",
  send_telegram = FALSE
)
cat("\n[B2-9] done. run_id =", res$run_id %||% "?", " grade =", res$grade %||% "?", "\n")
