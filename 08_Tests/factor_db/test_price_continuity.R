#==============================================================================
# test_price_continuity.R — 팩터 빌더 연속 가격 배율 px_cont (2026-11-13 · 도훈 "1번은 다시 계산해주고")
#
# 무엇을 재나(합성 픽스처 · 운영 .cache 읽기/쓰기 0):
#   C1 배율 단위 — 정정 없으면 정확히 1(비트) · 배율 정정 자리에서 Close×px_cont 비율 = 1 + Ret · 차단 자리(Ret NA) = 평탄 ·
#      종목 독립 · 원래 행 순서 보존
#   C2 모듈 실구동 양성 대조 — 같은 가격 경로에 ×5 기준 단절(Ret 은 정정됨)을 심고:
#        px_cont 없음 → M05 · M06 · M17 · M20 · T07(PMA20) 이 기준 계열(단절 없음)과 다르다(결함 재현)
#        px_cont 있음 → 기준 계열과 같다(수리) · 단절 없는 종목은 px_cont 유무와 무관하게 비트 동일
#   C3 돌연변이 — compute_momentum.R 의 prices 를 구판(Close)으로 되돌린 사본은 C2 수리 판정이 빨개져야 한다
#   C4 배선 — factor_db_builder.R::.load_base_data 가 fdb_px_cont 를 부른다(AST)
#   C5 FF 요인 빌더 — 모멘텀 정렬의 월말 종가 비율이 연속 가격이면 Ret 연쇄 수익과 같다(구판 = ×5 어긋남)
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/factor_db/test_price_continuity.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
.t_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  cands <- character(0)
  if (length(f)) cands <- c(cands, normalizePath(file.path(dirname(f[1]), "..", ".."), mustWork = FALSE))
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/factor_db/price_continuity.R"))]
  if (!length(hit)) stop("project root 미발견")
  hit[1]
}
PROJ <- .t_root()
FDB <- file.path(PROJ, "02_Infrastructure/factor_db")
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
chk <- function(cond, n, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)
cat("=== price continuity (합성 픽스처) ===\n")
source(file.path(FDB, "price_continuity.R"))

# ── C1 배율 단위 ───────────────────────────────────────────────────────────────
d0 <- data.table(Ticker = rep(c("B", "A"), each = 6), Date = rep(as.Date("2026-03-25") + 0:5, 2),
                 Close = c(10, 11, 12, 13, 14, 15, 100, 102, 510, 515, 520, 1300))
d0[, Ret := Close / shift(Close) - 1, by = Ticker]
ord0 <- paste(d0$Ticker, d0$Date)
a0 <- fdb_px_cont(copy(d0)[Ticker == "B"])
chk(identical(a0$px_cont, rep(1, 6)), "c1_no_repair_exact_one", "정정 없으면 배율 = 정확히 1(비트)")
d1 <- copy(d0)
d1[Ticker == "A" & Date == as.Date("2026-03-27"), Ret := 510 / 102 / 5 - 1]   # ×5 배율 정정(가드 rescale)
d1[Ticker == "A" & Date == as.Date("2026-03-30"), Ret := NA_real_]             # 차단(가드 block) — 그날 1300/520 = ×2.5
a1 <- fdb_px_cont(copy(d1))
chk(identical(paste(a1$Ticker, a1$Date), ord0), "c1_row_order_kept", "원래 행 순서 보존")
dk <- copy(d1); setkey(dk, Date); ak <- fdb_px_cont(dk)
chk(identical(key(ak), "Date") && identical(paste(ak$Ticker, ak$Date), paste(dk$Ticker, dk$Date)), "c1_key_kept", "키(Date) · 키 순서 보존 — 빌더의 RAWDATA[.(d)] 조인이 산다")
A <- a1[Ticker == "A"]; cc <- A$Close * A$px_cont
chk(isTRUE(all.equal(cc[3] / cc[2], 1 + d1[Ticker == "A"]$Ret[3], tolerance = 1e-14)) && identical(A$px_cont[1:2], c(1, 1)),
    "c1_rescaled_seam_joined", sprintf("정정 자리 연속 비율 = 1 + Ret(%.5f) · 앞자리 배율 1", cc[3] / cc[2] - 1))
