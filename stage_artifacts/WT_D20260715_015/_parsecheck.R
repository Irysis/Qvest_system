# parse-check — 편집된 rawdata_sanitize.R 구문 검증 + 함수 추출 검증 (config/calendar 미로드)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
f <- file.path(QM, "02_Infrastructure/data/rawdata_sanitize.R")
ok <- tryCatch({ parse(f); TRUE }, error = function(e) { cat("PARSE FAIL:", conditionMessage(e), "\n"); FALSE })
cat(sprintf("parse(rawdata_sanitize.R) = %s\n", ok))
# 함수 추출(firewall+tripwire) 안전 eval — verify_r46가 쓰는 방식과 동일
suppressWarnings(suppressMessages(library(data.table)))
txt <- readLines(f, warn = FALSE)
b0 <- grep("^ret_sanity_firewall <- function", txt)
b1 <- grep("^sanitize_rawdata <- function", txt)
eval(parse(text = paste(txt[b0:(b1[1]-1)], collapse = "\n")), envir = globalenv())
cat(sprintf("exists(ret_sanity_firewall)=%s · exists(close_continuity_tripwire)=%s\n",
            exists("ret_sanity_firewall"), exists("close_continuity_tripwire")))
# 마이크로 유닛테스트: 합성 date-gap 케이스로 P3 restore 동작 확인
dt <- data.table(
  Ticker = c("T1","T1","T1","T2","T2","T3","T3"),
  Date   = as.Date(c("2026-04-27","2026-04-28","2026-07-02",   # T1: 64일 hole, stored 물리타당
                     "2026-01-05","2026-01-06",                 # T2: 정상 연속
                     "2026-04-29","2026-07-02")),               # T3: hole, stored도 무효(분할)
  Close  = c(1000, 1010, 6000, 5000, 5050, 100, 500),
  Ret    = c(0.00, 0.01, 0.0293, 0.00, 0.01, 0.00, 3.00),       # T1 stored=+2.9%(타당) / T3 stored=+300%(무효)
  Ret_stored = c(0.00, 0.01, 0.0293, 0.00, 0.01, 0.00, 3.00),
  K200 = c(FALSE,FALSE,FALSE, TRUE,TRUE, FALSE,FALSE),
  KQ150 = FALSE)
setorder(dt, Ticker, Date)
dt[, prevClose := shift(Close), by = Ticker]
dt[, gapdays := as.integer(Date - shift(Date)), by = Ticker]
dt[, Ret := Close/prevClose - 1]   # recompute (T1 07-02 = 6000/1010-1 = +494%; T3 = 500/100-1=+400%)
fw <- ret_sanity_firewall(dt)
cat("\n[unit] firewall counts:\n"); print(fw$counts)
cat("[unit] isolation:\n"); print(fw$isolation[, .(Ticker, Date, Ret=round(Ret,3), Ret_stored=round(Ret_stored,3), gapdays, action, cause)])
# 기대: T1 07-02 = RESTORE(stored +2.9% 타당) · T3 07-02 = HARD(stored +300% 무효) · T2 무영향
stopifnot(fw$counts$restore == 1L, fw$counts$hard == 1L)
r_idx <- which(fw$mask_restore); h_idx <- which(fw$mask_hard)
cat(sprintf("[unit] restore row = %s @ %s (stored=%.4f) · hard row = %s @ %s\n",
            dt$Ticker[r_idx], dt$Date[r_idx], dt$Ret_stored[r_idx],
            dt$Ticker[h_idx], dt$Date[h_idx]))
stopifnot(dt$Ticker[r_idx] == "T1", dt$Ticker[h_idx] == "T3")
# tripwire 유닛
tw <- close_continuity_tripwire(dt)
cat("\n[unit] tripwire counts:\n"); print(tw$counts)
stopifnot(tw$counts$total_holes == 2L)   # T1 + T3 hole
cat("\n[unit] ALL micro-tests PASS\n")
