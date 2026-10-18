## =============================================================================
## engine_dryrun_test.R — 생성 엔진 파일 통째 리허설(합성 데이터 · CPU · 가짜 루트 · 12개월) — 실제 데이터 · 실제 _work · GPU 를 쓰지 않는다
##   가짜 루트 tests/_out/engine_dryrun/root/(표지 파일 02_Infrastructure/hooks/qvest_hook_router.py · 합성 .cache/{consensus/*.parquet,
##   fundamental_merged.parquet})를 만들고 CLAUDE_PROJECT_DIR = QM_ROOT = 가짜 루트 · QVEST_PY = venv · CUDA_VISIBLE_DEVICES = -1 로
##   engine_V1.R → engine_V2.R 사본을 각각 별도 Rscript 프로세스에서 sys.source 한다(파이썬 하위 프로세스 출력까지 로그 파일로).
##   사본은 생성 엔진과 바이트 동일하되 한 줄만 바꾼다: '.N_WORKERS_CAP <- 32L' → '2L'(CPU 워커 31개 × torch 적재 메모리 회피 ·
##   달별 결과는 처리 순서 · 워커 수와 무관 — 원본 rotate 주석). 엔진은 매 실행 양성 대조(10만 행)를 CPU 로 돈다.
##   단언: 두 실행 rc 0 · 로그 줄(R 검산 · 규칙 함수 검산 · σ · 양성 대조 · 규칙 · [DT qpred] · 패널 삭제) · V1 = 학습 12개월 · V2 = 캐시 12개월 ·
##         FACTORS(열 · 유한 점수 · V1 거부 ≈ 20% · V2 = q10) · PORTFOLIO 롱숏 Σ · 예측표(같은 파일 · 열 13 · s_hist · h_hist) · panel.parquet 삭제 ·
##         시작일 2005-01-31 신호 · 가짜 루트 밖 쓰기 없음(실제 _work 불변).
## 실행: Rscript tests/engine_dryrun_test.R      (수 분 · 끝나면 가짜 루트 삭제 · 로그 · 결과는 tests/_out/engine_dryrun/ 에 남긴다)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
REAL_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
DT_DIR <- file.path(REAL_ROOT, "04_Research/strategies/DT_2002_06975")
OUTD <- file.path(DT_DIR, "tests", "_out", "engine_dryrun")
FAKE <- file.path(OUTD, "root")
PY <- file.path(REAL_ROOT, ".venv_qvest_ml", "Scripts", "python.exe")

## ── 내부 모드: 엔진 사본 1개 실행 ──
if (length(args) >= 2L && args[1] == "--inner") {
  eng <- args[2]
  Sys.setenv(CLAUDE_PROJECT_DIR = FAKE, QM_ROOT = FAKE, QVEST_PY = PY, CUDA_VISIBLE_DEVICES = "-1")
  env <- new.env(parent = globalenv())
  env$RAWDATA <- as.data.table(read_parquet(file.path(FAKE, ".cache", "rawdata_synthetic.parquet"), mmap = FALSE))
  env$BM_DT <- NULL
  sys.source(eng, envir = env)
  saveRDS(list(FACTORS = env$FACTORS, PORTFOLIO = env$PORTFOLIO, QP = env$.DT_QP, panel = env$.panel_path, RD = env$.RD),
          file.path(OUTD, paste0(basename(eng), ".rds")))
  quit(status = 0L)
}

## ── 외부 모드: 합성 데이터 · 가짜 루트 · 두 엔진 실행 · 단언 ──
unlink(OUTD, recursive = TRUE)
dir.create(file.path(FAKE, "02_Infrastructure", "hooks"), recursive = TRUE, showWarnings = FALSE)
writeLines("# fake root marker for engine_dryrun_test.R (deleted after the test)", file.path(FAKE, "02_Infrastructure", "hooks", "qvest_hook_router.py"))
dir.create(file.path(FAKE, ".cache", "consensus"), recursive = TRUE, showWarnings = FALSE)
real_work <- file.path(DT_DIR, "_work")
real_before <- if (dir.exists(real_work)) sort(list.files(real_work, recursive = TRUE, all.files = TRUE)) else character(0)

