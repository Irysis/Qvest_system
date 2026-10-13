## MC3 B안 통합 확인 (2026-10-13 · 도훈 "B안으로 가자") — 러너 기본값 경로(측정 축 all_hyg_2000_v1)로 얇은 초기 폭 합성 엔진을 재
##   실효 시작 절단(§5-b) · FIDELITY 자동 신고 · 권위 기록(measurement_axis.effective_start · signal_coverage basis) · 창 진단(essence_diag) 배선을 확인한다.
##   운영 무오염: QVEST_RP_REGISTER=0 · QVEST_RP_NO_LCODE=1 · QVEST_NO_LEDGER_OPEN=1 · 팩터 분석 생략 · send_telegram=FALSE · 산출 = runs/
## 실행: Rscript run_mc3_thin_start.R
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT, QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1",
                        QVEST_NO_LEDGER_OPEN = "1", QVEST_RP_NO_FACTOR_ANALYSIS = "1")
EXP <- file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/mc1_integration")
RUNS <- file.path(EXP, "runs"); dir.create(RUNS, recursive = TRUE, showWarnings = FALSE)
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))
t0 <- Sys.time()
r <- tryCatch(run_paper_replication(
  strategy_name = "MC3_INTEG_thin_start_SYNTH",
  strategy_idea = "[MC3 B 통합 확인 · 합성] 2003 전 폭 30 → 실효 시작 절단 배선 확인(판정 대상 아님)",
  factor_engine_path = file.path(EXP, "mc3_thin_start_engine.R"),
  portfolio_spec = list(construction = "top_n_long", weighting = "ew", rebalance = "monthly", n_long = 25L),
  source_paper = list(url = "https://doi.org/10.1111/j.1540-6261.1993.tb04702.x", paper_key = "JT1993_wiring_test"),
  out_root = RUNS, send_telegram = FALSE), error = function(e) paste("ERROR:", conditionMessage(e)))
cat(sprintf("[mc3-thin] 측정 %s · %.1f분\n", if (is.character(r)) r else "ok", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
od <- list.dirs(RUNS, recursive = FALSE); od <- od[which.max(file.mtime(od))]
for (jr in c("judge_request.eligible.json", "judge_request.held.json", "judge_request.json"))
  if (file.exists(file.path(od, jr))) file.rename(file.path(od, jr), file.path(od, sub("\\.json$", ".EXPERIMENT_HOLD.json", jr)))
cat("[mc3-thin] 산출:", od, "\n")

A <- fromJSON(file.path(od, "authoritative_remeasure.json"), simplifyVector = FALSE)
H <- fread(file.path(od, "04_holdings.csv"))[target_weight > 0]; H[, date := as.Date(date)]
ok <- function(name, cond, detail = "") cat(sprintf("  [%s] %s %s\n", if (isTRUE(cond)) "PASS" else "FAIL", name, detail))
es <- A$measurement_axis$effective_start
ok("J1 실효 시작 = 2003 첫 월말 신호일(폭 30 < 50 인 2000~2002 신호일 제외) · 규칙 기록",
   identical(es$status, "ok") && as.Date(es$date) >= as.Date("2003-01-01") && as.Date(es$date) < as.Date("2003-02-01") &&
     es$n_dates_cut >= 30L && identical(A$measurement_axis$effective_start_rule$rule, "breadth_multiple"),
   sprintf("(실효 시작 %s · 제외 %s · 시작 폭 %s · 보유 %s)", es$date, es$n_dates_cut, es$breadth_at_start, es$holdings_at_start))
ok("J2 첫 보유 = 실효 시작 뒤(잘린 신호일의 보유 없음)", min(H$date) > as.Date(es$date), sprintf("(첫 보유 %s)", format(min(H$date))))
ok("J3 FIDELITY 자동 신고(실효 시작 · 제외 수)", grepl("실효 시작", A$replication$fidelity, fixed = TRUE), A$replication$fidelity)
ed <- A$essence_diag
ok("J4 창 진단 = 실효 시작 기준(기준일 = 실효 시작 · 이탈 0~1개월 · 기준 출처 MC3) · 전역 기준일 병기",
   is.list(ed) && identical(ed$window_anchor_date, es$date) && ed$window_deviation_months %in% c(0L, 1L) &&
     grepl("MC3", ed$window_anchor_basis, fixed = TRUE) && nzchar(ed$window_anchor_date_global %||% ""),
   sprintf("(기준 %s · 이탈 %s · 전역 %s)", ed$window_anchor_date, ed$window_deviation_months, ed$window_anchor_date_global))
sc <- A$measurement_axis$signal_coverage
by <- rbindlist(lapply(sc$by_year, as.data.table))
ok("J5 커버리지 폭 = 선정 전 패널(basis factors) — 2000~2002 폭 30 · 2003 이후 수백(보유 25 로 눌리지 않음)",
   identical(sc$basis, "factors") && all(by[yr < "2003"]$breadth_median == 30) && all(by[yr >= "2003"]$breadth_median > 100),
   sprintf("(2001 %s · 2005 %s)", by[yr == "2001"]$breadth_median, by[yr == "2005"]$breadth_median))
writeLines(toJSON(list(out_dir = od, effective_start = es, essence_diag_window = ed[c("window_anchor_date", "window_deviation_months", "window_anchor_basis")],
                       first_holding = format(min(H$date)), fidelity = A$replication$fidelity), auto_unbox = TRUE, pretty = TRUE),
           file.path(EXP, "mc3_thin_start_summary.json"))
cat("[mc3-thin] 끝\n")