chk(isTRUE(all.equal(cc[6] / cc[5], 1, tolerance = 1e-14)), "c1_blocked_seam_flat", "차단 자리(Ret NA) = 평탄(하네스 NA→0 과 같은 뜻)")
chk(identical(a1[Ticker == "B"]$px_cont, rep(1, 6)), "c1_tickers_independent", "다른 종목 배율 무접촉")
inf <- attr(a1, "px_cont_info")
chk(inf$n_fixed == 1L && inf$n_blocked == 1L && inf$n_tickers == 1L, "c1_info_counts", sprintf("정정 %d · 차단 %d · 종목 %d", inf$n_fixed, inf$n_blocked, inf$n_tickers))

# ── C2 모듈 실구동 ─────────────────────────────────────────────────────────────
#   300거래일 · 종목 3(기준 REF · 단절 SEAM · 무단절 NORM). SEAM 은 REF 와 같은 수익 경로인데 250일째부터 가격 수준이 ×5(Ret 은 정정 값).
set.seed(7)
nd <- 300L; dates <- seq(as.Date("2025-01-02"), by = "day", length.out = 430L)
dates <- dates[!as.POSIXlt(dates)$wday %in% c(0L, 6L)][seq_len(nd)]
r <- rnorm(nd, 0.0004, 0.018); r[1] <- 0
px <- 1000 * cumprod(1 + r)
mk <- function(tk, close, ret) data.table(Date = dates, Ticker = tk, Close = close, Open = close * (1 + rnorm(nd, 0, 0.002)),
                                          High = close * 1.01, Low = close * 0.99, Vol = 1e5, Size = close * 1e6,
                                          Ret = ret, BM_Ret = r * 0.8, Sector = "S", Sector_Lv2 = "S2")
K <- 250L
seam_close <- px; seam_close[K:nd] <- px[K:nd] * 5
REF <- mk("REF", px, c(NA, px[-1] / px[-nd] - 1))
SEAMt <- mk("SEAM", seam_close, c(NA, px[-1] / px[-nd] - 1))       # 저장 Ret = 정정된 실수익(가드 처분 뒤와 같은 상태)
SEAMt[, Open := Open / px * seam_close]
NORM <- mk("NORM", px * 1.7, c(NA, px[-1] / px[-nd] - 1))
RAW0 <- rbind(REF, SEAMt, NORM)
RAW1 <- fdb_px_cont(copy(RAW0))
sig <- dates[nd]
load_mod <- function(path, fn) { e <- new.env(parent = globalenv()); sys.source(path, envir = e); get(fn, envir = e) }
cm <- load_mod(file.path(FDB, "compute_momentum.R"), "compute_momentum")
ct <- load_mod(file.path(FDB, "compute_technical.R"), "compute_technical")
pick <- function(res, tk, f) { v <- as.data.table(res)[Ticker == tk & Factor_Name == f, Raw_Value]; if (length(v)) v[1] else NA_real_ }
FM <- c("M05_Trended_Mom", "M06_High_52w", "M17_Low_52w", "M20_Keller_Mom")
m0 <- cm(RAW0[Date <= sig], sig); m1 <- cm(RAW1[Date <= sig], sig)
sigT <- dates[K + 9L]                       # 기술적(20일 창)은 이음매를 지나는 신호일로 잰다
t0 <- ct(RAW0[Date <= sigT], sigT); t1 <- ct(RAW1[Date <= sigT], sigT)   # 모듈 계약: 빌더가 Date <= 신호일로 잘라 준다
FT <- "T07_PMA20"
ref_m <- sapply(FM, function(f) pick(m1, "REF", f)); ref_t <- pick(t1, "REF", FT)
broken <- sapply(FM, function(f) abs(pick(m0, "SEAM", f) - ref_m[[f]]) > 1e-6)
fixed  <- sapply(FM, function(f) abs(pick(m1, "SEAM", f) - ref_m[[f]]) <= 1e-9 * max(1, abs(ref_m[[f]])))
chk(all(broken[c("M05_Trended_Mom", "M06_High_52w", "M17_Low_52w")]), "c2_defect_reproduced",
    sprintf("배율 없음 = 단절 종목 M05/M06/M17 이 기준과 다름(M06 %.3f vs %.3f)", pick(m0, "SEAM", "M06_High_52w"), ref_m[["M06_High_52w"]]))
