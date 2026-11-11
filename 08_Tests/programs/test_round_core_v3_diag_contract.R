#!/usr/bin/env Rscript
#==============================================================================
# test_round_core_v3_diag_contract.R — 셀 엔진의 기저 정합 진단 ↔ 코어 v3 측정 관문의 계약 시험 (2026-11-11 · 판 2 구축 S4)
#
# 왜: 코어 v3 의 측정 관문(rc_standing_base_alignment)은 셀 엔진(rf_cell_engine.R)이 산출 폴더에 쓰는 rf_engine_diag.json 의
#   base_alignment 를 읽어 판정 전에 측정을 가른다. 코어 시험은 관문에 **손으로 만든** 진단을 넣고, 셀 엔진 시험은 진단의 **내용**만 본다 —
#   둘 사이의 필드 이름 · 키 꼴이 어긋나면 실제 측정이 전부 측정 실패로 닫힌다(GPU 측정 몇 시간이 버려진다). 여기서는 **실제 셀 엔진**이 쓴
#   진단을 **실제 관문**에 넣는다.
#   C1 월말 격자 엔진 → 통과 · 요약 필드 13개 · base_kind factors      C2 60거래일 격자 → 통과(옮김 > 0 · 덮임 0)
#   C3 주간 격자 → base_off_month_grid                                  C4 포트폴리오만 내는 엔진 → base_not_score_panel
#   C5 진단 파일이 없는 산출(옛 셀 엔진 꼴) → base_alignment_missing     C6 기저가 엔진이 아닌 칸 → 관문 대상 아님
#   C7 요약에 τ_D 뒤 날짜 필드(last_*)가 없다
# 부작용 없음: 픽스처 · 격리 루트 전부 tempdir. 실자료 · 원장 무접촉.
# 실행(저장소 루트에서): Rscript 08_Tests/programs/test_round_core_v3_diag_contract.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
LIVE <- file.path(ROOT, "02_Infrastructure/reinforcement"); ENGINE <- file.path(LIVE, "rf_cell_engine.R")
PASS <- 0L; FAIL <- 0L
chk <- function(cond, m, d = "") if (isTRUE(cond)) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) } else { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
emit <- function() cat(sprintf('{"test":"round_core_v3_diag_contract","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
CORE <- file.path(ROOT, "04_Research/programs/_lib/round_core/v3/load.R")
if (!file.exists(ENGINE) || !file.exists(CORE)) { chk(FALSE, "전제", paste("없음:", ENGINE, CORE)); emit(); quit(status = 1L) }

TMP <- file.path(tempdir(), sprintf("rcv3dc_%d", Sys.getpid())); dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
SIBS <- c("rf_rebalance.R", "rf_sleeve.R", "rf_axes.R", "rf_base_cache.R", "rf_base_align.R")
make_root <- function(tag) {
  r <- file.path(TMP, tag)
  dir.create(file.path(r, ".cache", "factor_db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure", "reinforcement"), recursive = TRUE, showWarnings = FALSE)
  for (f in SIBS) file.copy(file.path(LIVE, f), file.path(r, "02_Infrastructure/reinforcement", f), overwrite = TRUE)
  writeBin(as.raw(rep(1L, 1000L)), file.path(r, ".cache", "rawdata.parquet")); writeBin(as.raw(rep(2L, 300L)), file.path(r, ".cache", "benchmark.parquet"))
  writeLines("20261111000000_aaaaaaa", file.path(r, ".cache", "factor_db", "build_hash.txt")); r
}
set.seed(20261111L)
.d <- seq(as.Date("2003-06-02"), as.Date("2008-12-31"), by = "day"); .d <- .d[as.integer(format(.d, "%w")) %in% 1:5]
FIX <- CJ(Ticker = sprintf("T%03d", 1:45), Date = .d); setorder(FIX, Ticker, Date)
FIX[, .r := rnorm(.N, 0.0003, 0.012)][, Close := 10000 * cumprod(1 + .r), by = Ticker][, .r := NULL]
FIX[, Vol := 200000][, Size := Close * 1e6][, K200 := as.integer(sub("T", "", Ticker, fixed = TRUE)) <= 40L][, KQ150 := FALSE]
FIX[, Sector_Lv2 := paste0("S", (as.integer(sub("T", "", Ticker, fixed = TRUE)) %% 5L) + 1L)]
BMF <- FIX[, .(BM_Ret = mean(Close / shift(Close) - 1, na.rm = TRUE)), by = Date]
head_ <- c("cal <- sort(unique(RAWDATA$Date))",
           "mk <- function(dates) { x <- RAWDATA[Date %in% dates, .(Date, Ticker)]; x[, Score := as.numeric(as.integer(Date)) * 1000 + as.integer(sub('T', '', Ticker, fixed = TRUE))]; x[] }")
weng <- function(name, body) { d <- file.path(TMP, name); dir.create(d, showWarnings = FALSE); p <- file.path(d, "engine.R"); writeLines(c(head_, body), p); p }
E <- list(
  ME = weng("ENG_ME", c("me <- cal[!duplicated(format(cal, '%Y%m'), fromLast = TRUE)]", "FACTORS <- mk(me[me >= as.Date('2004-06-01')])")),
  G60 = weng("ENG_60", c("g <- cal[cal >= as.Date('2005-01-01')]; g <- g[seq(1L, length(g), by = 60L)]", "FACTORS <- mk(g)")),
  WK = weng("ENG_WK", c("wk <- cal[!duplicated(format(cal, '%G%V'), fromLast = TRUE)]", "FACTORS <- mk(wk[wk >= as.Date('2004-06-01')])")),
  PF = weng("ENG_PF", c("me <- cal[!duplicated(format(cal, '%Y%m'), fromLast = TRUE)]", "x <- RAWDATA[Date %in% me[me >= as.Date('2004-06-01')], .(Date, Ticker)]",
                        "x[, i := as.integer(sub('T', '', Ticker, fixed = TRUE))]", "PORTFOLIO <- x[, .(Ticker, Weight = i / sum(i), Leg = 'long'), by = Date]")))
spec_of <- function(base) list(code = "DC", label = "diag-contract", block = "T",
                               fixed_axes = list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150", start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8),
                               base_signal = base, factor2 = list(kind = "none"), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
## 실제 셀 엔진을 격리 루트에서 돌려 산출 폴더(진단 파일)를 만든다 → list(spec = 칸 사양 경로, dir = 산출 폴더, err)
run_cell <- function(tag, base) {
  root <- make_root(tag); out <- file.path(TMP, paste0("out_", tag)); dir.create(out, showWarnings = FALSE)
  sp <- file.path(TMP, sprintf("spec_%s.json", tag)); writeLines(toJSON(spec_of(base), auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  old <- Sys.getenv(c("QM_ROOT", "RF_CELL_SPEC", "RF_ENGINE_DIAG_DIR"), unset = NA)
  on.exit(for (nm in names(old)) if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, setNames(list(old[[nm]]), nm)), add = TRUE)
  Sys.setenv(QM_ROOT = root, RF_CELL_SPEC = sp, RF_ENGINE_DIAG_DIR = out)
  env <- new.env(); assign("RAWDATA", copy(FIX), envir = env); assign("BM_DT", BMF, envir = env); err <- NULL
  invisible(capture.output(suppressWarnings(suppressMessages(tryCatch(source(ENGINE, local = env), error = function(e) err <<- conditionMessage(e)))), type = "output"))
  list(spec = sp, dir = out, err = err)
}
R <- list(ME = run_cell("ME", list(kind = "engine", path = E$ME)), G60 = run_cell("G60", list(kind = "engine", path = E$G60)),
          WK = run_cell("WK", list(kind = "engine", path = E$WK)), PF = run_cell("PF", list(kind = "engine", path = E$PF)),
          MOM = run_cell("MOM", list(kind = "mom_12_1")))
chk(all(vapply(R, function(x) is.null(x$err), logical(1))), "전제 — 실제 셀 엔진이 다섯 칸을 돌았다", paste(unlist(lapply(R, function(x) x$err)), collapse = " | "))

Sys.setenv(QM_ROOT = ROOT)
suppressMessages(source(CORE)); TAU <- "2022-12-31"
gate <- function(x, spec = x$spec, dir = x$dir) rc_standing_base_alignment(spec, dir, TAU, ROOT)
g <- gate(R$ME); s <- g$summary[["ENG_ME/engine.R"]]
chk(isTRUE(g$need) && isTRUE(g$ok) && !is.null(s) && setequal(names(s), RC_STANDING_BASE_SUMMARY) && identical(s$base_kind, "factors") &&
      identical(s$rule, "month_snap_v1") && isTRUE(as.numeric(s$n_moved) == 0) && isTRUE(as.numeric(s$n_offcal) == 0) && isTRUE(as.numeric(s$n_cell_dates_from_start) > 0),
    sprintf("C1 월말 격자 엔진의 실제 진단 → 관문 통과 · 요약 %d필드", length(RC_STANDING_BASE_SUMMARY)), paste(g$error, g$why, paste(names(s), collapse = ",")))
g2 <- gate(R$G60); s2 <- g2$summary[["ENG_60/engine.R"]]
chk(isTRUE(g2$ok) && isTRUE(as.numeric(s2$n_moved) > 0) && isTRUE(as.numeric(s2$n_superseded) == 0), "C2 60거래일 격자 → 통과(옮김 > 0 · 덮임 0)", paste(g2$error, g2$why))
g3 <- gate(R$WK)
chk(isTRUE(g3$need) && identical(g3$ok, FALSE) && identical(g3$error, "base_off_month_grid"), "C3 주간 격자 → base_off_month_grid", paste(g3$error, g3$why))
g4 <- gate(R$PF)
chk(identical(g4$ok, FALSE) && identical(g4$error, "base_not_score_panel"), "C4 포트폴리오만 내는 엔진 → base_not_score_panel", paste(g4$error, g4$why))
g5 <- gate(R$ME, dir = R$MOM$dir)                      # 엔진 기저 칸 사양 + 진단 파일이 없는 산출(기저 mom_12_1 칸은 진단을 쓰지 않는다)
chk(!file.exists(file.path(R$MOM$dir, "rf_engine_diag.json")) && identical(g5$ok, FALSE) && identical(g5$error, "base_alignment_missing"),
    "C5 진단 없는 산출 → base_alignment_missing(옛 셀 엔진으로 잰 측정 차단)", paste(g5$error, g5$why))
g6 <- gate(R$MOM)
chk(identical(g6$need, FALSE) && isTRUE(g6$ok), "C6 기저가 엔진이 아닌 칸 → 관문 대상 아님")
chk(!any(c("last_cell_date", "last_engine_date") %in% names(s)) && all(c("last_cell_date", "last_engine_date") %in% names(fromJSON(file.path(R$ME$dir, "rf_engine_diag.json"), simplifyVector = FALSE)$base_alignment[[1]])),
    "C7 진단에는 끝 날짜가 있고 원장 요약에는 없다(τ_D 뒤 날짜를 원장에 싣지 않는다)")
unlink(TMP, recursive = TRUE)
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
