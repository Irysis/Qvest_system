# run_b2_10.R — 규칙기반 고속강화 B2-10 드라이버 (rulefast 10/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=10
# 만다트: 텔레그램·L-code 금지 (병렬 B2 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B2-10] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 러너의 자동 rf_open_entry 를 섀도로 가로챈다(기존 entry attempt n=10 귀속).
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B2_10_HRP/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B2_10_HRP",
  strategy_idea = paste(
    "규칙기반 고속강화 B2-10: B1-5 승자 신호(모멘텀 12-1 rank-Z 50% + Amihud 비유동성",
    "rank-Z 50%)를 고정한 채 비중만 계층적 리스크 패리티(HRP, Lopez de Prado 2016)로",
    "교체한다. 상관거리 sqrt(0.5(1-rho)) → 단일연결 군집 → 준대각화 → 재귀 이분 배분.",
    "공분산 역행렬을 쓰지 않는다 — min-var 역행렬 불안정 셀의 대조군.",
    "상관 추정창 = 직전 60개월 월수익, 창 종점 t-1. long-only 25종 · Sum(w)=1 ·",
    "K200∪KQ150 · adv20>=2e8(t-1) · 2005-01~ · 월간 · 15bps."),
  factor_engine_path = "04_Research/strategies/RF_B2_10_HRP/fe_b2_10_hrp.R",
  portfolio_spec = list(construction = "engine_direct", weighting = "hrp",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://www.pm-research.com/content/iijpormgmt/42/4/59",
    title = "Lopez de Prado (2016), Building Diversified Portfolios that Outperform Out of Sample, JPM 42(4):59-69",
    paper_key = "lopezdeprado_2016_jpm_hrp"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B2_10_HRP/stage",
  send_telegram = FALSE
)
cat("\n[B2-10] done. grade =", res$grade, "| out =", res$out_dir, "\n")
