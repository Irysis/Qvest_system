# run_b3_13.R — 규칙기반 고속강화 B3-13 드라이버 (rulefast 13/20)
# 원장 entry: RP_20260829_122020_9192_rulefast, attempt n=13
# 만다트: 텔레그램·L-code 금지 (병렬 B3 배치 — 보고는 세션이 담당)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/alpha_search/run_paper_replication.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# 만다트: L-code 금지 — 세션-로컬 무력화 (하네스 파일 무수정, 이 프로세스 한정)
emit_lcode <- function(...) {
  cat("[B3-13] emit_lcode suppressed (mandate: 병렬 rulefast — L-code 금지)\n")
  invisible(NULL)
}

# 원장 보호 — 러너의 자동 rf_open_entry 만 섀도로 가로챈다 (line 342 call-time source).
.RP_INFRA <- file.path(PROJECT_ROOT,
                       "04_Research/strategies/RF_B3_13_SmallCap/shadow_infra")

res <- run_paper_replication(
  strategy_name = "RF_B3_13_SmallCap",
  strategy_idea = paste(
    "규칙기반 고속강화 B3-13: B1-5 승자(모멘텀 12-1 rank-Z 50% + 비유동성 Amihud",
    "aligned-Z 50%, long-only top-25 EW 월간, 15bps)를 신호·비중 무변경으로 유지하고",
    "적용 유니버스만 교체 — K200∪KQ150 멤버십 대신 거래 가능 전 종목(지수 무관) 중",
    "매 리밸일 횡단면 시가총액 하위 1/3. 필터 순서 = adv20>=2e8(t-1) 하한 적용 후",
    "하위 1/3(실투 가능 집합 안에서의 소형주). Banz(1981) 규모 효과의 크기 축 단독 시험."),
  factor_engine_path = "04_Research/strategies/RF_B3_13_SmallCap/fe_b3_13_smallcap.R",
  portfolio_spec = list(construction = "top_n_long", weighting = "ew",
                        n_long = 25L, rebalance = "monthly"),
  # ★유니버스 치환은 엔진 안에서 수행 — 러너의 K200_KQ150 재치환을 피한다(no-op 라벨).
  universe = "SIZE_BOTTOM33_ALLTRADABLE",
  source_paper = list(
    url = "https://www.sciencedirect.com/science/article/abs/pii/0304405X81900180",
    title = "Banz (1981), The relationship between return and market value of common stocks, JFE 9(1)",
    paper_key = "banz_1981_jfe"),
  commission_paper = 0.0015,   # 실투형 15bps — 등급 판과 동일 (이중 시뮬 단일화)
  start_date = "2005-01-01",
  out_root = "04_Research/strategies/RF_B3_13_SmallCap/stage",
  send_telegram = FALSE
)
cat("\n[B3-13] done. run_id =", res$strategy_id %||% "?", "\n")
