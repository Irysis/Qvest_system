# test_daily_fdb_pit_c11.R — 일간 Factor DB PIT C11·C1 수리 검사 (2026-09-24 신설 · 서브시스템 S2_daily_fdb)
#
# 지키는 것: 02_Infrastructure/factor_db/factor_db_daily_phase6.R · phase7.R · phase9b.R 와 도우미 factor_db_daily_pit.R ·
#   factor_db_daily_rcpp.cpp(roll_expanding_tail_beta_cpp) 가 판정서(04_Research/01_reports/pit_c11_20260924/
#   PIT_C11_verdict_20260924.md) V-09·V-12·1-4 를 고친 상태로 남아 있는가.
#   - D32(V-09): 한국 d 행 VIX = 미국 날짜 < d 의 최신 관측(S0 가용시점 층 · decision_close)
#   - RE10·RE13(V-12·C1): 누적 백분위 + 가용일 결합 · RE11: 가용일 결합 · RE14: 날짜 기준 12개월 변화 + 가용일 결합
#   - D08(C1): 결정일까지 누적 꼬리베타 · RE04(phase9b · C1): 누적 백분위 플래그
#   - regime_daily_v2 스탬프 가드(V-10·V-11 의 일간 fdb 쪽 fail-closed)
#
# ★양방향(pit.md: 양성 대조 없는 계기는 방어선으로 세지 않는다).
#   양성 대조 = 실제 운영 파일의 블록을 파스 트리에서 꺼내 그대로 평가해 독립 기준값과 대조.
#   위반 주입 = (1) 도우미 사본에 돌연변이 8종을 덧씌워 같은 검사를 돌린다 (2) 수리 이전 식 원문 표본
#   (08_Tests/fixtures/daily_fdb_pre_c11_specimens.R)으로 같은 검사를 돌린다 → 해당 축이 빨개져야 한다.
#   ★운영 저장값(fdb_daily_*.parquet)과의 일치·불일치는 단정하지 않는다 — 2단계 재빌드로 저장값이 바뀌면 뒤집히는
#   검사가 되기 때문이다(참고 출력만).
#
# 축: A 전제·배선(AST) · B 도우미 합성 양성 대조 · E 실데이터 읽기 전용(판정서 실례) · M 위반 주입
# 쓰기: tempdir() 만(sourceCpp cacheDir 포함). 운영 .cache·원장·로그에 쓰지 않는다.
# 실행: Rscript 08_Tests/factor_db/test_daily_fdb_pit_c11.R   (R_ENVIRON_USER=<빈 파일> 권장 · 데이터 루트 = QM_ROOT)

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(Rcpp) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ROOT))
FDB    <- file.path(ROOT, "02_Infrastructure/factor_db")
HELPER <- file.path(FDB, "factor_db_daily_pit.R")
CPP    <- file.path(FDB, "factor_db_daily_rcpp.cpp")
P6 <- file.path(FDB, "factor_db_daily_phase6.R"); P7 <- file.path(FDB, "factor_db_daily_phase7.R")
P9 <- file.path(FDB, "factor_db_daily_phase9b.R")
AVAIL <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
SPEC  <- file.path(ROOT, "08_Tests/fixtures/daily_fdb_pre_c11_specimens.R")
CACHE <- file.path(DATA_ROOT, ".cache")

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
skip <- function(axis, reason, missing) {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  SKIP  %s — %s [%s]\n", axis, reason, missing))
}
raises <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
TD <- file.path(tempdir(), paste0("fdbpit_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)

# ── AST 도우미: 최상위 식(첫 줄 deparse 접두)·PART_x j-블록 안 대입문 ─────────────────────────
.dp1 <- function(e) paste(deparse(e, width.cutoff = 500L)[1], collapse = "")
top_exprs <- function(file) parse(file, keep.source = FALSE, encoding = "UTF-8")
top_expr <- function(file, starts) {
  ex <- top_exprs(file)
  i <- which(vapply(ex, function(e) startsWith(.dp1(e), starts), TRUE))
  if (length(i) != 1L) stop(sprintf("top_expr(%s): '%s' → %d개", basename(file), starts, length(i)))
  ex[[i]]
}
inner_stmts <- function(file, part_prefix, lhs_names) {
  e <- top_expr(file, part_prefix)
  br <- e[[3]][[4]]
  if (!identical(br[[1]], as.name("{"))) stop("inner_stmts: j-블록 아님")
  out <- list()
  for (k in 2:length(br)) {
    s <- br[[k]]
    if (is.call(s) && identical(s[[1]], as.name("<-"))) {
      lhs <- s[[2]]
      nm <- if (is.name(lhs)) as.character(lhs) else if (is.call(lhs)) as.character(lhs[[2]]) else ""
      if (nm %in% lhs_names) out[[length(out) + 1L]] <- s
    }
  }
  out
}
has_named_arg <- function(e, arg) {       # 식 안 어딘가의 호출에 이름 붙은 인자 arg 가 있는가
  if (is.call(e)) {
    nms <- names(as.list(e))
    if (!is.null(nms) && arg %in% nms) return(TRUE)
    for (k in seq_along(e)) if (!is.null(e[[k]]) && has_named_arg(e[[k]], arg)) return(TRUE)
  }
  FALSE
}
top_calls <- function(file) vapply(top_exprs(file), .dp1, "")

# =============================================================================
cat("=== A 전제·배선 ===\n")
for (p in c(HELPER, CPP, P6, P7, P9, AVAIL, SPEC)) chk(paste("A0 존재", basename(p)), file.exists(p), p)
if (!all(file.exists(c(HELPER, CPP, P6, P7, P9, AVAIL, SPEC)))) {
  cat(toJSON(list(test = "daily_fdb_pit_c11", pass = PASS, fail = FAIL + 1L, skipped = 0L, total = PASS + FAIL + 1L,
                  skips = list()), auto_unbox = TRUE), "\n", sep = ""); quit(status = 1L, save = "no")
}
for (p in c(P6, P7, P9, HELPER)) chk(paste("A1 parse", basename(p)), !raises(top_exprs(p)))
tc6 <- top_calls(P6); tc7 <- top_calls(P7); tc9 <- top_calls(P9)
src_ok <- function(tc, f) any(startsWith(tc, "source(") & grepl(f, tc, fixed = TRUE))
chk("A2 phase6 가 fred_availability.R·factor_db_daily_pit.R 를 source", src_ok(tc6, "fred_availability.R") && src_ok(tc6, "factor_db_daily_pit.R"))
chk("A2 phase7 가 fred_availability.R·factor_db_daily_pit.R 를 source", src_ok(tc7, "fred_availability.R") && src_ok(tc7, "factor_db_daily_pit.R"))
chk("A2 phase9b 가 factor_db_daily_pit.R 를 source", src_ok(tc9, "factor_db_daily_pit.R"))
chk("A3 세 파일 모두 regime 스탬프 가드(fdb_regime_c11_mask) 호출",
    any(startsWith(tc6, "fdb_regime_c11_mask(")) && any(startsWith(tc7, "fdb_regime_c11_mask(")) && any(startsWith(tc9, "fdb_regime_c11_mask(")))
# A4 phase6: D08 대입문의 우변 = fdb_d08_expanding_tail_beta · VIX 블록 = fdb_fred_on_kr_dates · roll 인자 없음
st_d08 <- tryCatch(inner_stmts(P6, "PART_A <- RW[", "D08_Tail_Beta"), error = function(e) list())
chk("A4 phase6 D08 = fdb_d08_expanding_tail_beta(...) 한 문장",
    length(st_d08) == 1L && identical(st_d08[[1]][[3]][[1]], as.name("fdb_d08_expanding_tail_beta")))
vb6 <- tryCatch(top_expr(P6, "if (file.exists(.macro_path_p6))"), error = function(e) NULL)
chk("A4 phase6 VIX 블록이 fdb_fred_on_kr_dates 경유 · roll 결합 없음",
    !is.null(vb6) && "fdb_fred_on_kr_dates" %in% all.names(vb6) && !has_named_arg(vb6, "roll"))
mb7 <- tryCatch(top_expr(P7, "if (file.exists(.macro_path_p7))"), error = function(e) NULL)
chk("A5 phase7 매크로 블록: fdb_fred_stat_on_kr_dates·fdb_expanding_pct·fdb_change_by_date 경유 · frank/shift/roll 없음",
    !is.null(mb7) && all(c("fdb_fred_stat_on_kr_dates", "fdb_expanding_pct", "fdb_change_by_date") %in% all.names(mb7)) &&
      !any(c("frank", "shift") %in% all.names(mb7)) && !has_named_arg(mb7, "roll"))
st_mrs <- tryCatch(inner_stmts(P9, "PART_VR <- RW[", "mrs_pctile"), error = function(e) list())
i_att <- which(startsWith(tc9, "RW <- fdb_attach_mrs_expanding_pct(RW)")); i_vr <- which(startsWith(tc9, "PART_VR <- RW["))
chk("A6 phase9b: PART_VR 앞에서 MRS 누적 백분위를 붙이고 mrs_pctile 이 그것만 쓴다(frank 없음)",
    length(st_mrs) == 1L && "MRS_Pct_Exp" %in% all.names(st_mrs[[1]]) && !("frank" %in% all.names(st_mrs[[1]])) &&
      length(i_att) == 1L && length(i_vr) == 1L && i_att < i_vr)

# ── 로드: S0 층 · C++ · 도우미(환경 H — 돌연변이는 사본 H 에 덧씌운다) ─────────────────────────
source(AVAIL)
options(fred_avail.root = ROOT, fred_avail.data_root = DATA_ROOT)
cpp_ok <- !raises(sourceCpp(CPP, cacheDir = file.path(TD, "rcpp")))
chk("A7 factor_db_daily_rcpp.cpp 컴파일·roll_expanding_tail_beta_cpp 노출", cpp_ok && exists("roll_expanding_tail_beta_cpp"))
source(SPEC)
HELPER_TXT <- readLines(HELPER, encoding = "UTF-8", warn = FALSE)
load_helper <- function(extra = character(0)) {
  f <- file.path(TD, sprintf("helper_%d.R", as.integer(runif(1, 1e6, 9e6))))
  writeLines(c(HELPER_TXT, "", extra), f, useBytes = TRUE)
  H <- new.env(parent = globalenv()); sys.source(f, envir = H, keep.source = FALSE); H
}
H0 <- load_helper()

# =============================================================================
# B 합성 양성 대조 — ck_B(H) 는 이름 붙은 논리값을 돌려준다(돌연변이 재사용)
syn_cal <- local({ d <- seq(as.Date("2019-01-01"), as.Date("2021-12-31"), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] })
ck_B <- function(H) {
  r <- c()
  set.seed(7)
  x <- round(rnorm(300), 1); x[c(5, 40, 41)] <- NA
  ref <- rep(NA_real_, length(x)); ok <- which(!is.na(x)); v <- x[ok]
  ref[ok] <- vapply(seq_along(v), function(i) frank(v[seq_len(i)], ties.method = "average")[i] / i, 0)
  e <- H$fdb_expanding_pct(x)
  r["B1 누적 백분위 = 접두 frank(평균 순위)/i (동률·NA 포함)"] <- isTRUE(all.equal(e, ref, tolerance = 1e-14))
  r["B2 누적 백분위 마지막 = 전표본 frank/N"] <- isTRUE(all.equal(tail(e[!is.na(e)], 1), tail(frank(v, ties.method = "average") / length(v), 1)))
  r["B2b 누적 백분위 절단 불변"] <- isTRUE(all.equal(H$fdb_expanding_pct(x[1:120]), e[1:120]))
  # 12개월 변화: 2024-10 결측
  dd <- seq(as.Date("2023-01-01"), as.Date("2025-12-01"), by = "month"); dd <- dd[dd != as.Date("2024-10-01")]
  vv <- 100 + seq_along(dd) * 0.5 + (as.POSIXlt(dd)$mon == 3) * 2
  ch <- H$fdb_change_by_date(vv, dd, 12L)
  want <- function(t) { t <- as.Date(t); b <- seq(t, by = "-12 months", length.out = 2)[2]; if (b %in% dd) vv[dd == t] / vv[dd == b] - 1 else NA_real_ }
  r["B3 날짜 기준 12개월 변화(2025-11 기준 = 2024-11 · 2025-10 기준 부재 → NA · 첫 해 NA)"] <-
    isTRUE(all.equal(ch[dd == as.Date("2025-11-01")], want("2025-11-01"))) && is.na(ch[dd == as.Date("2025-10-01")]) &&
    all(is.na(ch[dd < as.Date("2024-01-01")])) && isTRUE(all.equal(ch[dd == as.Date("2024-11-01")], want("2024-11-01")))
  # D08 C++ = 무차별 대입(R, t 이하만) · 절단 불변
  brute <- function(ret, bm, k, mt) {
    m <- length(ret); out <- rep(NA_real_, m)
    for (t in seq_len(m)) {
      b <- bm[1:t]; rr <- ret[1:t]; s <- sd(b, na.rm = TRUE)
      if (is.na(s) || !(s > 1e-8)) next
      msk <- !is.na(b) & !is.na(rr) & abs(b) > k * s
      if (sum(msk) < mt) next
      out[t] <- -lm.fit(cbind(1, b[msk]), rr[msk])$coefficients[2L]
    }
    out
  }
  set.seed(11); mx <- 0; na_same <- TRUE
  for (k in 1:12) {
    m <- sample(80:400, 1); bm <- rt(m, 3) * 0.01; ret <- 0.9 * bm + rnorm(m, 0, 0.01)
    bm[sample(m, 4)] <- NA; ret[sample(m, 4)] <- NA
    a <- H$fdb_d08_expanding_tail_beta(ret, bm, 2, 6L); b <- brute(ret, bm, 2, 6L)
    na_same <- na_same && identical(is.na(a), is.na(b))
    if (any(!is.na(a) & !is.na(b))) mx <- max(mx, max(abs(a - b), na.rm = TRUE))
  }
  r["B4 D08 누적 꼬리베타 = 무차별 대입(t 이하만 · NA 패턴 동일 · |차|<1e-10)"] <- na_same && mx < 1e-10
  # 절단 불변: 운영 정의 수치(2σ · 꼬리 ≥60)로 값이 실제로 나오는 길이(2,500일)에서
  set.seed(12); m <- 3000L; bm <- rt(m, 3) * 0.01; ret <- 0.9 * bm + 0.5 * pmin(bm, 0) + rnorm(m, 0, 0.01)
  a <- H$fdb_d08_expanding_tail_beta(ret, bm, 2, 60L); a2 <- H$fdb_d08_expanding_tail_beta(ret[1:2200], bm[1:2200], 2, 60L)
  r["B5 D08 절단 불변(t 이후를 잘라도 t 이하 값 불변 · 값 존재 >500)"] <- isTRUE(all.equal(a2, a[1:2200])) && sum(!is.na(a2)) > 500
  # 스탬프 가드
  df <- data.frame(Date = as.Date("2020-01-01") + 0:4, MRS = c(1, 2, 3, 4, 5))
  f0 <- file.path(TD, "rg_none.parquet"); arrow::write_parquet(df, f0)
  # r1: 가드는 접두가 아니라 **현행 규칙 키**와 같아야 통과한다(V2 소견 5) — 현행 키는 S0 에서 받고, 옛 epoch(b1) 판은 F
  CUR_KEY <- H$.fdb_current_regime_key(); OLD_KEY <- "c11_avail:2026-09-24.b1:78c87534"
  tb <- arrow::arrow_table(df); tb$metadata[[FDB_REGIME_C11_STAMP_KEY_T]] <- CUR_KEY
  f1 <- file.path(TD, "rg_md.parquet"); arrow::write_parquet(tb, f1)
  f2 <- file.path(TD, "rg_col.parquet"); d2 <- df; d2[[FDB_REGIME_C11_STAMP_KEY_T]] <- CUR_KEY; arrow::write_parquet(d2, f2)
  tb3 <- arrow::arrow_table(df); tb3$metadata[[FDB_REGIME_C11_STAMP_KEY_T]] <- "latest"
  f3 <- file.path(TD, "rg_bad.parquet"); arrow::write_parquet(tb3, f3)
  d4 <- as.data.table(df); setattr(d4, FDB_REGIME_C11_STAMP_KEY_T, CUR_KEY)   # S3 수리판 형식(R 속성)
  d6 <- as.data.table(df); setattr(d6, FDB_REGIME_C11_STAMP_KEY_T, OLD_KEY); f6 <- file.path(TD, "rg_attr_stale.parquet"); arrow::write_parquet(d6, f6)
  f4 <- file.path(TD, "rg_attr.parquet"); arrow::write_parquet(d4, f4)
  d5 <- as.data.table(df); setattr(d5, FDB_REGIME_C11_STAMP_KEY_T, "latest"); f5 <- file.path(TD, "rg_attr_bad.parquet"); arrow::write_parquet(d5, f5)
  r["B6 스탬프 판독: 없음 F · R 속성 T · 메타데이터 T · 열 T · 형식 불일치(메타·속성) F · 파일 없음 F"] <-
    !H$fdb_regime_c11_ok(f0) && H$fdb_regime_c11_ok(f4) && H$fdb_regime_c11_ok(f1) && H$fdb_regime_c11_ok(f2) &&
    !H$fdb_regime_c11_ok(f3) && !H$fdb_regime_c11_ok(f5) && !H$fdb_regime_c11_ok(file.path(TD, "nope.parquet")) &&
    isTRUE(startsWith(CUR_KEY, "c11_avail:")) && !identical(CUR_KEY, OLD_KEY)
  r["B6c 옛 epoch 스탬프(규칙이 바뀐 뒤의 판) = F · 현행 키 미해석(NA) = F"] <-
    !H$fdb_regime_c11_ok(f6) && !H$fdb_regime_c11_ok(f4, current_key = NA_character_)
  g0 <- as.data.table(df); ok0 <- suppressWarnings(H$fdb_regime_c11_mask(g0, c("MRS", "없는열"), f0, "t"))
  g1 <- as.data.table(df); ok1 <- suppressWarnings(H$fdb_regime_c11_mask(g1, c("MRS"), f1, "t"))
  r["B6b 가드: 스탬프 없으면 열 전부 NA · 있으면 값 보존"] <- !ok0 && all(is.na(g0$MRS)) && ok1 && identical(g1$MRS, df$MRS)
  # MRS 누적 백분위 부착: 날짜별 한 값 · 행 순서 보존 · 절단 불변
  rw <- CJ(Ticker = c("A", "B", "C"), Date = as.Date("2020-01-01") + 0:59)
  set.seed(3); mk <- data.table(Date = as.Date("2020-01-01") + 0:59, MRS = round(runif(60, 0, 60), 0)); mk$MRS[7] <- NA
  rw <- mk[rw, on = "Date"]; rw <- rw[sample(.N)]; ord <- paste(rw$Ticker, rw$Date)
  a1 <- H$fdb_attach_mrs_expanding_pct(copy(rw))
  want_mk <- copy(mk)[!is.na(MRS)][order(Date)]; want_mk[, p := vapply(seq_len(.N), function(i) frank(MRS[1:i], ties.method = "average")[i] / i, 0)]
  chk_v <- want_mk$p[match(a1$Date, want_mk$Date)]
  a2 <- H$fdb_attach_mrs_expanding_pct(copy(rw[Date <= as.Date("2020-01-31")]))
  a1s <- a1[Date <= as.Date("2020-01-31")]
  r["B7 MRS 누적 백분위: 기준값 일치 · 행 순서 보존 · 절단 불변"] <- identical(paste(a1$Ticker, a1$Date), ord) &&
    isTRUE(all.equal(a1$MRS_Pct_Exp, chk_v)) &&
    isTRUE(all.equal(a2$MRS_Pct_Exp, a1s$MRS_Pct_Exp[match(paste(a2$Ticker, a2$Date), paste(a1s$Ticker, a1s$Date))]))
  # fail-closed
  r["B8 fail-closed: DEXKOUS·미등록 계열 거부 · S0 층 미로드 시 거부"] <-
    raises(H$fdb_fred_obs(data.table(Date = as.Date("2020-01-01"), Value = 1, Series_ID = "DEXKOUS"), "DEXKOUS")) &&
    raises(H$fdb_fred_obs(data.table(Date = as.Date("2020-01-01"), Value = 1, Series_ID = "NOPE"), "NOPE")) &&
    raises({ f <- H$.fdb_need_avail; environment(f) <- new.env(parent = baseenv()); f() })
  # 단조 가드: 규칙 사본에 2020-01 CPI 공표 지연 override(→ 2020-01 이 2020-02 보다 늦게 풀림) → 결합 거부
  RL <- fred_avail_rules(file.path(ROOT, "06_Registry/fred_availability_rules.json"))
  RLb <- RL; i_cpi <- RLb$index[["CPIAUCSL"]]
  RLb$raw$series[[i_cpi]]$release_overrides <- c(RLb$raw$series[[i_cpi]]$release_overrides,
    list(list(obs = "2020-01-01", us_release = "2020-06-30", source = "test: 단조 위반 주입")))
  cpi <- data.table(Date = seq(as.Date("2019-01-01"), as.Date("2021-06-01"), by = "month")); cpi[, Value := 250 + .I]
  st_f <- function(v, d) -H$fdb_change_by_date(v, d, 12L)
  r["B9 가용일 단조 위반(앞 관측이 늦게 풀림) → 누적 통계 결합 거부 · 정상 규칙은 통과"] <-
    raises(H$fdb_fred_stat_on_kr_dates(syn_cal, cpi, "CPIAUCSL", st_f, kr_calendar = syn_cal, rules = RLb)) &&
    !raises(H$fdb_fred_stat_on_kr_dates(syn_cal, cpi, "CPIAUCSL", st_f, kr_calendar = syn_cal, rules = RL))
  # 합성 VIX: 한국 d 에는 미국 날짜 < d 관측만
  vx <- data.table(Date = syn_cal, Value = seq_along(syn_cal) + 10)
  j <- H$fdb_fred_on_kr_dates(syn_cal, vx, "VIXCLS", kr_calendar = syn_cal)
  r["B10 합성 VIX: 모든 한국 d 의 관측일 < d · 가용일 위반 0"] <- all(j$obs_date[-1] < j$Date[-1]) && is.na(j$value[1]) &&
    nrow(fred_join_violations(j$Date[-1], j$obs_date[-1], "VIXCLS", "decision_close", kr_calendar = syn_cal)) == 0L
  r
}
FDB_REGIME_C11_STAMP_KEY_T <- "c11_avail_regime_key"   # 검사 쪽 독립 표기(도우미 상수와 대조)
cat("=== B 도우미 합성 양성 대조 ===\n")
chk("B0 도우미 스탬프 키 = 검사 표기(c11_avail_regime_key)", identical(H0$FDB_REGIME_C11_STAMP_KEY, FDB_REGIME_C11_STAMP_KEY_T))
rB <- ck_B(H0); for (nm in names(rB)) chk(nm, rB[[nm]])

# =============================================================================
# E 실데이터(읽기 전용) — 운영 블록을 파스 트리에서 꺼내 평가(impl = "new") / 수리 이전 표본(impl = "spec")
need <- file.path(CACHE, c("RAWDATA.parquet", "macro_fred.parquet", "benchmark.parquet", "regime_daily_v2.parquet", "trading_calendar.parquet"))
HAVE_DATA <- all(file.exists(need))
if (HAVE_DATA) {
  suppressMessages(library(arrow))
  m_all <- as.data.table(read_parquet(file.path(CACHE, "macro_fred.parquet"), mmap = FALSE)); m_all[, Date := as.Date(Date)]
  ds <- open_dataset(file.path(CACHE, "RAWDATA.parquet"))
  rw_d32 <- as.data.table(ds |> dplyr::filter(Date >= as.Date("2018-06-01") & Date <= as.Date("2020-03-31")) |>
                            dplyr::select(Date, Ticker, Ret) |> dplyr::collect())
  rw_d32[, Date := as.Date(Date)]
  set.seed(20260924)
  tk_d32 <- sample(rw_d32[Date == as.Date("2020-03-31"), unique(Ticker)], 400)
  rw_d32 <- rw_d32[Ticker %in% tk_d32]; setkey(rw_d32, Ticker, Date)
  kr_all <- sort(unique(as.Date(dplyr::collect(dplyr::distinct(dplyr::select(ds, Date)))$Date)))
  tk_long <- as.data.table(ds |> dplyr::filter(Date <= as.Date("2006-12-31")) |> dplyr::count(Ticker) |> dplyr::collect())[n > 1500]$Ticker
  set.seed(9); tk_long <- sample(tk_long, min(25L, length(tk_long)))
  rw_long <- as.data.table(ds |> dplyr::filter(Ticker %in% tk_long) |> dplyr::select(Date, Ticker, Ret, Size) |> dplyr::collect())
  rw_long[, Date := as.Date(Date)]
  bmk <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet"), mmap = FALSE)); setnames(bmk, "Ret", "BM_Ret", skip_absent = TRUE)
  bmk[, Date := as.Date(Date)]
  rw_long <- bmk[, .(Date, BM_Ret)][rw_long, on = "Date"]; setkey(rw_long, Ticker, Date)
  reg <- as.data.table(read_parquet(file.path(CACHE, "regime_daily_v2.parquet"), mmap = FALSE)); reg[, Date := as.Date(Date)]
  # 독립 기준값 ------------------------------------------------------------
  vix <- m_all[Series_ID == "VIXCLS" & !is.na(Value), .(VIX = last(Value)), by = Date][order(Date)]
  kd <- sort(unique(rw_d32$Date))
  ref_vp <- vix[.(Date = kd - 1L), on = "Date", roll = TRUE]$VIX           # 미국 날짜 ≤ 한국 날짜−1 역일 = 미국 < 한국
  ref_vs <- vix[.(Date = kd), on = "Date", roll = TRUE]$VIX
  refd <- merge(rw_d32, data.table(Date = kd, Vp = ref_vp), by = "Date"); setkey(refd, Ticker, Date)
  ref_d32 <- refd[, { cp <- c(NA, diff(log(Vp))); n <- .N; i <- max(1, n - 251):n
    ok <- !is.na(Ret[i]) & !is.na(cp[i]) & is.finite(cp[i])
    .(last = Date[n], pit = if (sum(ok) < 3) NA_real_ else cov(Ret[i][ok], cp[i][ok]) / var(cp[i][ok])) }, by = Ticker][last == as.Date("2020-03-31")]
  exp_pct <- function(x) vapply(seq_along(x), function(i) { h <- x[seq_len(i)]; (sum(h < x[i]) + (sum(h == x[i]) + 1) / 2) / i }, 0)
  ewma_ref <- function(x, h = 21) { a <- 1 - exp(-log(2) / h); o <- rep(NA_real_, length(x)); o[1] <- x[1]
    for (k in 2:length(x)) { if (is.na(x[k])) o[k] <- o[k - 1] else if (is.na(o[k - 1])) o[k] <- x[k] else o[k] <- a * x[k] + (1 - a) * o[k - 1] }; o }
  vix[, re10 := -exp_pct(VIX)]
  vix[, re11 := { ch <- c(NA_real_, diff(log(VIX))); ch[!is.finite(ch)] <- NA_real_; -ewma_ref(ch) }]
  kr_e <- kr_all[kr_all >= as.Date("2019-01-01") & kr_all <= as.Date("2020-12-31")]
  ref_re10 <- vix[.(Date = kr_e - 1L), on = "Date", roll = TRUE]$re10
  ref_re11 <- vix[.(Date = kr_e - 1L), on = "Date", roll = TRUE]$re11
  hy <- m_all[Series_ID == "BAMLH0A0HYM2" & !is.na(Value), .(HY = last(Value)), by = Date][order(Date)]
  cpi <- m_all[Series_ID == "CPIAUCSL" & !is.na(Value), .(CPI = last(Value)), by = Date][order(Date)]
  # HY·CPI 기준: 규칙(S0 정본)으로 가용일을 붙인 뒤 '가용일 ≤ 한국 d 인 최신 관측' (S0 층은 자체 검사로 따로 잰다)
  hy[, av := fred_avail_date("BAMLH0A0HYM2", Date)]; hy[, re13 := -exp_pct(HY)]
  cpi[, av := fred_avail_date("CPIAUCSL", Date)]
  cpi[, re14 := { bd <- as.Date(sprintf("%d-%02d-01", as.POSIXlt(Date)$year + 1899L, as.POSIXlt(Date)$mon + 1L))   # 1년 전 같은 달(M-01)
                  -(CPI / CPI[match(bd, Date)] - 1) }]
  by_avail <- function(tab, col, kds) { t2 <- tab[!is.na(av) & !is.na(get(col))][order(av, Date)]
    idx <- findInterval(as.integer(kds), as.integer(t2$av)); out <- rep(NA_real_, length(kds)); out[idx > 0] <- t2[[col]][idx[idx > 0]]; out }
  ref_re13 <- by_avail(hy, "re13", kr_all)
  ref_re14 <- by_avail(cpi, "re14", kr_all)
  stored <- tryCatch(as.data.table(read_parquet(file.path(CACHE, "factor_db_daily/fdb_daily_202003.parquet"), mmap = FALSE,
                     col_select = c("Date", "Ticker", "D32_Beta_VIX", "RE10_VIX_Pctile", "RE14_Inflation_YoY"))), error = function(e) NULL)
}

# 구현 어댑터 ---------------------------------------------------------------
impl_new <- function(H) {
  list(
    vix = function(RW) {
      e <- new.env(parent = H); e$RW <- copy(RW); e$CACHE_DIR <- CACHE
      e$.macro_path_p6 <- file.path(CACHE, "macro_fred.parquet")
      eval(top_expr(P6, "if (\"VIX\" %in% names(RW))"), e)
      eval(top_expr(P6, "if (file.exists(.macro_path_p6))"), e)
      eval(top_expr(P6, "if (!(\"VIX\" %in% names(RW)))"), e)
      e$RW
    },
    macro = function(kds) {
      e <- new.env(parent = H); e$RW <- data.table(Date = kds); e$CACHE_DIR <- CACHE
      e$.macro_path_p7 <- file.path(CACHE, "macro_fred.parquet"); e$MACRO_F <- NULL
      suppressWarnings(eval(top_expr(P7, "if (file.exists(.macro_path_p7))"), e))
      e$MACRO_F
    },
    d08 = function(ret, bm) {
      e <- new.env(parent = H); e$ret <- ret; e$bm <- bm; e$m <- length(ret)
      for (s in inner_stmts(P6, "PART_A <- RW[", "D08_Tail_Beta")) eval(s, e)
      e$D08_Tail_Beta
    },
    re04 = function(RWp) {
      e <- new.env(parent = H); e$RW <- copy(RWp)
      eval(top_expr(P9, "RW <- fdb_attach_mrs_expanding_pct(RW)"), e)
      eval(top_expr(P9, "PART_VR <- RW["), e)
      e$PART_VR[, .(Ticker, Date, RE04 = RE04_HighVol_Beta)]
    })
}
impl_spec <- list(
  vix = function(RW) pre_c11_vix_join(copy(RW), m_all),
  macro = function(kds) pre_c11_macro_f(m_all, kds),
  d08 = function(ret, bm) pre_c11_d08(ret, bm),
  re04 = function(RWp) RWp[, .(Date = Date, RE04 = pre_c11_re04(as.double(Ret), as.double(BM_Ret), as.double(MRS))), by = Ticker])
st_d32 <- inner_stmts(P6, "PART_A <- RW[", c("vix_chg", "D32_Beta_VIX"))

ck_E <- function(I) {
  r <- c()
  # E1·E2 D32
  RWv <- I$vix(rw_d32)
  vk <- unique(RWv[, .(Date, VIX)])[order(Date)]
  r["E1 VIX 열: 한국 d = 미국 날짜 < d 의 최신 VIX(2018-06~2020-03 전 거래일 · 독립 기준)"] <-
    isTRUE(all.equal(vk$VIX, ref_vp[match(vk$Date, kd)])) && sum(!is.na(vk$VIX)) > 400
  d32 <- RWv[, { e <- new.env(); e$ret <- as.double(Ret); e$VIX <- VIX; e$m <- .N
    for (s in st_d32) eval(s, e); .(Date = Date, rep = e$D32_Beta_VIX) }, by = Ticker]
  z <- merge(d32[Date == as.Date("2020-03-31")], ref_d32, by = "Ticker")[!is.na(rep) & !is.na(pit)]
  sp <- if (nrow(z) > 10) cor(z$rep, z$pit, method = "spearman") else NA
  r["E2 D32 2020-03-31 = 독립 PIT 기준(Spearman>0.99999 · max|차|<1e-9 · n≥200)"] <- nrow(z) >= 200 && isTRUE(sp > 0.99999) &&
    max(abs(z$rep - z$pit)) < 1e-9
  E_last$d32 <<- z
  # E3~E6 매크로
  MF <- I$macro(kr_all)
  g <- MF[match(kr_e, Date)]
  r["E3 RE10 = 누적 백분위 × 미국<한국 가용(2019~2020 전 한국일)"] <- isTRUE(all.equal(g$RE10_VIX_Pctile, ref_re10))
  r["E4 RE11 = EWMA × 미국<한국 가용(2019~2020 전 한국일)"] <- isTRUE(all.equal(g$RE11_VIX_Change_EWMA, ref_re11))
  r["E5 RE13 = 누적 백분위 × ICE 한국 d+2 가용(전 한국일)"] <- isTRUE(all.equal(MF$RE13_Credit_Spread_Pctile[match(kr_all, MF$Date)], ref_re13)) &&
    sum(!is.na(ref_re13)) > 100
  r["E6 RE14 = 날짜 기준 12개월 × CPI 공표 상한 가용(전 한국일)"] <- isTRUE(all.equal(MF$RE14_Inflation_YoY[match(kr_all, MF$Date)], ref_re14))
  E_last$mf <<- MF
  # E8 D08 실데이터: 절단 불변 · 복제 아님
  tr_ok <- TRUE; n_cmp <- 0L; n_const <- 0L; n_both <- 0L
  for (tk in unique(rw_long$Ticker)) {
    s <- rw_long[Ticker == tk]
    a <- I$d08(as.double(s$Ret), as.double(s$BM_Ret))
    Tn <- sum(s$Date <= as.Date("2012-12-31"))
    if (Tn > 10) { b <- I$d08(as.double(s$Ret[1:Tn]), as.double(s$BM_Ret[1:Tn]))
      tr_ok <- tr_ok && isTRUE(all.equal(b, a[1:Tn])); n_cmp <- n_cmp + sum(!is.na(b)) }
    i1 <- which(s$Date <= as.Date("2008-01-31")); i2 <- length(a)
    if (length(i1) && max(s$Date) > as.Date("2009-12-31") && !is.na(a[max(i1)]) && !is.na(a[i2])) { n_both <- n_both + 1L; n_const <- n_const + (abs(a[max(i1)] - a[i2]) < 1e-12) }
  }
  r["E8 D08 실데이터 절단 불변(T=2012-12-31 · 25종목)"] <- tr_ok && n_cmp > 1000
  r["E8b D08 실데이터 날짜별 값(2008-01 ≠ 마지막 날 · 복제 아님)"] <- n_both >= 5 && n_const == 0L
  # E9 RE04 실데이터: 절단 불변(스탬프 가드를 우회해 MRS 를 직접 싣는다 — 식 자체의 PIT 성질을 잰다)
  RWp <- reg[, .(Date, MRS)][rw_long, on = "Date"]; setkey(RWp, Ticker, Date)
  f1 <- I$re04(RWp); f2 <- I$re04(RWp[Date <= as.Date("2012-12-31")])
  zz <- merge(f1[Date <= as.Date("2012-12-31")], f2, by = c("Ticker", "Date"))
  diff_n <- zz[is.na(RE04.x) != is.na(RE04.y) | abs(RE04.x - RE04.y) > 1e-10, .N]
  r["E9 RE04 실데이터 절단 불변(T=2012-12-31 · 값 존재 >1000행)"] <- diff_n == 0L && zz[!is.na(RE04.x), .N] > 1000
  r
}
E_last <- new.env()

cat("=== E 실데이터(읽기 전용) ===\n")
if (!HAVE_DATA) {
  skip("E_real_data", "운영 데이터 부재 — 실데이터 축 미측정", paste(basename(need[!file.exists(need)]), collapse = ","))
} else {
  rE <- ck_E(impl_new(H0)); for (nm in names(rE)) chk(nm, rE[[nm]])
  for (sid in c("VIXCLS", "BAMLH0A0HYM2", "CPIAUCSL")) {
    o <- H0$fdb_fred_obs(m_all, sid); j <- H0$fdb_fred_on_kr_dates(kr_all, o, sid); jj <- j[!is.na(obs_date)]
    chk(sprintf("E7 %s 결합 가용일 위반 0 · 같은 날짜 0 (%d 한국일)", sid, nrow(jj)),
        nrow(jj) > 100 && nrow(fred_join_violations(jj$Date, jj$obs_date, sid, "decision_close")) == 0L && !any(jj$obs_date == jj$Date))
  }
  # 참고(단정 아님): 운영 저장값 대비 — 2단계 재빌드 전 저장값은 같은 날짜 판이다
  if (!is.null(stored)) {
    stored[, Date := as.Date(Date)]
    z <- merge(E_last$d32, stored[Date == as.Date("2020-03-31"), .(Ticker, st = D32_Beta_VIX)], by = "Ticker")[!is.na(st)]
    mf <- E_last$mf
    cat(sprintf("  info  [참고] D32 2020-03-31 Spearman(수리판, 저장값)=%.4f (판정서 V-09: 저장값 대 PIT 판 0.2068) · n=%d\n",
                cor(z$rep, z$st, method = "spearman"), nrow(z)))
    s1 <- unique(stored[Date %in% as.Date(c("2020-03-02", "2020-03-12")), .(Date, RE10_VIX_Pctile, RE14_Inflation_YoY)])
    for (k in seq_len(nrow(s1))) cat(sprintf("  info  [참고] %s 저장 RE10 %.7f → 수리 %.7f · 저장 RE14 %.7f → 수리 %.7f\n", s1$Date[k],
        s1$RE10_VIX_Pctile[k], mf[Date == s1$Date[k]]$RE10_VIX_Pctile, s1$RE14_Inflation_YoY[k], mf[Date == s1$Date[k]]$RE14_Inflation_YoY))
  }
}

# =============================================================================
cat("=== M 위반 주입(돌연변이 · 수리 이전 표본) — 해당 축이 빨개져야 한다 ===\n")
MUT <- list(
  M1_same_date_join = list(expect_B = character(0), expect_E = c("E1", "E2", "E3", "E4", "E5", "E6"), code = c(
    "fdb_fred_on_kr_dates <- function(kr_dates, obs_dt, series_id, value_col = 'Value', kr_calendar = NULL, rules = NULL) {",
    "  od <- as.data.table(obs_dt); od <- data.table(Date = as.Date(od$Date), v = od[[value_col]])[!is.na(v)]",
    "  setkey(od, Date); od[, obs_date := Date]; k <- data.table(Date = as.Date(kr_dates)); r <- od[k, on = 'Date', roll = TRUE]",
    "  data.table(Date = k$Date, value = as.double(r$v), obs_date = r$obs_date, avail_date = as.Date(NA)) }")),
  M2_one_row_lag = list(expect_B = character(0), expect_E = c("E5"), code = c(
    "fdb_fred_on_kr_dates <- function(kr_dates, obs_dt, series_id, value_col = 'Value', kr_calendar = NULL, rules = NULL) {",
    "  od <- as.data.table(obs_dt); od <- data.table(Date = as.Date(od$Date), v = od[[value_col]])[!is.na(v)]",
    "  setkey(od, Date); od[, obs_date := Date]; k <- data.table(Date = as.Date(kr_dates)); r <- od[k, on = 'Date', roll = TRUE]",
    "  data.table(Date = k$Date, value = shift(as.double(r$v)), obs_date = shift(r$obs_date), avail_date = as.Date(NA)) }")),
  M3_full_sample_pct = list(expect_B = c("B1", "B2b"), expect_E = c("E3", "E5"), code = c(
    "fdb_expanding_pct <- function(x) { x <- as.double(x); out <- rep(NA_real_, length(x)); ok <- !is.na(x)",
    "  out[ok] <- frank(x[ok], ties.method = 'average') / sum(ok); out }")),
  M4_d08_full_history = list(expect_B = c("B4", "B5"), expect_E = c("E8"), code = c(
    "fdb_d08_expanding_tail_beta <- function(ret, bm, k_sd, min_tail) pre_c11_d08(ret, bm)")),
  M5_row_shift_yoy = list(expect_B = c("B3"), expect_E = c("E6"), code = c(
    "fdb_change_by_date <- function(values, dates, months) { v <- as.double(values); v / shift(v, as.integer(months)) - 1 }")),
  M6_guard_always_ok = list(expect_B = c("B6", "B6c"), expect_E = character(0), code = c(
    "fdb_regime_c11_ok <- function(regime_path, ...) TRUE")),
  M9_prefix_only_stamp = list(expect_B = c("B6c"), expect_E = character(0), code = c(   # r1: 구판(접두만) — 옛 epoch 통과
    "fdb_regime_c11_ok <- function(regime_path, current_key = NULL) { if (!file.exists(regime_path)) return(FALSE)",
    "  tb <- tryCatch(arrow::read_parquet(regime_path, as_data_frame = FALSE, mmap = FALSE), error = function(e) NULL); if (is.null(tb)) return(FALSE)",
    "  .ok1 <- function(v) is.character(v) && length(v) == 1L && !is.na(v) && startsWith(v, FDB_REGIME_C11_STAMP_PREFIX)",
    "  if (.ok1(tryCatch(tb$metadata$r$attributes[[FDB_REGIME_C11_STAMP_KEY]], error = function(e) NULL))) return(TRUE)",
    "  if (.ok1(tryCatch(tb$metadata[[FDB_REGIME_C11_STAMP_KEY]], error = function(e) NULL))) return(TRUE)",
    "  if (FDB_REGIME_C11_STAMP_KEY %in% names(tb)) { v <- as.character(as.vector(tb[[FDB_REGIME_C11_STAMP_KEY]])); v <- v[!is.na(v)]",
    "    return(length(v) > 0L && all(startsWith(v, FDB_REGIME_C11_STAMP_PREFIX))) }; FALSE }")),
  M7_no_monotone_assert = list(expect_B = c("B9"), expect_E = character(0), code = c(
    "fdb_assert_avail_monotone <- function(obs_dates, series_id, kr_calendar = NULL, rules = NULL) invisible(TRUE)")),
  M8_mrs_full_sample = list(expect_B = c("B7"), expect_E = c("E9"), code = c(
    "fdb_attach_mrs_expanding_pct <- function(rw) { rw <- copy(as.data.table(rw))",
    "  rw[, MRS_Pct_Exp := fifelse(!is.na(MRS), frank(MRS, ties.method = 'average') / sum(!is.na(MRS)), NA_real_)]; rw }"))
)
red_of <- function(res, codes) { if (!length(codes)) return(character(0))
  nm <- names(res); codes[vapply(codes, function(cd) any(startsWith(nm, paste0(cd, " ")) & !unlist(res)), TRUE)] }
for (mn in names(MUT)) {
  mu <- MUT[[mn]]
  Hm <- tryCatch(load_helper(mu$code), error = function(e) NULL)
  if (is.null(Hm)) { chk(sprintf("%s 로드", mn), FALSE); next }
  rb <- if (length(mu$expect_B)) tryCatch(ck_B(Hm), error = function(e) c(`B? 오류` = FALSE)) else c()
  re <- if (length(mu$expect_E) && HAVE_DATA) tryCatch(ck_E(impl_new(Hm)), error = function(e) { cat("   (E 오류:", conditionMessage(e), ")\n"); c(`E? 오류` = FALSE) }) else c()
  gotB <- red_of(rb, mu$expect_B); gotE <- red_of(re, mu$expect_E)
  wantE <- if (HAVE_DATA) mu$expect_E else character(0)
  chk(sprintf("%s red (기대 %s → 빨강 %s)", mn, paste(c(mu$expect_B, wantE), collapse = ","), paste(c(gotB, gotE), collapse = ",")),
      setequal(gotB, mu$expect_B) && setequal(gotE, wantE))
}
if (HAVE_DATA) {
  rs <- tryCatch(ck_E(impl_spec), error = function(e) { cat("   (표본 E 오류:", conditionMessage(e), ")\n"); c(`E? 오류` = FALSE) })
  want_spec <- c("E1", "E2", "E3", "E4", "E5", "E6", "E8", "E9")
  got <- red_of(rs, want_spec)
  chk(sprintf("S0 수리 이전 식 원문 표본 red (기대 %s → 빨강 %s)", paste(want_spec, collapse = ","), paste(got, collapse = ",")),
      setequal(got, want_spec))
} else skip("S_specimen", "운영 데이터 부재 — 표본 대조 미측정", "RAWDATA/macro_fred")

unlink(TD, recursive = TRUE)
cat(sprintf("\n=== 결과: PASS %d · FAIL %d · SKIP %d ===\n", PASS, FAIL, length(SKIPS)))
cat(toJSON(list(test = "daily_fdb_pit_c11", pass = PASS, fail = FAIL, skipped = length(SKIPS),
                total = PASS + FAIL, skips = SKIPS), auto_unbox = TRUE), "\n", sep = "")
quit(status = if (FAIL > 0L) 1L else 0L, save = "no")