set.seed(20261018)
days <- seq(as.Date("2000-06-01"), as.Date("2006-01-31"), by = "day"); days <- days[!(as.POSIXlt(days)$wday %in% c(0L, 6L))]
tks <- sprintf("A%06d", 1:60)
RAW <- CJ(Ticker = tks, Date = days)
RAW[, Close := 1000 * exp(cumsum(rnorm(.N, 2e-4, 0.02))), by = Ticker]
RAW[, Open := Close * exp(rnorm(.N, 0, 0.005))]
RAW[, Vol := round(runif(.N, 1e4, 1e6))]
RAW[, Size := Close * 1e7]
RAW[, K200 := TRUE]; RAW[, KQ150 := FALSE]
RAW <- RAW[!(Ticker == "A000059" & Date < as.Date("2003-01-02"))]                         # 늦은 상장
RAW <- RAW[!(Ticker == "A000060" & Date > as.Date("2005-06-30"))]                         # 상장 폐지
RAW[Ticker == "A000058" & Date >= as.Date("2005-03-01") & Date <= as.Date("2005-05-31"), K200 := FALSE]   # 멤버십 공백
RAW[Ticker %in% tks[51:57], `:=`(K200 = FALSE, KQ150 = TRUE)]                              # 코스닥 표식
write_parquet(RAW, file.path(FAKE, ".cache", "rawdata_synthetic.parquet"))
cd <- days[days >= as.Date("2001-01-02")]
OP <- CJ(Ticker = tks, Date = cd)[, op_profit_fy1 := 1e9 * exp(cumsum(rnorm(.N, 0, 0.01))), by = Ticker]
TP <- CJ(Ticker = tks, Date = cd)[, target_price := 1200 * exp(cumsum(rnorm(.N, 0, 0.01))), by = Ticker]
write_parquet(OP, file.path(FAKE, ".cache", "consensus", "op_profit_fy1.parquet"))
write_parquet(TP, file.path(FAKE, ".cache", "consensus", "target_price.parquet"))
items <- c("Revenue", "OperatingProfit", "PretaxIncome", "TaxExpense", "NetIncome", "OperatingCF", "Dividends", "DepAmort",
           "TotalAssets", "CurrentAssets", "CurrentLiab", "TotalEquity", "ShortTermBorr", "LongTermBorr")
FM <- CJ(Ticker = tks, FY = 1998:2005, Item = items)
FM[, Value := runif(.N, 1e8, 1e10)][Item == "Dividends", Value := -Value]
FM[, `:=`(Period = sprintf("%d12", FY), Source = "DART")]
XQ <- CJ(Ticker = tks[1:5], FY = 2004:2005, MM = c(3L, 6L, 9L, 12L), Item = c("Revenue", "OperatingProfit"))
XQ[, `:=`(Value = runif(.N, 1e8, 1e9), Period = sprintf("%d%02d", FY, MM), Source = "XLSX")]
write_parquet(rbind(FM[, .(Ticker, Period, Item, Value, Source)], XQ[, .(Ticker, Period, Item, Value, Source)]),
              file.path(FAKE, ".cache", "fundamental_merged.parquet"))

