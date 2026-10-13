## MC1 · MC3 통합 확인 (2026-10-13) — 실제 데이터로 측정 축 ALL_HYG(전 종목 + 위생 · 2000-01-01)가 끝까지 도는가
##   엔진 = 04_Research/strategies/RP_AUTO_cond_mat_0410079(롱온리 top-25 · 컨센서스 신호 — 커버리지 기록 시험에도 맞다)
##   운영 무오염: QVEST_RP_REGISTER=0 · QVEST_RP_NO_LCODE=1 · QVEST_NO_LEDGER_OPEN=1 · send_telegram=FALSE · 산출 = 이 폴더 runs/
##   A 가 나와도 judge_request*.json 은 *.EXPERIMENT_HOLD.json 으로 바꾼다(전환 전 측정 축 = Judge/BOOK 비대상).
## 실행: Rscript run_mc1_integration.R
suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT,
                        QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1")
EXP <- file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/mc1_integration")
RUNS <- file.path(EXP, "runs"); dir.create(RUNS, recursive = TRUE, showWarnings = FALSE)
SID <- "RP_AUTO_cond_mat_0410079"
sdir <- file.path(ROOT, "04_Research/strategies", SID)
fid <- fromJSON(file.path(sdir, "FIDELITY.json"), simplifyVector = FALSE)
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))
## v2(10-13 밤 · 전환 뒤): MC1_USE_DEFAULTS=1 이면 universe · start_date 를 넘기지 않는다 — 러너 기본값이 활성 epoch 에서
##   풀리는지(전환 경로) + 엔진 시작 리터럴 패치(.RP_START_DATE)로 2005 이전 보유가 생기는지(I6)를 함께 본다. 산출 이름에 _defaults.
USE_DEF <- identical(Sys.getenv("MC1_USE_DEFAULTS"), "1"); SFX <- if (USE_DEF) "_defaults" else ""
t0 <- Sys.time()
.rp_args <- list(
  strategy_name = paste0("MC1_INTEG_cond_mat_0410079_ALL_HYG", SFX),
  strategy_idea = "[MC1 통합 확인] 측정 축 ALL_HYG(전 종목 + 위생 · 2000-01-01) — 계약 주입 경로 실데이터 확인",
  factor_engine_path = file.path(sdir, "engine.R"), portfolio_spec = fid$portfolio_spec,
  source_paper = list(url = "https://arxiv.org/abs/cond-mat/0410079", paper_key = "cond-mat/0410079"),
  commission_paper = fid$commission_paper, out_root = RUNS, send_telegram = FALSE)
if (!USE_DEF) .rp_args <- c(.rp_args, list(universe = "ALL_HYG", start_date = "2000-01-01"))
r <- tryCatch(do.call(run_paper_replication, .rp_args), error = function(e) paste("ERROR:", conditionMessage(e)))
cat(sprintf("[mc1-integ] 측정 %s · %.1f분\n", if (is.character(r)) r else "ok", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
od <- list.dirs(RUNS, recursive = FALSE); od <- od[which.max(file.mtime(od))]
for (jr in c("judge_request.eligible.json", "judge_request.json"))
  if (file.exists(file.path(od, jr))) file.rename(file.path(od, jr), file.path(od, sub("\\.json$", ".EXPERIMENT_HOLD.json", jr)))
cat("[mc1-integ] 산출:", od, "\n")

## ── 점검 ──
A <- fromJSON(file.path(od, "authoritative_remeasure.json"), simplifyVector = FALSE)
H <- fread(file.path(od, "04_holdings.csv"))[target_weight > 0]
H[, date := as.Date(date)]
ok <- function(name, cond, detail = "") cat(sprintf("  [%s] %s %s\n", if (isTRUE(cond)) "PASS" else "FAIL", name, detail))
ma <- A$measurement_axis
ok("I1 권위 기록에 측정 축 블록(epoch all_hyg_2000_v1 · 시작 그대로 · 멤버십 진단)",
   identical(ma$epoch, "all_hyg_2000_v1") && isTRUE(ma$epoch_pure) && identical(ma$membership$mode, "injected"),
   sprintf("(멤버 하루 중앙 %s · 지수 멤버 %s)", ma$membership$members_per_day_median, ma$membership$index_members_per_day_median))
ok("I2 FIDELITY 에 전 종목 + 위생 자동 신고", grepl("전 종목 + 위생", A$replication$fidelity, fixed = TRUE), A$replication$fidelity)
ok("I3 등급 산출(권위 등급 존재 · 규칙 판 v3.1)", !is.null(A$essence_grade) && identical(A$grade_v3$rules_version, "v3.1"),
   sprintf("(등급 %s · S %s · CR %s)", A$essence_grade, format(A$grade_v3$S), A$grade_v3$cr$overall))
## 처치 전달 · PIT — 보유 종목이 신호일(= 집행 전 거래일 이하 마지막 거래일) 위생 멤버였는가 · 지수 비멤버가 있는가
suppressMessages(library(arrow))
RW <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"),
                                 col_select = c("Date", "Ticker", "K200", "KQ150", "Close", "Vol", "AdminStock", "TradingHalt", "UnfaithfulDisc")))