chk(all(fixed), "c2_momentum_repaired", "배율 있음 = M05 · M06 · M17 · M20 이 기준 계열과 같다")
chk(abs(pick(t0, "SEAM", FT) - ref_t) > 1e-3 && abs(pick(t1, "SEAM", FT) - ref_t) <= 1e-9,
    "c2_technical_repaired", sprintf("T07(PMA20 · 이음매 9일 뒤) 배율 없음 %.4f vs 기준 %.4f → 배율 있음 = 기준", pick(t0, "SEAM", FT), ref_t))
same_norm <- all(sapply(FM, function(f) identical(pick(m0, "NORM", f), pick(m1, "NORM", f))))
chk(same_norm, "c2_untouched_ticker_bitwise", "단절 없는 종목은 배율 유무와 무관하게 비트 동일")

# ── C3 돌연변이 ────────────────────────────────────────────────────────────────
src <- readLines(file.path(FDB, "compute_momentum.R"), warn = FALSE, encoding = "UTF-8")
pat <- "prices <- if (.pm_ok) Close * px_cont else Close"
hits <- grep(pat, src, fixed = TRUE)
if (length(hits) != 2L) bad("c3_mutation_setup", sprintf("치환 대상 %d곳(2 이어야 함)", length(hits))) else {
  mut <- sub(pat, "prices <- Close", src, fixed = TRUE)
  mp <- tempfile(fileext = ".R"); writeLines(mut, mp, useBytes = TRUE)
  cmm <- load_mod(mp, "compute_momentum"); mm <- cmm(RAW1[Date <= sig], sig)
  still_broken <- abs(pick(mm, "SEAM", "M06_High_52w") - ref_m[["M06_High_52w"]]) > 1e-6
  chk(still_broken, "c3_mutation_reddens", "구판 prices(Close) 사본 = 배율이 있어도 M06 이 다시 틀린다(검사가 수리를 재고 있다)")
}

# ── C4 배선 ────────────────────────────────────────────────────────────────────
ex <- parse(file.path(FDB, "factor_db_builder.R"), encoding = "UTF-8"); found <- FALSE
for (x in ex) if (is.call(x) && length(x) >= 3 && identical(as.character(x[[1]]), "<-") && identical(as.character(x[[2]]), ".load_base_data"))
  found <- "fdb_px_cont" %in% all.names(x[[3]])
chk(found, "c4_builder_wiring", ".load_base_data 가 fdb_px_cont 를 부른다")

# ── C5 FF 요인 빌더 모멘텀 정렬(build_kr_factor_returns.R · krf_snap → .krf_prior) ─────────────────
#   월말 14개 · 한 종목 · 8번째 달부터 가격 수준 ×5(Ret 은 정정 값). 연속 가격이면 C[f−1]/C[f−12]−1 = Ret 연쇄 수익,
#   배율 열이 없으면(구판) ×5 만큼 어긋난다.
fe <- new.env(parent = globalenv()); sys.source(file.path(PROJ, "02_Infrastructure/data/build_kr_factor_returns.R"), envir = fe, keep.source = FALSE)
mo <- seq(as.Date("2025-02-01"), by = "month", length.out = 14L) - 1L; set.seed(11); rm_ <- c(0, rnorm(13, 0.01, 0.05))   # 월말 14개
pxm <- 100 * cumprod(1 + rm_); clm <- pxm; clm[8:14] <- pxm[8:14] * 5
RW <- data.table(Date = mo, Ticker = "X", Close = clm, Size = pxm * 1e9, Ret = c(NA, pxm[-1] / pxm[-14] - 1), member = TRUE)
ME <- data.table(ym = as.integer(format(mo, "%Y%m")), me_date = mo)
ym13 <- as.integer(format(mo[14], "%Y%m"))
mom_of <- function(R) { S <- fe$krf_snap(R, ME); X <- fe$.krf_prior(S, 1L, 11L); X[ym == ym13, mom] }
truth <- pxm[13] / pxm[2] - 1
m_new <- mom_of(fdb_px_cont(copy(RW))); m_old <- mom_of(copy(RW))
chk(isTRUE(all.equal(m_new, truth, tolerance = 1e-12)) && abs(m_old - truth) > 0.5,
    "c5_ff_momentum_continuous", sprintf("연속 가격 모멘텀 %.4f = Ret 연쇄 %.4f · 배율 없음(구판) %.4f", m_new, truth, m_old))

cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL))
cat(sprintf('{"test":"price_continuity","pass":%d,"fail":%d,"skipped":0,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