R <- list()
chk <- function(name, ok, detail = "") {
  R[[length(R) + 1L]] <<- list(name = name, ok = isTRUE(ok), detail = detail)
  cat(sprintf("[engine-dryrun] %-4s %s%s\n", if (isTRUE(ok)) "OK" else "FAIL", name, if (nzchar(detail)) paste0(" — ", detail) else ""))
}
mk_copy <- function(rule) {
  src <- file.path(DT_DIR, sprintf("engine_%s.R", rule)); dst <- file.path(OUTD, sprintf("engine_%s_dryrun.R", rule))
  x <- rawToChar(readBin(src, "raw", file.info(src)$size)); Encoding(x) <- "UTF-8"
  old <- ".N_WORKERS_CAP <- 32L "; n <- lengths(regmatches(x, gregexpr(old, x, fixed = TRUE)))
  if (n != 1L) stop("워커 상한 줄 치환 대상 ", n, "회")
  y <- sub(old, ".N_WORKERS_CAP <- 2L  ", x, fixed = TRUE)
  if (identical(x, y)) stop("워커 상한 치환 불성사")
  writeBin(charToRaw(y), dst); dst
}
run_inner <- function(rule) {
  eng <- mk_copy(rule); logf <- file.path(OUTD, sprintf("engine_%s.log", rule))
  t0 <- Sys.time()
  rc <- system2(file.path(R.home("bin"), "Rscript"), c(shQuote(file.path(DT_DIR, "tests", "engine_dryrun_test.R")), "--inner", shQuote(eng)),
                stdout = logf, stderr = logf)
  list(rc = as.integer(rc), log = readLines(logf, encoding = "UTF-8", warn = FALSE), secs = as.numeric(difftime(Sys.time(), t0, units = "secs")),
       out = if (file.exists(file.path(OUTD, paste0(basename(eng), ".rds")))) readRDS(file.path(OUTD, paste0(basename(eng), ".rds"))) else NULL)
}
has <- function(log, pat) any(grepl(pat, log, fixed = TRUE))