RW[, Date := as.Date(Date)]
source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R"))
ep <- ma_epoch("all_hyg_2000_v1")
RW[, HYG := ma_membership(RW, ep)]
cal <- sort(unique(RW$Date))
H[, sig := cal[findInterval(date, cal, left.open = TRUE)]]          # 집행일 전 거래일 = 월말 신호일
J <- merge(H, RW[, .(Date, Ticker, HYG, K200, KQ150)], by.x = c("sig", "ticker"), by.y = c("Date", "Ticker"), all.x = TRUE)
ok("I4 [PIT] 모든 보유가 신호일 위생 멤버(20일 거래대금 t−1 ≥ 하한 ∧ 관리 · 정지 · 불성실공시 아님)", all(J$HYG %in% TRUE),
   sprintf("(위반 %d/%d)", sum(!(J$HYG %in% TRUE)), nrow(J)))
nonidx <- J[!(K200 %in% 1) & !(KQ150 %in% 1)]
ok("I5 [처치 전달] 지수(K200∪KQ150) 비멤버 보유가 있다 — 구 축이면 0", nrow(nonidx) > 0L,
   sprintf("(비멤버 보유 %d/%d · 날짜 %d)", nrow(nonidx), nrow(J), uniqueN(nonidx$date)))
ok("I6 시작 2000 축 — 첫 보유일이 2000년대 초(신호 커버리지가 정한다 · 기록됨)", min(H$date) < as.Date("2005-01-01"),
   sprintf("(첫 보유 %s · 첫 신호 %s)", format(min(H$date)), ma$signal_coverage$first_signal_date))
cat("[mc1-integ] 신호 커버리지(연도별 폭/멤버 중앙값) — 처음 6년:\n")
print(head(rbindlist(lapply(ma$signal_coverage$by_year, as.data.table)), 6))
## MC8 짝 대조 — 위생 유니버스로
source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"))
card <- tryCatch(mc_card(od, root = ROOT), error = function(e) e)
ok("I7 MC8 짝 대조가 ALL_HYG(위생 멤버십)로 돈다", !inherits(card, "error") && identical(card$controls$spec$universe, "ALL_HYG"),
   if (inherits(card, "error")) conditionMessage(card) else sprintf("(귀속 %s · 대조 상태 %s)", card$controls$attribution$overall$label, card$controls$status))
if (!inherits(card, "error")) mc_write(card, file.path(EXP, paste0("card", SFX)), root = ROOT)
writeLines(toJSON(list(out_dir = od, defaults_path = USE_DEF, grade = A$essence_grade, S = A$grade_v3$S, measurement_axis = ma$epoch,
                       first_holding = format(min(H$date)), first_signal = ma$signal_coverage$first_signal_date,
                       nonindex_holdings = nrow(nonidx), holdings = nrow(J)), auto_unbox = TRUE, pretty = TRUE),
           file.path(EXP, paste0("integration_summary", SFX, ".json")))
cat("[mc1-integ] 끝\n")
