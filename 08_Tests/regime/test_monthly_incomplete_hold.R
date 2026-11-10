# test_monthly_incomplete_hold.R -- 월간 국면 원장이 덜 온 입력으로 만든 달을 동결하지 않는가 (2026-11-10 전수점검)
#
# 지키는 것:
#   월 행의 MSM 은 그 달 일별 값의 평균, KTRI 는 그 달 마지막 가용 행이다. 달이 바뀐 뒤 첫 병합이 지난달 행을 영구 동결하는데,
#   그 시점에 국내 자료가 월말까지 오지 않았으면(리프레시 실패 · 지연) 덜 찬 값이 굳고, 뒤에 맞는 값이 와도 '동결 구간 재서술'로
#   거부된다(append-only). 수리 = 생산자(regime_signal.R)가 '국내 자료 층이 그 달의 마지막 KRX 거래일에 못 미친 달'을 파일 속성
#   input_incomplete_dates 로 남기고, 병합(regime_append_only.R)은 그 달을 동결하지 않고 진행 중 행으로 둔다.
#
# 축:
#   A  월말 거래일 계산(.rs_month_last_session) — 자료와 독립(주말 + 휴장일 등록부) · 불변식 재도출 · 미수록 해 = NA
#   B  생산자 표시 블록 — 층 끝이 월말 거래일에 못 미친 달만 표시 · 닿으면 표시 없음 · 과거 달은 보지 않음 · 층 꺼짐
#   C  병합 — 표시된 달은 동결 보류(행은 실린다) → 입력이 찬 다음 병합에서 맞는 값으로 동결 · 속성 없는 후보는 종전 동작
#   D  [대조] 보류를 끈 경우(allow_incomplete) 덜 찬 값이 굳고, 맞는 값은 재서술로 거부된다 — 이 가드가 막는 사고의 재현
#   E  [위반 주입] 표시 줄 · 보류 줄을 지운 사본은 B · C 를 통과하지 못한다
#
# 방식: 소스에서 함수 · 블록을 그대로 꺼내 실행(재구현 금지). 쓰기 = tempdir() 만(root 인자를 명시한다 — 운영 원장 무접촉).

suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
root <- gsub("\\\\", "/", normalizePath(root, winslash = "/", mustWork = FALSE))

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)
done <- function() {
  cat(sprintf('{"test":"monthly_incomplete_hold","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
  if (sys.nframe() == 0L) quit(save = "no", status = if (fail > 0L) 1L else 0L)
}

SIG <- file.path(root, "02_Infrastructure", "regime", "regime_signal.R")
LIB <- file.path(root, "02_Infrastructure", "regime", "regime_append_only.R")
REG <- file.path(root, "06_Registry", "krx_holidays.json")
UTL <- file.path(root, "02_Infrastructure", "utils", c("atomic_parquet.R", "atomic_json.R"))
if (!all(file.exists(c(SIG, LIB, REG, UTL)))) { ng("대상 소스 · 휴장일 등록부 · 원자적 쓰기 정본 부재"); done() } else {

  sig_lines <- readLines(SIG, warn = FALSE, encoding = "UTF-8")
  # 최상위 함수 정의 하나만 꺼낸다(파일 전체 source 는 config · 캐시를 끌고 온다)
  grab_fn <- function(lines, name, env) {
    ex <- parse(text = lines, keep.source = FALSE)
    for (x in ex) if (is.call(x) && identical(x[[1]], as.name("<-")) && is.name(x[[2]]) && identical(as.character(x[[2]]), name)) eval(x, envir = env)
    exists(name, envir = env, inherits = FALSE)
  }
  E <- new.env(parent = globalenv()); assign("PROJECT_ROOT", root, envir = E)
  if (!grab_fn(sig_lines, ".rs_month_last_session", E)) { ng(".rs_month_last_session 정의 없음"); done() } else {
  mls <- get(".rs_month_last_session", envir = E)

  cat("== A 월말 거래일 ==\n")
  reg <- fromJSON(REG, simplifyVector = FALSE); hol <- as.Date(names(reg$holidays)); yrs <- as.integer(unlist(reg$years))
  yms <- format(seq(as.Date(sprintf("%d-01-01", max(yrs) - 2L)), by = "month", length.out = 36L), "%Y-%m")   # 등록부 마지막 3개 해
  got <- mls(yms)
  is_sess <- function(d) !(as.POSIXlt(d)$wday %in% c(0L, 6L)) & !(d %in% hol)
  inv <- vapply(seq_along(yms), function(i) {
    d <- got[i]; me <- as.Date(cut(as.Date(paste0(yms[i], "-01")) + 31, "month")) - 1
    !is.na(d) && format(d, "%Y-%m") == yms[i] && is_sess(d) && (d == me || !any(is_sess(seq(d + 1, me, by = "day"))))
  }, logical(1))
  chk(all(inv), sprintf("A1 36개 달 불변식 — 그 달 안 · 거래일 · 그 뒤 날은 전부 주말/휴장(위반 %d)", sum(!inv)))
  ye <- sprintf("%d-12", max(yrs)); ye_hol <- as.Date(sprintf("%d-12-31", max(yrs)))
  chk(!(ye_hol %in% hol) || mls(ye) < ye_hol, "A2 연말 휴장(12-31 이 등록부 휴장일)인 해의 12월은 그 앞 거래일")
  chk(is.na(mls(sprintf("%d-06", max(yrs) + 3L))), "A3 등록부 미수록 해 = NA(판정 불가 — 지어내지 않는다)")
  chk(all(is.na(mls(c("2026-11", "2026-12"), reg_path = file.path(tempdir(), "no_such_registry.json")))), "A4 등록부를 못 읽으면 전부 NA")
  chk(is.na(mls("bad-ym")), "A5 형식이 틀린 달 = NA")
  chk(inherits(got, "Date") && length(mls(character(0))) == 0L, "A6 반환 = Date · 빈 입력 = 길이 0")

  cat("== B 생산자 표시 블록 ==\n")
  i0 <- grep("# >>> input-incomplete-flag", sig_lines, fixed = TRUE); i1 <- grep("# <<< input-incomplete-flag", sig_lines, fixed = TRUE)
  if (length(i0) != 1L || length(i1) != 1L || i1 <= i0) { ng("B0 표시 블록 앵커 소실(검사가 대상을 잃음)") } else {
    BLOCK <- sig_lines[(i0 + 1L):(i1 - 1L)]
    ok(sprintf("B0 소스에서 표시 블록 %d줄 추출", length(BLOCK)))
    mk_sig <- function(yms) data.table(YM = yms, Date = as.Date(cut(as.Date(paste0(yms, "-01")) + 31, "month")) - 1)
    run_block <- function(block, yms, msm_end, ktri_end) {
      e <- new.env(parent = E)
      e$signal_dt <- mk_sig(yms)
      e$msm_dt  <- if (is.null(msm_end))  data.table(Date = as.Date(character(0))) else data.table(Date = as.Date(msm_end))
      e$ktri_dt <- if (is.null(ktri_end)) data.table(Date = as.Date(character(0))) else data.table(Date = as.Date(ktri_end))
      invisible(capture.output(eval(parse(text = block), envir = e)))
      attr(e$signal_dt, "input_incomplete_dates")
    }
    Y <- "2026"                                      # 등록부에 실린 해(위 A 가 수록을 확인) — 11월 말일 = 월요일 · 12-31 = 연말 휴장
    need11 <- mls(paste0(Y, "-11")); need12 <- mls(paste0(Y, "-12"))
    m4 <- paste0(Y, c("-08", "-09", "-10", "-11")); m5 <- c(m4, paste0(Y, "-12"))
    e11 <- as.character(as.Date(paste0(Y, "-11-30"))); e12 <- as.character(as.Date(paste0(Y, "-12-31")))
    chk(identical(run_block(BLOCK, m4, need11 - 3, need11 - 3), e11), "B1 층 끝이 11월 말 거래일 3일 전 → 11월 표시(달 바뀐 아침에 자료가 뒤처진 상황)")
    chk(identical(run_block(BLOCK, m4, need11, need11), character(0)), "B2 층 끝 = 11월 말 거래일 → 표시 없음(동결 가능)")
    chk(identical(run_block(BLOCK, m5, as.Date(paste0(Y, "-12-01")), as.Date(paste0(Y, "-12-01"))), e12), "B3 층 끝이 12월 초 → 12월(진행 중)만 표시 · 11월은 아님")
    chk(identical(run_block(BLOCK, m5, as.Date(paste0(Y, "-12-01")), need11 - 3), c(e11, e12)), "B4 한 층(KTRI)만 뒤처져도 그 달 표시(가장 늦은 층 기준)")
    chk(identical(run_block(BLOCK, m4, need11, NULL), character(0)), "B5 KTRI 층 꺼짐 → 켜진 층(MSM)만으로 판정")
    chk(identical(run_block(BLOCK, m4, NULL, NULL), character(0)), "B6 국내 자료 층이 없으면 표시 없음(속성은 빈 문자 벡터)")
    chk(identical(run_block(BLOCK, m4, need11 - 3, need11 - 3)[1], e11) && length(run_block(BLOCK, m4, need11 - 3, need11 - 3)) == 1L,
        "B7 층 끝이 속한 달 앞의 달(8~10월)은 표시하지 않는다")
    mutB <- sub(".inc_need > .inc_lim]", "FALSE]", BLOCK, fixed = TRUE)
    chk(!identical(mutB, BLOCK) && identical(run_block(mutB, m4, need11 - 3, need11 - 3), character(0)), "E1 표시 조건을 지운 사본은 B1 을 놓친다 — B 가 이것을 잡는다")
  }

  cat("== C · D 병합 ==\n")
  TD <- gsub("\\\\", "/", normalizePath(file.path(tempdir(), paste0("mih_", Sys.getpid())), winslash = "/", mustWork = FALSE))
  mk_root <- function(tag) {
    r <- file.path(TD, tag); dir.create(file.path(r, "02_Infrastructure", "utils"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(r, ".cache", "_regime_candidate"), recursive = TRUE, showWarnings = FALSE)
    file.copy(UTL, file.path(r, "02_Infrastructure", "utils"), overwrite = TRUE); r
  }
  KEY <- "fixture_key_v1"; EST <- "fixture_estimator"
  # 후보(재생성본) — 표식 계약을 갖춘 월간 표. nov = 11월 행의 결정값(덜 찬 값 / 맞는 값을 구분하려고 바꾼다)
  mk_cand <- function(r, yms, nov, incomplete = NULL, name = "cand.parquet") {
    dt <- data.table(YM = yms, Date = as.Date(cut(as.Date(paste0(yms, "-01")) + 31, "month")) - 1)
    dt[, `:=`(MSM_Crisis_Prob = 0.1, FRED_MRS = 10, KTRI_Score = 50, VEA_Score = 50, Regime_Score = 20, Category = "Normal", Cash_Pct = 0)]
    dt[YM == "2026-11", `:=`(Regime_Score = nov, Cash_Pct = nov / 100)]
    dt[, avail_date := Date][, c11_regime_key := KEY][, msm_estimator := EST]
    setattr(dt, "c11_avail_regime_key", KEY); setattr(dt, "msm_estimator", EST)
    if (!is.null(incomplete)) setattr(dt, "input_incomplete_dates", as.character(incomplete))
    p <- file.path(r, ".cache", "_regime_candidate", name); arrow::write_parquet(dt, p); p
  }
  load_lib <- function(lines = NULL) { e <- new.env(parent = globalenv())
    if (is.null(lines)) sys.source(LIB, envir = e) else { f <- tempfile(fileext = ".R"); writeLines(lines, f, useBytes = TRUE); sys.source(f, envir = e); unlink(f) }
    e }
  L <- load_lib()
  meta_ft <- function(r) fromJSON(file.path(r, "06_Registry", "regime_published", "regime_signal_monthly_meta.json"))$frozen_through
  pub_nov <- function(r) { x <- as.data.table(arrow::read_parquet(file.path(r, "06_Registry", "regime_published", "regime_signal_monthly_published.parquet"), mmap = FALSE))
    x[format(as.Date(Date), "%Y-%m") == "2026-11"]$Regime_Score }
  M6 <- c("2026-06", "2026-07", "2026-08", "2026-09", "2026-10", "2026-11"); M7 <- c(M6, "2026-12")
  ap <- function(lib, r, as_of, cand, ...) suppressWarnings(lib$regime_ledger_append("monthly", root = r, as_of = as.Date(as_of), candidate = cand, verbose = FALSE, ...))
  # 시나리오: 11-10 초기화 → 12-01 덜 찬 11월(값 31) → 12-02 맞는 11월(값 47)
  scenario <- function(lib, tag, flag = TRUE, ...) {
    r <- mk_root(tag)
    a0 <- ap(lib, r, "2026-11-10", mk_cand(r, M6, 25, if (flag) "2026-11-30" else NULL), init = TRUE)
    a1 <- ap(lib, r, "2026-12-01", mk_cand(r, M6, 31, if (flag) "2026-11-30" else NULL), ...)
    s1 <- list(ft = meta_ft(r), nov = pub_nov(r))
    a2 <- ap(lib, r, "2026-12-02", mk_cand(r, M7, 47, if (flag) "2026-12-31" else NULL), ...)
    list(a0 = a0, a1 = a1, s1 = s1, a2 = a2, ft2 = meta_ft(r), nov2 = pub_nov(r))
  }
  S <- tryCatch(scenario(L, "hold"), error = function(e) e)
  if (inherits(S, "error")) ng(paste("C 시나리오 중단:", conditionMessage(S))) else {
    chk(identical(S$a0$status, 0L) && isTRUE(S$a0$written), "C0 초기화(11-10) 정상 — 11월은 진행 중")
    chk(identical(S$a1$status, 0L) && isTRUE(S$a1$written) && identical(S$a1$held_incomplete, "2026-11-30"), "C1 12-01 병합 정상 · 11월 행을 '입력 미도달 보류'로 보고")
    chk(identical(S$s1$ft, "2026-10-31"), sprintf("C2 동결 경계는 10월 말에 머문다(실제 %s)", S$s1$ft))
    chk(isTRUE(all.equal(S$s1$nov, 31)), "C3 보류된 11월 행은 발행본에 실려 있다(진행 중 행 · 소비자는 잠정값을 본다)")
    chk(identical(S$a2$status, 0L) && length(S$a2$held_incomplete) == 0L && length(S$a2$hard) == 0L, "C4 12-02 병합 — 재서술 경보 없이 정상")
    chk(identical(S$ft2, "2026-11-30") && isTRUE(all.equal(S$nov2, 47)), sprintf("C5 입력이 찬 뒤 11월이 맞는 값(47)으로 동결(경계 %s · 값 %s)", S$ft2, paste(S$nov2, collapse = ",")))
  }
  S0 <- tryCatch(scenario(L, "noattr", flag = FALSE), error = function(e) e)
  if (inherits(S0, "error")) ng(paste("C6 시나리오 중단:", conditionMessage(S0))) else
    chk(identical(S0$s1$ft, "2026-11-30") && length(S0$a1$held_incomplete) == 0L, "C6 속성 없는 후보(구판 생산자)는 종전 동작 — 12-01 에 11월 동결")
  SD <- tryCatch(scenario(L, "allow", allow_incomplete = TRUE), error = function(e) e)
  if (inherits(SD, "error")) ng(paste("D 시나리오 중단:", conditionMessage(SD))) else {
    chk(identical(SD$s1$ft, "2026-11-30") && isTRUE(all.equal(SD$s1$nov, 31)), "D1 [대조] 보류를 끄면 덜 찬 값(31)이 12-01 에 굳는다")
    chk(identical(SD$a2$status, 1L) && isTRUE(all.equal(SD$nov2, 31)), "D2 [대조] 뒤에 온 맞는 값(47)은 '동결 구간 재서술'로 거부되고 틀린 값이 남는다 — 가드가 막는 사고")
  }
  cat("== E 위반 주입(병합) ==\n")
  lib_lines <- readLines(LIB, warn = FALSE, encoding = "UTF-8")
  tgt <- "    held <- completed[Date %in% inc & (is.na(ft0) | Date > ft0)]$Date"
  hit <- which(lib_lines == tgt)
  if (length(hit) != 1L) ng(sprintf("E2 돌연변이 대상 줄이 정확히 1곳이 아님(%d)", length(hit))) else {
    mut <- lib_lines; mut[hit] <- "    held <- as.Date(character(0))"
    LM <- tryCatch(load_lib(mut), error = function(e) e)
    SM <- if (inherits(LM, "error")) LM else tryCatch(scenario(LM, "mut"), error = function(e) e)
    if (inherits(SM, "error")) ng(paste("E2 돌연변이 시나리오 중단:", conditionMessage(SM))) else
      chk(identical(SM$s1$ft, "2026-11-30") && isTRUE(all.equal(SM$nov2, 31)), "E2 보류 줄을 지운 사본은 덜 찬 11월을 굳힌다 — C2 · C5 가 이것을 잡는다")
  }
  unlink(TD, recursive = TRUE)
  done()
  }
}