a <- run_inner("V1")
chk(sprintf("engine_V1 사본 실행 rc 0 (%.0fs)", a$secs), a$rc == 0L && !is.null(a$out), if (a$rc != 0L) paste(tail(a$log, 6), collapse = " | ") else "")
b <- run_inner("V2")
chk(sprintf("engine_V2 사본 실행 rc 0 (%.0fs)", b$secs), b$rc == 0L && !is.null(b$out), if (b$rc != 0L) paste(tail(b$log, 6), collapse = " | ") else "")
if (!is.null(a$out) && !is.null(b$out)) {
  for (z in list(list("V1", a), list("V2", b))) {
    rl <- z[[1]]; L <- z[[2]]$log
    chk(sprintf("%s 로그: 원본 R 검산 · 규칙 함수 검산 · σ · 양성 대조 · 규칙 · 예측표 · 패널 삭제", rl),
        has(L, "양성 대조 통과 — 순위 재척도") && has(L, "규칙 함수 검산 통과") && has(L, "σ(직전 252거래일") && has(L, "자기 이력 폭 h(직전 252거래일") &&
          has(L, "[dnn] positive control (heteroscedastic synthetic") && has(L, sprintf("규칙 %s:", rl)) && has(L, "[DT qpred] path=") &&
          has(L, "DNN(분위): 양성 대조") && has(L, "패널 작업본 삭제 완료"))
    chk(sprintf("%s 태그 [DT_2002_06975:%s] · 장치 cpu", rl, rl), has(L, sprintf("[DT_2002_06975:%s]", rl)) && has(L, "device cpu"))
    chk(sprintf("%s panel.parquet 삭제 · 작업본은 가짜 루트 안", rl), !file.exists(z[[2]]$out$panel) && startsWith(z[[2]]$out$RD, FAKE))
  }
  dn <- grep("^\\[dnn\\] done:", a$log, value = TRUE); dn2 <- grep("^\\[dnn\\] done:", b$log, value = TRUE)
  chk("V1 = 12개월 학습 · V2 = 12개월 캐시(분위 캐시는 규칙과 무관 — 7 엔진 공유)",
      length(dn) == 1L && grepl("over 12 months (trained 12, cache 0)", dn, fixed = TRUE) &&
        length(dn2) == 1L && grepl("over 12 months (trained 0, cache 12)", dn2, fixed = TRUE), paste(dn, "/", dn2))
  F1 <- a$out$FACTORS; F2 <- b$out$FACTORS
  chk("FACTORS 열 · 유한 점수 · 첫 신호 2005-01-31 · 12개월", identical(names(F1), c("Date", "Ticker", "Score")) && !anyNA(F1$Score) &&
        identical(min(F1$Date), as.Date("2005-01-31")) && uniqueN(F1$Date) == 12L && uniqueN(F2$Date) == 12L)
  share <- 1 - nrow(F1) / nrow(F2)
  chk(sprintf("V1 거부 몫 = %.3f(신호일별 ⌊0.2N⌋/N 기대 %.3f)", share,
              1 - sum(F2[, .N, by = Date][, N - floor(0.2 * N + 1e-9)]) / nrow(F2)),
      abs(share - (1 - sum(F2[, .N, by = Date][, N - floor(0.2 * N + 1e-9)]) / nrow(F2))) < 1e-12)
  q <- as.data.table(read_parquet(b$out$QP, mmap = FALSE))
  chk("V2 점수 = 예측표 q10 · V1 통과 종목 점수 = q50", isTRUE(all.equal(q[F2, on = .(Date, Ticker), q10], F2$Score, tolerance = 0)) &&
        isTRUE(all.equal(q[F1, on = .(Date, Ticker), q50], F1$Score, tolerance = 0)))
  chk(sprintf("두 엔진 같은 예측표 파일(규칙 무관) · 열 13 · 실현 라벨 없음 · h 유한 %.0f%%", 100 * mean(is.finite(q$h_hist))), identical(a$out$QP, b$out$QP) && ncol(q) == 13L && all(c("s_hist", "h_hist") %in% names(q)) && mean(is.finite(q$h_hist)) > 0.5 &&
        has(b$log, "기존 파일과 내용 일치(쓰기 생략)"), basename(b$out$QP))
  chk("V2 예측표 행 = FACTORS 행(V2 는 거부 없음)", nrow(q) == nrow(F2))
  P1 <- a$out$PORTFOLIO
  chk("PORTFOLIO(원본 5분위 롱숏 조립) 롱 Σ = 1 · 숏 Σ = −1", nrow(P1) > 0L &&
        isTRUE(all(P1[, abs(sum(Weight[Weight > 0]) - 1) < 1e-9 & abs(sum(Weight[Weight < 0]) + 1) < 1e-9, by = Date]$V1)))
}
real_after <- if (dir.exists(real_work)) sort(list.files(real_work, recursive = TRUE, all.files = TRUE)) else character(0)
chk("실제 DT _work 불변(가짜 루트 밖 쓰기 없음)", identical(real_before, real_after), sprintf("파일 %d → %d", length(real_before), length(real_after)))
ok <- all(vapply(R, function(z) z$ok, logical(1)))
writeLines(toJSON(list(ok = ok, n = length(R), n_ok = sum(vapply(R, function(z) z$ok, logical(1))), checks = R,
                       at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")), auto_unbox = TRUE, pretty = TRUE),
           file.path(DT_DIR, "tests", "_out", "engine_dryrun_results.json"))
## 가짜 루트(표지 파일 · 합성 캐시 · 작업본) 삭제 — OneDrive 가 빈 디렉터리 핸들을 잠깐 잡으면 rmdir 만 실패하므로 재시도하고, 판정은 '파일 0 · 표지 없음'
marker <- file.path(FAKE, "02_Infrastructure", "hooks", "qvest_hook_router.py")
for (i in 1:5) { unlink(FAKE, recursive = TRUE); if (!dir.exists(FAKE)) break; Sys.sleep(2) }
left <- if (dir.exists(FAKE)) length(list.files(FAKE, recursive = TRUE, all.files = TRUE)) else 0L
cat(sprintf("[engine-dryrun] %s — 단언 %d 중 통과 %d · 가짜 루트 삭제 %s\n", if (ok) "OK" else "FAIL", length(R),
            sum(vapply(R, function(z) z$ok, logical(1))),
            if (!dir.exists(FAKE)) "완료" else if (left == 0L && !file.exists(marker)) "파일 · 표지 삭제 완료(빈 디렉터리만 남음 — OneDrive 핸들)" else sprintf("실패(파일 %d개 남음)", left)))
if (file.exists(marker)) { cat("[engine-dryrun] 표지 파일이 남았다 — 수동 삭제 필요: ", marker, "\n"); quit(status = 1L) }
quit(status = if (ok) 0L else 1L)
