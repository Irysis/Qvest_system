# test_c11_monthly_fdb.R — PIT C11 수리 1단계 S1(월간 Factor DB) 상설 검사 (2026-09-24 신설)
#
# 지키는 것 (판정서 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md):
#   V-08  factor_db_builder.R 의 VIX 결합 = 가용일 결합(S0 fred_asof_join · decision_close — 미국 날짜 < 한국 날짜)
#         + 결합 자기검증 + compute_defense.R D32 는 c11_avail 표지 없는 VIX 열을 거부(fail-closed)
#   V-01  MA01·MA02 퇴역(decision_register PIT-C11-MA0102) — compute_regime 산출 0 · registry lifecycle retired
#   V-13  compute_regime.R 공통 −1일 필터(:75-77) → 계열별 가용일 필터 · RE14·MA07 날짜 기준 12개월 변화
#         (PIT-C11-CONVENTIONS ③ — CPIAUCSL 2025-10 관측 부재)
#   레지스트리 선언 정정(D32 known_discrepancy · RE_VIX_z · ⑤-8)
#
# ★양방향. 양성 대조만으로는 부족하다 — 구판 결합·자기검증 삭제·표지 검사 삭제·공통 필터 복귀·행 기준 shift·
#   MA01 부활·레지스트리 복귀를 **주입했을 때 빨개지는가**를 함께 잰다(E절). 주입이 초록이면 검사가 죽은 것이다
#   (pit.md: 양성 대조 없는 계기는 방어선으로 세지 않는다).
#
# 축: A 빌더 VIX(합성) · B 실데이터 VIX·D32(읽기 전용) · C compute_regime(실데이터 202608·합성) · D 레지스트리 · E 돌연변이
# 쓰기: tempdir() 만. 운영 .cache 는 읽기만(mmap=FALSE) — 원장·로그·레지스트리 쓰기 0.
# 코드 루트 = 이 파일의 3단 위(워크트리·섀도 안전) · 데이터 루트 = QM_ROOT(없으면 코드 루트).
# 실행: Rscript 08_Tests/factor_db/test_c11_monthly_fdb.R   (R_ENVIRON_USER=<빈 파일> 권장 · 약 1~2분)

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(arrow) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ROOT))
if (!nzchar(DATA_ROOT)) DATA_ROOT <- ROOT
FDB_DIR   <- file.path(ROOT, "02_Infrastructure/factor_db")
BUILDER   <- file.path(FDB_DIR, "factor_db_builder.R")
DEFENSE   <- file.path(FDB_DIR, "compute_defense.R")
REGIME    <- file.path(FDB_DIR, "compute_regime.R")
REGISTRY  <- file.path(FDB_DIR, "factor_registry.json")
GUARD     <- file.path(FDB_DIR, "emission_guard.R")
HELPER    <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
RULES     <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
CACHE     <- file.path(DATA_ROOT, ".cache")
MACRO_P   <- file.path(CACHE, "macro_fred.parquet")
CAL_P     <- file.path(CACHE, "trading_calendar.parquet")
RAW_P     <- file.path(CACHE, "RAWDATA.parquet")
SIG       <- as.Date("2026-08-31")      # 판정서 V-08 실례 달(202608)

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
skip <- function(axis, reason, missing) {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  SKIP  %s — %s [%s]\n", axis, reason, missing))
}
quiet <- function(expr) { r <- NULL; invisible(capture.output(r <- suppressWarnings(expr))); r }
TD <- file.path(tempdir(), paste0("c11_s1_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
CACHE_DIR <- CACHE   # compute_regime 이 exists("CACHE_DIR") 로 데이터 루트를 잡는다(빌더 세션과 같은 규약)

cat(sprintf("=== 전제 (코드 루트 %s · 데이터 루트 %s) ===\n", ROOT, DATA_ROOT))
for (p in c(BUILDER, DEFENSE, REGIME, REGISTRY, GUARD, HELPER, RULES)) chk(paste("존재", basename(p)), file.exists(p), p)
FA <- new.env(parent = globalenv()); invisible(quiet(source(HELPER, local = FA)))

# ── 빌더에서 C11 정의만 격리 적재(설정·전체 모듈 적재 없이 — test_fdb_state_gate 와 같은 방식) ───────
B_NEED <- c(".fdb_c11_env", ".fdb_vix_asof_join", ".fdb_attach_vix")
load_builder_defs <- function(lines) {
  env <- new.env(parent = globalenv())
  ex <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  got <- character(0)
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) &&
                    as.character(e[[2]]) %in% B_NEED) { eval(e, env); got <- c(got, as.character(e[[2]])) }
  env$.self_dir <- FDB_DIR; env$.fdb_env <- new.env(parent = emptyenv()); env$CACHE_DIR <- CACHE
  env$.GOT <- got
  env
}
B_SRC <- sub("\r$", "", readLines(BUILDER, encoding = "UTF-8", warn = FALSE))
BE <- load_builder_defs(B_SRC)
chk("A0 빌더 C11 정의 3종 적재", setequal(BE$.GOT, B_NEED), paste(setdiff(B_NEED, BE$.GOT), collapse = ","))

