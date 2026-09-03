# run_b2_8_ctrl.R — 규칙기반 고속강화 B2-8 드라이버 (rulefast 8/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=8
# 만다트: 텔레그램·L-code 금지 (병렬 B2 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B2-8-CTRL] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 본 시도는 기존 rulefast entry attempt n=8 에 사전 등록됨.
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B2_8_InvVol/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B2_8_CTRL_EW",
  strategy_idea = paste(
    "[대조군] B2-8 동일 패널 EW 컨트롤: B1-5 승자 신호(모멘텀 12-1 rank-Z 50% + Amihud",
    "비유동성 rank-Z 50%) + 보유집합은 처치와 동일 + **비중만 EW**. 처치(w∝1/σ)와의",
    "델타에서 패널 갱신(daily_refresh) 교란을 제거하기 위한 동일 패널 기준선.",
    "B1-5(EW top-25)와 σ 부적격 0건이면 동일 구성."),
  factor_engine_path = "04_Research/strategies/RF_B2_8_InvVol/fe_b2_8_ctrl_ew.R",
  portfolio_spec = list(construction = "engine_direct", weighting = "ew_control",
                        n_long = 25L, rebalance = "monthly"),
  universe = "K200_KQ150",
  source_paper = list(
    url = "https://www.tandfonline.com/doi/abs/10.2469/faj.v68.n1.1",
    title = "Asness, Frazzini & Pedersen (2012), Leverage Aversion and Risk Parity, FAJ 68(1)",
    paper_key = "afp_2012_faj_riskparity"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B2_8_InvVol/stage_ctrl",
  send_telegram = FALSE
)
cat("\n[B2-8-CTRL] done. out_dir =", res$out_dir, " grade =", res$grade, "\n")
