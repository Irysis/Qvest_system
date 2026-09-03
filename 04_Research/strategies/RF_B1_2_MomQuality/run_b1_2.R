# =============================================================================
# run_b1_2.R — RF_B1_2_MomQuality rulefast 실행 드라이버 (병렬 B1-2)
# =============================================================================
# 블록 지시: 텔레그램·L-code 발행 금지(Q-Lead 일괄 소관) + 전략 디렉터리 밖 쓰기
# 금지(병렬 B1-1~B1-5 — 원장 RP_20260829_122020_9192_rulefast 는 이미 open,
# rf_open_entry 중복 등록 차단). 아래 스텁 3종이 그 경계를 강제한다.
# =============================================================================

root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

# ── 경계 스텁 1: L-code 발행 금지 (러너 tryCatch 가 비치명 처리) ──
emit_lcode <- function(...) stop("BLOCKED(B1-2): L-code 발행 금지 — Q-Lead 일괄 소관")
lockBinding("emit_lcode", globalenv())

# ── 경계 스텁 2: 강화 원장 쓰기 금지 (원장 entry 이미 open — 중복 등록 차단) ──
# 러너가 미달 등급 시 reinforce_ledger.R 를 재-source 하며 rf_open_entry 를
# 전역에 재정의하려 한다 → lockBinding 으로 재정의 자체를 에러로 만들어
# 러너의 tryCatch(비치명) 경로로 떨어뜨린다.
rf_open_entry <- function(...) stop("BLOCKED(B1-2): 원장 쓰기 금지")
lockBinding("rf_open_entry", globalenv())

res <- run_paper_replication(
  strategy_name = "RF_B1_2_MomQuality",
  strategy_idea = paste("rulefast B1-2: 모멘텀(12-1) rank-Z + 수익성 GP/A rank-Z 50/50 컴포짓,",
                        "상위 25종 EW 월간 리밸런싱 (JT1993 + Novy-Marx 2013)"),
  factor_engine_path = "04_Research/strategies/RF_B1_2_MomQuality/engine_momquality.R",
  portfolio_spec = list(construction = "top_n_long", weighting = "ew",
                        n_long = 25L, rebalance = "monthly"),
  source_paper = list(
    url = "https://www.sciencedirect.com/science/article/pii/S0304405X13000044",
    title = "Novy-Marx (2013) The Other Side of Value: The Gross Profitability Premium, JFE 108",
    paper_key = "rulefast_b1_2_momquality"),
  commission_paper = 0.0015,          # 실투형 단일 판 — 15bps 순비용
  start_date = "2005-01-01",
  out_root = file.path(root, "04_Research/strategies/RF_B1_2_MomQuality/artifacts"),
  send_telegram = FALSE               # 경계 스텁 3: 텔레그램 금지 (Q-Lead 소관)
)

cat("\n=== RF_B1_2 RESULT ===\n")
cat(sprintf("grade=%s | out=%s\n", res$grade, res$out_dir))
print(res$essence)