# ── 합성 픽스처: 한국 평일 달력(한국 휴일 1일) · 미국 VIX(미국 휴일 1일) ──────────────────────────────
wk <- function(a, b) { d <- seq(as.Date(a), as.Date(b), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] }
SYN_CAL <- setdiff(wk("2026-07-01", "2026-09-30"), as.Date("2026-09-25"))  # 한국 휴일(합성)
SYN_CAL <- as.Date(SYN_CAL, origin = "1970-01-01")
SYN_US  <- setdiff(wk("2026-07-01", "2026-09-30"), as.Date("2026-09-07"))  # 미국 Labor Day
SYN_US  <- as.Date(SYN_US, origin = "1970-01-01")
SYN_VIX <- data.table(Series_ID = "VIXCLS", Date = SYN_US, Value = 10 + seq_along(SYN_US) / 100)
exp_pit <- function(kd, us) {         # 독립 계산: 한국 거래일 d 의 결정형 가용값 = max(미국 날짜 < d)
  u <- data.table(UD = as.Date(us$Date), V = us$Value, key = "UD")
  q <- as.Date(kd) - 1L
  u[J(q), roll = TRUE]$V
}
exp_same <- function(kd, us) {        # 구판(같은 날짜) 결합 — 민감도 대조용
  u <- data.table(UD = as.Date(us$Date), V = us$Value, key = "UD")
  q <- as.Date(kd)
  u[J(q), roll = TRUE]$V
}
sameday <- function(a, b) identical(as.character(a), as.character(b))

