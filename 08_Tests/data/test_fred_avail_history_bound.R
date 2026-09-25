# test_fred_avail_history_bound.R — 규칙 파일의 주간·월간 가용일이 과거 실공표일의 '상한'인가 (PIT C11 r1 · 2026-09-24 신설)
#
# 지키는 것: 06_Registry/fred_availability_rules.json 의 고정 규칙(안 B)이 **과거 실공표일보다 늦은** 가용일을 내는가.
#   b1 규칙(판정서 ② 표의 2026 스냅샷 상·하한)은 과거에 상한이 아니었다 — V2(CPI +48 → BLS 실공표 5건 반증) ·
#   V1(INDPRO 2025 셧다운 11-24·12-03) · r1 ALFRED 빈티지 대조(NFCI 휴일 주 104건·FEDFUNDS·DRTSCILM 등).
#   기존 S0 검사(test_fred_availability.R)의 기대값은 같은 규칙 파일에서 손으로 유도해 규칙이 틀려도 같이 틀린다
#   (V2 소견 — E5·E6 가용일 부분이 독립 기준이 아니다). 이 검사의 기대값은 규칙 파일이 아니라 **공표 기관·ALFRED
#   실공표일**(08_Tests/fixtures/fred_release_history_cases.json — 출처 줄 포함)에서 온다.
#
# 판정: 가용일(한국) > 미국 공표일 (미국 공표 시각 = 오전 ET = 한국 밤 → 한국 같은 날짜 15:30 결정은 공표 전).
# ★양방향: 현판 초록 + b1 형태로 되돌린 변조 규칙(보강 bound·override 삭제)을 주입하면 해당 사례가 빨개져야 한다.
# ★postfix(2026-09-24): 공표일 = 빈티지 '날짜'가 아니라 **값의 첫 등장**. b2 의 INDPRO·PERMIT 7건(개정 전용 판을 공표로 셈)을
#   되돌리는 주입(D)이 빨개져야 한다 — H09·H10 의 구 기대값(11-24·12-03)은 틀린 날짜를 정답으로 적어 두었었다.
# 쓰기: tempdir() 만. 운영 .cache 는 한국 거래일 달력만 읽는다(mmap=FALSE).
# 실행: Rscript 08_Tests/data/test_fred_avail_history_bound.R   (R_ENVIRON_USER=<빈 파일> 권장)

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ROOT))
HELPER <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
RULES  <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
CASES  <- file.path(ROOT, "08_Tests/fixtures/fred_release_history_cases.json")
CAL    <- file.path(DATA_ROOT, ".cache/trading_calendar.parquet")

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
finish <- function() {
  cat(sprintf("\n=== 결과: PASS %d · FAIL %d · SKIP %d ===\n", PASS, FAIL, length(SKIPS)))
  cat(toJSON(list(test = "fred_avail_history_bound", pass = PASS, fail = FAIL, skipped = length(SKIPS),
                  total = PASS + FAIL, skips = SKIPS), auto_unbox = TRUE), "\n")
  quit(save = "no", status = if (FAIL > 0L || length(SKIPS) > 0L) 1L else 0L)
}
TD <- file.path(tempdir(), paste0("fahist_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)

cat("=== 전제 ===\n")
for (p in c(HELPER, RULES, CASES, CAL)) chk(paste("존재", basename(p)), file.exists(p), p)
if (FAIL > 0L) finish()
source(HELPER)
options(fred_avail.root = ROOT)
RL <- fred_avail_rules(RULES)
cal <- sort(unique(as.Date(arrow::read_parquet(CAL, col_select = "Date", as_data_frame = TRUE, mmap = FALSE)$Date)))
fx <- fromJSON(CASES, simplifyVector = FALSE)
cs <- rbindlist(lapply(fx$cases, function(x) data.table(id = x$id, series = x$series, obs = as.Date(x$obs),
                                                        us_release = as.Date(x$us_release), source = x$source)))
chk(sprintf("사례 %d건 · 계열 %d종 · 출처 줄 전부 있음", nrow(cs), uniqueN(cs$series)),
    nrow(cs) >= 20L && all(nzchar(cs$source)) && !anyNA(cs$obs) && !anyNA(cs$us_release))
chk("사례의 공표일은 관측 기간 뒤(픽스처 자기 일관성)", all(cs$us_release > cs$obs))
chk("달력이 사례 구간을 덮는다", min(cal) < min(cs$obs) && max(cal) > max(cs$us_release))

# 판정기: 규칙 R 로 각 사례의 가용일 → 가용일 <= 공표일 인 사례 id(= 공표 전 사용)
early_ids <- function(R) {
  bad <- character(0)
  for (i in seq_len(nrow(cs))) {
    a <- fred_avail_date(cs$series[i], cs$obs[i], kr_calendar = cal, rules = R)
    if (is.na(a) || a <= cs$us_release[i]) bad <- c(bad, cs$id[i])
  }
  bad
}

cat("\n=== A. 현판 규칙 = 과거 실공표일의 상한 ===\n")
b0 <- early_ids(RL)
for (i in seq_len(nrow(cs))) {
  a <- fred_avail_date(cs$series[i], cs$obs[i], kr_calendar = cal, rules = RL)
  chk(sprintf("A %s %s %s → 미국 공표 %s · 규칙 가용(한국) %s", cs$id[i], cs$series[i], cs$obs[i], cs$us_release[i], a),
      !is.na(a) && a > cs$us_release[i])
}

cat("\n=== B. 위반 주입: b1 형태로 되돌린 규칙은 빨개져야 한다 ===\n")
mut_rules <- function(tag, f) {
  r <- fromJSON(RULES, simplifyVector = FALSE)
  r <- f(r)
  p <- file.path(TD, paste0("rules_", tag, ".json"))
  writeLines(toJSON(r, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), p, useBytes = TRUE)
  fred_avail_rules(p)
}
sidx <- function(r, id) which(vapply(r$series, function(s) identical(s$id, id), logical(1)))
drop_r1 <- function(r, id, bounds = TRUE, overrides = TRUE) {       # r1 에서 더한 bound·override 만 걷어낸다
  i <- sidx(r, id); s <- r$series[[i]]
  if (bounds) s$bounds <- Filter(function(b) !grepl("^r1 보강", b$basis), s$bounds)
  if (overrides && length(s$release_overrides))
    s$release_overrides <- Filter(function(o) !grepl("r1 보강", o$source, fixed = TRUE), s$release_overrides)
  r$series[[i]] <- s; r
}
ids_of <- function(ser) cs[series == ser, id]
for (m in list(
  list(tag = "cpi_b1",   ser = "CPIAUCSL", f = function(r) drop_r1(r, "CPIAUCSL"),                 why = "CPI 영업일 상한·r1 override 삭제(= b1 +48)"),
  list(tag = "ind_b1",   ser = "INDPRO",   f = function(r) drop_r1(r, "INDPRO"),                   why = "INDPRO 영업일 상한·셧다운 override 삭제"),
  list(tag = "nfci_b1",  ser = "NFCI",     f = function(r) drop_r1(r, "NFCI"),                     why = "NFCI 미국 영업일 bound·override 삭제(= 라벨+6)"),
  list(tag = "icsa_b1",  ser = "ICSA",     f = function(r) drop_r1(r, "ICSA", bounds = FALSE),     why = "ICSA 셧다운 override 삭제"),
  list(tag = "ff_b1",    ser = "FEDFUNDS", f = function(r) drop_r1(r, "FEDFUNDS"),                 why = "FEDFUNDS 영업일 상한 삭제(= 셋째 한국 영업일)"),
  list(tag = "perm_b1",  ser = "PERMIT",   f = function(r) drop_r1(r, "PERMIT"),                   why = "PERMIT 영업일 상한·셧다운 override 삭제(= +54)"),
  list(tag = "drts_b1",  ser = "DRTSCILM", f = function(r) drop_r1(r, "DRTSCILM"),                 why = "DRTSCILM 넷째 달 상한 삭제(= +37)"),
  list(tag = "pcop_b1",  ser = "PCOPPUSDM",f = function(r) drop_r1(r, "PCOPPUSDM"),                why = "PCOPPUSDM 상한·IMF 공백 override 삭제(= +51)"),
  list(tag = "walcl_b1", ser = "WALCL",    f = function(r) drop_r1(r, "WALCL", bounds = FALSE),    why = "WALCL 지연 override 삭제"))) {
  R2 <- mut_rules(m$tag, m$f)
  red <- intersect(early_ids(R2), ids_of(m$ser))
  chk(sprintf("B %s: %s → %s 사례 빨강 %d/%d", m$tag, m$why, m$ser, length(red), length(ids_of(m$ser))), length(red) >= 1L,
      "(주입이 초록 = 검사가 그 축을 못 본다)")
}
# 달력 형태: 가용일을 미국 공표일 '당일'로 두는 규칙(kr_rule on_or_after·days 0)은 반드시 빨개져야 한다(판정 부등호 대조)
R3 <- mut_rules("same_day", function(r) {
  i <- sidx(r, "CPIAUCSL")
  r$series[[i]]$bounds <- list(list(type = "label_plus_days", days = 0L, basis = "mutant same-day"))
  r$series[[i]]$release_overrides <- NULL; r })
chk("B same_day: CPI 를 라벨 당일 가용으로 → CPI 사례 전부 빨강",
    all(ids_of("CPIAUCSL") %in% early_ids(R3)))

cat("\n=== D. 위반 주입: postfix 값 대조 override(b3)를 b2 로 되돌리면 빨개져야 한다 ===\n")
# b2 결함 재현(postfix 2026-09-24): r1 은 빈티지 '날짜'만 보고 개정 전용 판(값 없는 판)을 공표로 셌다 —
#   INDPRO 2025-09 → 11-24(연간 개정판) · 2025-10 → 12-03(9월분 판) · PERMIT 2025-11 → 01-09(2025-10 에서 끝난 판),
#   PERMIT 2019-01·2025-12·2026-01·2026-02 는 override 가 없어 M+1월 21번째 미국 영업일 상한이 공표보다 일렀다.
POSTFIX_IDS <- c("H09", "H10", "H29", "H30", "H31", "H32", "H33")
chk(sprintf("D0 픽스처에 postfix 값 대조 사례 %d건이 있다", length(POSTFIX_IDS)),
    all(POSTFIX_IDS %in% cs$id) && all(grepl("^postfix 값 대조", cs[id %in% POSTFIX_IDS, source])))
is_pf <- function(o) grepl("^postfix 값 대조", o$source)
b2_revert <- function(r) {
  back <- list(INDPRO = c("2025-09-01" = "2025-11-24", "2025-10-01" = "2025-12-03"),
               PERMIT = c("2025-11-01" = "2026-01-09"))
  for (sid in c("INDPRO", "PERMIT")) {
    i <- sidx(r, sid); ov <- r$series[[i]]$release_overrides
    keep <- list()
    for (o in ov) {
      if (!is_pf(o)) { keep[[length(keep) + 1L]] <- o; next }
      b <- back[[sid]][o$obs]
      if (!is.na(b)) keep[[length(keep) + 1L]] <- list(obs = o$obs, us_release = unname(b), source = "mutant b2 revert")
    }
    r$series[[i]]$release_overrides <- keep
  }
  r
}
R4 <- mut_rules("b2_revert", b2_revert)
red4 <- early_ids(R4)
chk(sprintf("D1 b2 되돌림(override 3건 원값 · 4건 삭제) → postfix 사례 %d/%d 빨강", length(intersect(red4, POSTFIX_IDS)), length(POSTFIX_IDS)),
    all(POSTFIX_IDS %in% red4), sprintf("(빨강 %s)", paste(red4, collapse = ",")))
chk("D1b b2 되돌림이 다른 사례를 빨갛게 하지 않는다(주입 범위 = postfix 7건)", length(setdiff(red4, POSTFIX_IDS)) == 0L,
    sprintf("(범위 밖 빨강 %s)", paste(setdiff(red4, POSTFIX_IDS), collapse = ",")))
R5 <- mut_rules("pf_drop", function(r) {
  for (sid in c("INDPRO", "PERMIT")) {
    i <- sidx(r, sid); r$series[[i]]$release_overrides <- Filter(Negate(is_pf), r$series[[i]]$release_overrides)
  }
  r })
red5 <- early_ids(R5)
chk(sprintf("D2 postfix override 만 삭제 → postfix 사례 %d/%d 빨강", length(intersect(red5, POSTFIX_IDS)), length(POSTFIX_IDS)),
    all(POSTFIX_IDS %in% red5), sprintf("(빨강 %s)", paste(red5, collapse = ",")))

cat("\n=== C. 규칙 파일 메타 — 보강 판(b2 이상)·대조 기록 ===\n")
raw <- fromJSON(RULES, simplifyVector = FALSE)
chk(sprintf("규칙 version=%s 가 b1 이 아니다", raw$version), !identical(raw$version, "2026-09-24.b1"))
chk(sprintf("규칙 version=%s 가 b2(값 대조 전 · INDPRO·PERMIT 7건 공표 전 사용)가 아니다", raw$version),
    !identical(raw$version, "2026-09-24.b2"))
chk("history_check 가 '위반 0'을 날짜 창 기준 그대로 주장하지 않는다 + 값 대조(b3_value_check) 기록 존재",
    !is.null(raw$history_check$b2_violations) && !grepl("^0", as.character(raw$history_check$b2_violations)) && is.list(raw$history_check$b3_value_check) &&
      length(raw$history_check$b3_value_check$evidence) >= 1L)
chk("history_check 기록(방법·증거·범위) 존재", is.list(raw$history_check) && length(raw$history_check$evidence) >= 1L &&
      is.list(raw$history_check$coverage))
chk("history_verified 가 true 로 과장되지 않는다(부분 대조)", !isTRUE(raw$history_verified))

finish()
