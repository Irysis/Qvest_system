# =============================================================================
# run_b1_4.R — 규칙기반 고속강화 B1-4 드라이버 (설계 재량 0)
# =============================================================================
# 병렬 B1 지시(도훈 2026-08-29): 텔레그램·L-code 금지 + 전략 디렉터리 밖 쓰기 금지.
#   → send_telegram=FALSE + emit_lcode 스텁 + rf_open_entry lockBinding 차단
#     (러너의 원장 자동 open 은 tryCatch 비치명 — 원장 마감은 부모 세션 소관).
# 비용: 15bps 단일 판 (commission_paper=0.0015 → sim 1회, 등급 판과 동일).
# =============================================================================
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)

source("02_Infrastructure/alpha_search/run_paper_replication.R")

# --- 지시 준수: L-code 발행 차단 (스텁 — 러너 호출은 tryCatch 내부) ---
emit_lcode <- function(...) { cat("[B1-4] emit_lcode 차단 (지시: L-code 금지)\n"); NULL }

# --- 지시 준수: 강화 원장 write 차단 (source 재정의 시 locked binding 에러 → tryCatch 비치명) ---
rf_open_entry <- function(...) stop("[B1-4] rf_open_entry 차단 (지시: 전략 디렉터리 밖 쓰기 금지)")
lockBinding("rf_open_entry", globalenv())

res <- run_paper_replication(
  strategy_name      = "RF_B1_4_MomRevision",
  strategy_idea      = "규칙기반 고속강화 B1-4: 모멘텀(12-1) rank-Z + 이익수정 브레드스 3개월(C13) rank-Z 50/50, long-only top-25 EW 월간 (JT1993 + Chan-Jegadeesh-Lakonishok 1996)",
  factor_engine_path = "04_Research/strategies/RF_B1_4_MomRevision/fe_rf_b1_4_momrevision.R",
  portfolio_spec     = list(construction = "top_n_long", weighting = "ew",
                            n_long = 25L, rebalance = "monthly"),
  source_paper       = list(
    url       = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.1996.tb05222.x",
    paper_key = "chan_jegadeesh_lakonishok_1996",
    title     = "Momentum Strategies (Chan, Jegadeesh & Lakonishok 1996, JF 51(5))"),
  commission_paper   = 0.0015,     # 실투형 15bps 판 — 등급 기준과 동일 (단일 sim)
  start_date         = "2005-01-01",
  out_root           = file.path(ROOT, "04_Research/strategies/RF_B1_4_MomRevision/stage_artifacts"),
  send_telegram      = FALSE)

cat("\n[B1-4] DONE — strategy_id=", res$strategy_id, " grade=", res$grade,
    " out=", res$out_dir, "\n", sep = "")
