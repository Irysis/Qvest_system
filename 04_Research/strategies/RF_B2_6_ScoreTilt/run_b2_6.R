# run_b2_6.R — 규칙기반 고속강화 B2-6 드라이버 (rulefast 6/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=6
# 만다트: 텔레그램·L-code 금지 (블록 일괄 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B2-6] emit_lcode suppressed (mandate: 블록 일괄 — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 미달 등급 시 러너가 rf_open_entry 로 공유 원장에 신규 entry 를 쓴다.
# 본 시도는 기존 rulefast entry attempt n=6 에 사전 등록됨. .RP_INFRA 섀도 재지정으로
# line 342 의 call-time source 만 가로챈다.
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B2_6_ScoreTilt/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B2_6_ScoreTilt",
  strategy_idea = paste(
    "규칙기반 고속강화 B2-6: B1-5 승자 컴포짓(모멘텀 12-1 rank-Z 50% + Amihud 비유동성",
    "rank-Z 50%)을 그대로 이식하고 비중만 교체 — 상위 25종 EW 를",
    "팩터 스코어 틸트 w_i ∝ (z_i − min(z_25) + eps) 로 바꾼다.",
    "근거 = Grinold(1989) 기본법칙: 최적 액티브 비중은 알파에 비례.",
    "K200∪KQ150 · adv20>=2e8(t-1) · long-only · Σw=1 · 월간 · 15bps."),
  factor_engine_path = "04_Research/strategies/RF_B2_6_ScoreTilt/fe_b2_6_scoretilt.R",
  portfolio_spec = list(construction = "engine_direct", weighting = "score_tilt",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://www.pm-research.com/content/iijpormgmt/15/3/30",
    title = "Grinold (1989), The Fundamental Law of Active Management, JPM 15(3):30-37",
    paper_key = "grinold_1989_jpm"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B2_6_ScoreTilt/stage",
  send_telegram = FALSE
)
cat("\n[B2-6] done. run_id =", res$strategy_id, "grade =", res$grade, "\n")