check_attach <- function(E, rd, macro_path, cal, expect_vals) {
  r <- quiet(E$.fdb_attach_vix(copy(rd), macro_path, fa = FA, kr_calendar = cal))
  v <- r$RAWDATA$VIX
  list(ok = !is.null(v) && isTRUE(all.equal(v, expect_vals, check.attributes = FALSE)) &&
         identical(r$status$vix, "ok") && grepl("^c11_avail:", attr(v, "c11_avail") %||% ""),
       r = r)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
# 절 보호 — 한 절이 죽어도 나머지 절과 요약 JSON 은 나온다(크래시 = 그 절 FAIL 1건 · 조용한 통과 아님)
run_section <- function(tag, expr) tryCatch(expr, error = function(e)
  chk(sprintf("%s절 실행(크래시)", tag), FALSE, conditionMessage(e)))
REAL <- all(file.exists(c(MACRO_P, CAL_P, RAW_P)))

cat("=== A. 빌더 VIX 결합 — 합성 양성 대조 · fail-closed · 자기검증 ===\n")
run_section("A", {
kd_syn <- SYN_CAL[SYN_CAL >= as.Date("2026-08-03")]
j <- quiet(BE$.fdb_vix_asof_join(kd_syn, SYN_VIX, fa = FA, kr_calendar = SYN_CAL))
chk("A1 결합값 = max(미국 날짜 < 한국 날짜)(독립 계산)", isTRUE(all.equal(j$value, exp_pit(kd_syn, SYN_VIX))))
chk("A2 모든 행 obs_date < kr_date", all(j$obs_date < j$kr_date))
mon <- as.Date("2026-08-31")
chk("A3 한국 월요일 ← 미국 직전 금요일", sameday(j[kr_date == mon]$obs_date, "2026-08-28"))
chk("A4 미국 휴일(09-07) 다음 한국 날짜 ← 미국 09-04", sameday(j[kr_date == as.Date("2026-09-08")]$obs_date, "2026-09-04"))
chk("A5 regime_key 속성", grepl("^c11_avail:", attr(j, "c11_key") %||% ""))
RD_SYN <- data.table(Date = rep(kd_syn, each = 2L), Ticker = rep(c("A", "B"), length(kd_syn)))
MP_SYN <- file.path(TD, "macro_syn.parquet")
write_parquet(rbind(SYN_VIX, data.table(Series_ID = "DGS10", Date = SYN_US, Value = 4)), MP_SYN)
ca <- check_attach(BE, RD_SYN, MP_SYN, SYN_CAL, exp_pit(RD_SYN$Date, SYN_VIX))
chk("A6 .fdb_attach_vix: 값·status ok·c11_avail 표지 · 행수 보존", ca$ok && nrow(ca$r$RAWDATA) == nrow(RD_SYN))
rd_old <- copy(RD_SYN)[, VIX := 99]      # 출처 미상 VIX 열(구판 같은 날짜판 가정)
ca2 <- check_attach(BE, rd_old, MP_SYN, SYN_CAL, exp_pit(RD_SYN$Date, SYN_VIX))
chk("A7 기존 VIX 열은 폐기 후 가용일 결합으로 재생성", ca2$ok)
MP_DUP <- file.path(TD, "macro_dup.parquet")
write_parquet(rbind(SYN_VIX, SYN_VIX[5][, Value := 77]), MP_DUP)
r_dup <- quiet(BE$.fdb_attach_vix(copy(RD_SYN), MP_DUP, fa = FA, kr_calendar = SYN_CAL))
chk("A8 같은 관측일 중복 → 결합 거부 · VIX 열 없음(fail-closed)",
    !("VIX" %in% names(r_dup$RAWDATA)) && grepl("^failed", r_dup$status$vix))
MP_NOV <- file.path(TD, "macro_novix.parquet")
write_parquet(data.table(Series_ID = "DGS10", Date = SYN_US, Value = 4), MP_NOV)
r_nov <- quiet(BE$.fdb_attach_vix(copy(RD_SYN), MP_NOV, fa = FA, kr_calendar = SYN_CAL))
chk("A9 VIXCLS 원천 없음 → VIX 열 없음", !("VIX" %in% names(r_nov$RAWDATA)) && identical(r_nov$status$vix, "no_source"))
# 자기검증 양성 대조: 같은 날짜 결합을 돌려주는 위조 도우미 → stop 이어야 한다
forge_fa <- function() {
  F2 <- new.env(parent = globalenv())
  for (nm in ls(FA, all.names = TRUE)) assign(nm, get(nm, envir = FA), envir = F2)
  F2$fred_asof_join <- function(kr_dates, series_dt, series_id, mode, kr_calendar = NULL, ...) {
    jj <- FA$fred_asof_join(kr_dates, series_dt, series_id, mode = mode, kr_calendar = kr_calendar)
    u <- data.table(Date = as.Date(series_dt$Date), key = "Date"); u[, O := Date]
    jj[, obs_date := u[J(jj$kr_date), roll = TRUE]$O]    # 같은 날짜(미국 d → 한국 d) 결합으로 바꿔치기
    jj
  }
  F2
}
self_check_stops <- function(E) {
  e <- tryCatch({ quiet(E$.fdb_vix_asof_join(kd_syn, SYN_VIX, fa = forge_fa(), kr_calendar = SYN_CAL)); NULL },
                error = function(e) conditionMessage(e))
  !is.null(e) && grepl("자기검증", e)
}
chk("A10 자기검증 — 같은 날짜 결합(위조 도우미) 주입 → stop", self_check_stops(BE))

})
cat("=== B. 실데이터(읽기 전용) — V-08 실값 · 전 이력 · D32 독립 재계산 · 표지 거부 ===\n")
run_section("B", {
if (!REAL) {
  skip("B·C 실데이터", "운영 .cache 부재(워크트리)", paste(c(MACRO_P, CAL_P, RAW_P)[!file.exists(c(MACRO_P, CAL_P, RAW_P))], collapse = ";"))
} else {
  MACRO <- as.data.table(read_parquet(MACRO_P, mmap = FALSE)); MACRO[, Date := as.Date(Date)]
  VIX_US <- MACRO[Series_ID == "VIXCLS" & !is.na(Value), .(Date, Value)]
  CAL <- FA$fred_kr_calendar(CAL_P)
  RD_DATES <- sort(unique(as.Date(read_parquet(RAW_P, col_select = "Date", mmap = FALSE)$Date)))
  KD <- RD_DATES[RD_DATES >= as.Date("2005-01-01")]
  real_attach <- function(E) quiet(E$.fdb_attach_vix(data.table(Date = KD, Ticker = "X"), MACRO_P, fa = FA))
  real_ok <- function(r) {
    v <- r$RAWDATA$VIX; d <- r$RAWDATA$Date
    if (is.null(v)) return(list(v0831 = FALSE, v0901 = FALSE, hist = FALSE, n_bad = NA))
    ex <- exp_pit(d, VIX_US)
    list(v0831 = isTRUE(all.equal(v[d == SIG], 14.43)), v0901 = isTRUE(all.equal(v[d == as.Date("2026-09-01")], 14.92)),
         hist = isTRUE(all.equal(v, ex, check.attributes = FALSE)), n_bad = sum(abs(v - ex) > 1e-12, na.rm = TRUE) + sum(is.na(v) != is.na(ex)))
  }
  RA <- real_attach(BE); ro <- real_ok(RA)
  chk("B1 한국 2026-08-31 행 VIX = 14.43(미국 08-28 · 판정서 V-08 PIT 값)", ro$v0831)
  chk("B2 한국 2026-09-01 행 VIX = 14.92(미국 08-31은 한국 09-01부터)", ro$v0901)
  chk(sprintf("B3 2005~ 전 이력 %d일 = 독립 계산(max 미국 날짜 < 한국 날짜) · 불일치 %s", length(KD), ro$n_bad), ro$hist)
  same_day <- exp_same(KD, VIX_US)
  chk("B4 민감도 — 같은 날짜 판과는 다르다(검사가 두 판을 가른다)", sum(abs(same_day - exp_pit(KD, VIX_US)) > 1e-9, na.rm = TRUE) > 1000L)
  chk("B5 status ok · regime_key = 규칙 파일 메타", identical(RA$status$vix, "ok") &&
        identical(RA$status$regime_key, FA$fred_avail_rules_meta()$regime_key))

  # D32 — 실제 종목 부분집합으로 compute_defense 구동, 독립 회귀와 대조
  SIG_TK <- sort(unique(as.data.table(read_parquet(RAW_P, col_select = c("Date", "Ticker", "Ret"), mmap = FALSE))[
    Date == SIG & !is.na(Ret)]$Ticker))
  TK <- SIG_TK[unique(round(seq(1, length(SIG_TK), length.out = 24)))]
  RD <- as.data.table(dplyr::collect(dplyr::filter(arrow::open_dataset(RAW_P), Ticker %in% TK,
                                                   Date >= !!(SIG - 420L), Date <= !!SIG)))
  RD[, Date := as.Date(Date)]
  setorder(RD, Date, Ticker)
  RDV <- quiet(BE$.fdb_attach_vix(copy(RD), MACRO_P, fa = FA))$RAWDATA
  run_defense <- function(src, rd) {
    DE <- new.env(parent = globalenv()); quiet(source(src, local = DE))
    out <- quiet(DE$compute_defense(copy(rd), SIG))
    out
  }
  indep_d32 <- function(rd, vcol) {    # compute_defense D32 와 같은 회귀를, 독립으로 만든 VIX 열로
    x <- rd[Date <= SIG & Date >= SIG - 365]
    setkey(x, Ticker, Date)
    x[, .(b = {
      s <- .SD[!is.na(Ret) & !is.na(get(vcol))]
      if (nrow(s) < 120L) NA_real_ else {
        vc <- diff(s[[vcol]]) / head(s[[vcol]], -1); rr <- s$Ret[-1]
        ok <- !is.na(vc) & !is.na(rr) & is.finite(vc)
        if (sum(ok) < 60L) NA_real_ else lm.fit(cbind(1, vc[ok]), rr[ok])$coefficients[2]
      }
    }), by = Ticker][!is.na(b)]
  }
  RD_IND <- copy(RD)
  RD_IND[, VIX_PIT := exp_pit(RD_IND$Date, VIX_US)]
  RD_IND[, VIX_SAME := exp_same(RD_IND$Date, VIX_US)]
  d32_ok <- function(out) {
    got <- out[Factor_Name == "D32_Beta_VIX", .(Ticker, g = Raw_Value)]
    ip <- merge(got, indep_d32(RD_IND, "VIX_PIT"), by = "Ticker")
    nrow(got) > 0L && nrow(ip) == nrow(got) && max(abs(ip$g - ip$b)) < 1e-10
  }
  OUT_D <- run_defense(DEFENSE, RDV)
  chk(sprintf("B6 D32(%d종) = 가용일 VIX 로 한 독립 회귀(허용 1e-10)", nrow(OUT_D[Factor_Name == "D32_Beta_VIX"])), d32_ok(OUT_D))
  ss <- merge(OUT_D[Factor_Name == "D32_Beta_VIX", .(Ticker, g = Raw_Value)], indep_d32(RD_IND, "VIX_SAME"), by = "Ticker")
  chk("B7 민감도 — 같은 날짜 VIX 회귀와는 다르다", nrow(ss) > 0L && max(abs(ss$g - ss$b)) > 1e-6)
  RD_NOTAG <- copy(RDV); setattr(RD_NOTAG[["VIX"]], "c11_avail", NULL)
  d32_rejects <- function(src) {
    o <- run_defense(src, RD_NOTAG)
    nrow(o[Factor_Name == "D32_Beta_VIX"]) == 0L && nrow(o[Factor_Name == "D02_Beta"]) > 0L
  }
  chk("B8 표지 없는 VIX 열 → D32 거부(다른 방어 팩터는 산출)", d32_rejects(DEFENSE))
}

})
cat("=== C. compute_regime — 계열별 가용일 필터 · 날짜 기준 YoY · MA01/MA02 퇴역 ===\n")
run_section("C", {
load_regime <- function(src) { CE <- new.env(parent = globalenv()); quiet(source(src, local = CE)); CE }
CE <- load_regime(REGIME)
# C0 합성 결측월: 2025-10 부재 계열의 날짜 기준 12개월 변화
ms <- seq(as.Date("2024-01-01"), as.Date("2026-12-01"), by = "month"); ms <- ms[ms != as.Date("2025-10-01")]
vv <- 100 * cumprod(rep(1.003, length(ms)))
y <- CE$.cr_yoy_by_date(ms, vv)
iv <- function(d) vv[ms == as.Date(d)]
chk("C0a 2026-10 YoY = NA(12개월 전 2025-10 관측 없음)", is.na(y[ms == as.Date("2026-10-01")]))
chk("C0b 2026-09 YoY = V(2026-09)/V(2025-09)−1(행 shift 면 13개월)",
    isTRUE(all.equal(y[ms == as.Date("2026-09-01")], iv("2026-09-01") / iv("2025-09-01") - 1)))
chk("C0c 결측 뒤 2025-11 YoY = V(2025-11)/V(2024-11)−1",
    isTRUE(all.equal(y[ms == as.Date("2025-11-01")], iv("2025-11-01") / iv("2024-11-01") - 1)))
chk("C0d 달력월 중복 입력은 거부", inherits(tryCatch(CE$.cr_yoy_by_date(c(ms[1], ms[1]), c(1, 2)), error = function(e) e), "error"))

regime_expect <- NULL
if (REAL) {
  last_avail <- function(sid) {       # 결정 SIG 에 가용한 최신 관측(도우미 = S0 규칙 정본)
    s <- MACRO[Series_ID == sid & !is.na(Value)]
    a <- FA$fred_avail_date(sid, s$Date, kr_calendar = CAL)
    s[!is.na(a) & a <= SIG][Date == max(Date)]
  }
  yoy12 <- function(sid, d) { s <- MACRO[Series_ID == sid]; s[Date == d]$Value / s[Date == seq(d, by = "-12 months", length.out = 2)[2]]$Value - 1 }
  L_cpi <- last_avail("CPIAUCSL")$Date; L_ip <- last_avail("INDPRO")$Date; L_hy <- last_avail("BAMLH0A0HYM2")$Date
  hy <- MACRO[Series_ID == "BAMLH0A0HYM2" & Date <= L_hy]
  regime_expect <- list(
    RE14 = -yoy12("CPIAUCSL", L_cpi),
    MA07 = 0.5 * yoy12("INDPRO", L_ip) + 0.5 * (-yoy12("CPIAUCSL", L_cpi)),
    RE13 = -mean(hy$Value <= hy[Date == L_hy]$Value))
  chk("C1 결정 2026-08-31 가용 최신 CPI = 2026-07(8월분은 09-18~ 도착)", sameday(L_cpi, "2026-07-01"))
  chk("C2 결정 2026-08-31 가용 최신 INDPRO = 2026-07", sameday(L_ip, "2026-07-01"))
  regime_ok <- function(out) {
    g <- function(f) out[Factor_Name == f]$Raw_Value[1]
    list(ma_absent = nrow(out[Factor_Name %in% c("MA01_GDP_Sensitivity", "MA02_CPI_Sensitivity")]) == 0L,
         re14 = isTRUE(all.equal(g("RE14_Inflation_YoY"), regime_expect$RE14, tolerance = 1e-12)),
         ma07 = isTRUE(all.equal(g("MA07_BusinessCycle_Composite"), regime_expect$MA07, tolerance = 1e-12)),
         re13 = isTRUE(all.equal(g("RE13_Credit_Spread_Pctile"), regime_expect$RE13, tolerance = 1e-12)),
         re10 = !is.null(g("RE10_VIX_Pctile")) && !is.na(g("RE10_VIX_Pctile")))
  }
  OUT_R <- quiet(CE$compute_regime(copy(RD), SIG))
  rk <- regime_ok(OUT_R)
  chk("C3 MA01·MA02 산출 0(퇴역)", rk$ma_absent)
  chk(sprintf("C4 RE14 = −[CPI(%s)/CPI(12개월 전)−1] 날짜 기준 · 가용분만", L_cpi), rk$re14,
      sprintf("got %s want %s", OUT_R[Factor_Name == "RE14_Inflation_YoY"]$Raw_Value[1], regime_expect$RE14))
  chk("C5 RE14 ≠ 저장 오염값 −0.0371296(판정서 V-13 · 신호월 8월분)",
      abs(OUT_R[Factor_Name == "RE14_Inflation_YoY"]$Raw_Value[1] - (-0.0371296)) > 1e-5)
  chk("C6 MA07 = 0.5·INDPRO YoY − 0.5·CPI YoY(가용분·날짜 기준)", rk$ma07)
  chk(sprintf("C7 RE13 = HY 분위(가용 최신 %s · ICE 한국 d+2)", L_hy), rk$re13)
  chk("C8 VIX 계 팩터(RE10) 산출 유지", rk$re10)
  # as-of 이력 자체: 모든 행의 가용일 ≤ SIG · DEXKOUS 제외 · 가짜 계열 fail-closed
  dt_all <- copy(MACRO)[, Series := fifelse(!is.na(Series_ID) & nzchar(Series_ID), Series_ID, Series)]
  dt_all <- rbind(dt_all, data.table(Date = SIG - 40, Value = 1, Series = "ZZZ_FAKE", Series_ID = "ZZZ_FAKE",
                                     Frequency = "d"), fill = TRUE)
  CE2 <- load_regime(REGIME)
  AS <- quiet(CE2$.cr_c11_asof(dt_all, SIG, MACRO_P, extra_kr_dates = RD$Date))
  av_ok <- all(vapply(split(AS, AS$Series), function(s)
    all(FA$fred_avail_date(s$Series[1], s$Date, kr_calendar = CAL) <= SIG), logical(1)))
  chk("C9 as-of 이력 전 행 가용일 ≤ 결정일(도우미 재계산)", av_ok)
  chk("C10 금지 계열 DEXKOUS · 규칙 없는 계열 제외(fail-closed)",
      !any(AS$Series %in% c("DEXKOUS", "ZZZ_FAKE")) && any(grepl("^ZZZ_FAKE", CE2$.CR_C11$dropped)) &&
        any(grepl("^DEXKOUS", CE2$.CR_C11$dropped)))
  chk("C11 VIXCLS 가용 최신 = 미국 08-28", sameday(max(AS[Series == "VIXCLS"]$Date), "2026-08-28"))
  # 도우미 부재 → MACRO 없음(해외 계열 팩터 0 · 침묵 금지 로그)
  iso <- file.path(TD, "iso_tree/02_Infrastructure/factor_db"); dir.create(iso, recursive = TRUE, showWarnings = FALSE)
  file.copy(REGIME, iso, overwrite = TRUE)
  # r1: compute_regime 의 도우미 후보에 CLAUDE_PROJECT_DIR(금칙 ④ CPD 먼저)가 들어갔다 — 격리는 두 env 모두 막아야 한다
  old_q <- Sys.getenv("QM_ROOT"); old_c <- Sys.getenv("CLAUDE_PROJECT_DIR", NA)
  Sys.setenv(QM_ROOT = file.path(TD, "nowhere"), CLAUDE_PROJECT_DIR = file.path(TD, "nowhere"))
  CE3 <- new.env(parent = globalenv()); quiet(source(file.path(iso, "compute_regime.R"), local = CE3))
  log3 <- capture.output(OUT3 <- suppressWarnings(CE3$compute_regime(copy(RD), SIG)))
  Sys.setenv(QM_ROOT = old_q); if (is.na(old_c)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = old_c)
  chk("C12 가용시점 층 부재 → 해외 계열 팩터 미산출 + '!!! MACRO 적재 실패' 로그(fail-closed)",
      !any(OUT3$Factor_Name %in% c("RE10_VIX_Pctile", "RE14_Inflation_YoY", "MA03_Rate_Sensitivity")) &&
        any(OUT3$Factor_Name == "RE01_Mkt_EWMA_21d") && any(grepl("MACRO 적재 실패", log3)))
}

})
cat("=== D. 레지스트리 선언 정정 ===\n")
run_section("D", {
reg_ok <- function(path) {
  R <- fromJSON(path, simplifyVector = FALSE)
  st <- function(f) R[[f]]$lifecycle$status %||% ""
  GE <- new.env(parent = globalenv()); quiet(source(GUARD, local = GE))
  act <- GE$emission_registry_meta(path)[status == "active", Factor_Name]
  list(retired = identical(st("MA01_GDP_Sensitivity"), "retired") && identical(st("MA02_CPI_Sensitivity"), "retired") &&
         all(grepl("PIT-C11-MA0102", c(R$MA01_GDP_Sensitivity$lifecycle$retirement_decision %||% "",
                                       R$MA02_CPI_Sensitivity$lifecycle$retirement_decision %||% ""))),
       not_active = !any(c("MA01_GDP_Sensitivity", "MA02_CPI_Sensitivity") %in% act) && "D32_Beta_VIX" %in% act,
       d32 = grepl("factor_db_builder.R", R$D32_Beta_VIX$availability$known_discrepancy %||% "") &&
         grepl("fred_asof_join", R$D32_Beta_VIX$availability$known_discrepancy %||% ""),
       vixz = grepl("V-10", R$RE_VIX_z$availability$known_discrepancy %||% "") && identical(R$RE_VIX_z$availability$rule, "-1d"),
       stale = sum(vapply(R, function(e) grepl("FRED sig_d-1. 선언(C11 publication lag) 대비 약한 강제",
                                               e$availability$known_discrepancy %||% "", fixed = TRUE), logical(1))))
}
rg <- reg_ok(REGISTRY)
chk("D1 MA01·MA02 lifecycle = retired + 결정 근거(PIT-C11-MA0102)", rg$retired)
chk("D2 emission_guard 기준 active 에서 MA01·MA02 제외(D32 는 active 유지)", rg$not_active)
chk("D3 D32 known_discrepancy = 빌더 경로·fred_asof_join(구 'compute_regime −1일' 서술 반증 반영)", rg$d32)
chk("D4 RE_VIX_z 선언 불일치 신고(V-10) · 규칙 문자열 = 도메인 계약 '-1d' 유지", rg$vixz)
chk("D5 compute_regime :75-77 '1일 근사' 낡은 서술 잔존 0", rg$stale == 0L, sprintf("잔존 %d", rg$stale))

})
cat("=== E. 위반 주입(돌연변이) — 전부 red 여야 한다 ===\n")
run_section("E", {
mutate <- function(lines, old, new) {
  i <- grep(old, lines, fixed = TRUE)
  if (length(i) != 1L) stop(sprintf("돌연변이 적용 실패(일치 %d줄): %s", length(i), old))
  lines[i] <- sub(old, new, lines[i], fixed = TRUE); lines
}
mut_file <- function(src, old, new, tag, tree = FALSE) {
  L <- sub("\r$", "", readLines(src, encoding = "UTF-8", warn = FALSE))
  M <- mutate(L, old, new)
  if (tree) {   # compute_regime 은 형제 data/ 에서 도우미를 찾는다 — 도우미·규칙을 함께 둔 미니 트리
    d <- file.path(TD, paste0("mt_", tag)); dir.create(file.path(d, "02_Infrastructure/factor_db"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(d, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
    file.copy(HELPER, file.path(d, "02_Infrastructure/data"), overwrite = TRUE)
    file.copy(RULES, file.path(d, "06_Registry"), overwrite = TRUE)
    p <- file.path(d, "02_Infrastructure/factor_db", basename(src))
  } else p <- file.path(TD, paste0(tag, "_", basename(src)))
  writeLines(M, p, useBytes = TRUE); p
}
red <- function(name, still_green) chk(paste(name, "→ red"), !isTRUE(still_green), "돌연변이가 살아남음 — 검사 무력")

# M1 구판 같은 날짜 roll 결합 복귀(빌더)
M1 <- load_builder_defs(mutate(B_SRC, "vix_filled <- data.table(Date = j$kr_date, VIX = j$value)",
  "vix_filled <- setkey(vix_raw[, .(Date, VIX = Value)], Date)[data.table(Date = sort(unique(RAWDATA$Date))), on = \"Date\", roll = TRUE]"))
red("M1 빌더 구판 같은 날짜 결합(합성 A6)", check_attach(M1, RD_SYN, MP_SYN, SYN_CAL, exp_pit(RD_SYN$Date, SYN_VIX))$ok)
if (REAL) { r1 <- real_ok(real_attach(M1)); red("M1' 빌더 구판 결합(실데이터 B1·B3)", r1$v0831 && r1$hist) }
# M2 자기검증 삭제(빌더)
M2 <- load_builder_defs(mutate(B_SRC, "if (nrow(bad) > 0L)", "if (FALSE)"))
red("M2 빌더 자기검증 삭제(A10)", self_check_stops(M2))
# M3 D32 표지 검사 삭제(compute_defense)
if (REAL) {
  p3 <- mut_file(DEFENSE, 'if (.vix_ok || "VKOSPI" %in% names(rd)) {', 'if ("VIX" %in% names(rd) || "VKOSPI" %in% names(rd)) {', "m3")
  red("M3 compute_defense 표지 검사 삭제(B8)", d32_rejects(p3))
}
if (REAL) {
  # M4 공통 −1일 필터 복귀(compute_regime)
  p4 <- mut_file(REGIME, ".cr_c11_asof(dt, sig_d, macro_path, extra_kr_dates = unique(rd$Date))", "dt[Date <= (sig_d - 1L)]", "m4", tree = TRUE)
  o4 <- quiet(load_regime(p4)$compute_regime(copy(RD), SIG)); k4 <- regime_ok(o4)
  red("M4 compute_regime 공통 −1일 필터 복귀(C4·C6·C7)", k4$re14 && k4$ma07 && k4$re13)
  # M5 RE14 행 기준 shift(12) 복귀
  p5 <- mut_file(REGIME, "cpi_dt[, cpi_yoy := .cr_yoy_by_date(Date, Value)]", "cpi_dt[, cpi_yoy := Value / shift(Value, 12) - 1]", "m5", tree = TRUE)
  o5 <- quiet(load_regime(p5)$compute_regime(copy(RD), SIG))
  red("M5 RE14 행 기준 shift(12) 복귀(C4)", regime_ok(o5)$re14)
  # M6 MA01 부활(구판 필터 동반 — 가용분만으로는 창 12관측을 못 채워 산출 자체가 불가하다)
  L6 <- sub("\r$", "", readLines(REGIME, encoding = "UTF-8", warn = FALSE))
  L6 <- mutate(L6, ".cr_c11_asof(dt, sig_d, macro_path, extra_kr_dates = unique(rd$Date))", "dt[Date <= (sig_d - 1L)]")
  L6 <- mutate(L6, "    # ---- MA03: Interest Rate Sensitivity (10Y Treasury) ----",
               "    ma01 <- .macro_beta(\"INDPRO\", \"MA01_GDP_Sensitivity\"); if (!is.null(ma01)) results[[\"MA01\"]] <- ma01")
  d6 <- file.path(TD, "mt_m6"); dir.create(file.path(d6, "02_Infrastructure/factor_db"), recursive = TRUE, showWarnings = FALSE)
  p6 <- file.path(d6, "02_Infrastructure/factor_db/compute_regime.R"); writeLines(L6, p6, useBytes = TRUE)
  o6 <- quiet(load_regime(p6)$compute_regime(copy(RD), SIG))
  red("M6 MA01 산출 부활(C3)", regime_ok(o6)$ma_absent)
}
# M7 레지스트리 MA01 active 복귀
R7 <- fromJSON(REGISTRY, simplifyVector = FALSE); R7$MA01_GDP_Sensitivity$lifecycle$status <- "active"
p7 <- file.path(TD, "reg_m7.json"); writeLines(toJSON(R7, auto_unbox = TRUE, null = "null", pretty = TRUE), p7, useBytes = TRUE)
k7 <- reg_ok(p7); red("M7 레지스트리 MA01 active 복귀(D1·D2)", k7$retired && k7$not_active)

})
unlink(TD, recursive = TRUE)
cat(sprintf("\n=== test_c11_monthly_fdb: %d PASS / %d FAIL / %d SKIP (code=%s · data=%s) ===\n",
            PASS, FAIL, length(SKIPS), ROOT, DATA_ROOT))
cat(toJSON(list(test = "c11_monthly_fdb", pass = PASS, fail = FAIL, total = PASS + FAIL,
                skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE), "\n", sep = "")
quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
