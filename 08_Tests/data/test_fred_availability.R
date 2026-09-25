# test_fred_availability.R — PIT C11 가용시점 층(S0) 검사 (2026-09-24 신설)
#
# 지키는 것: 02_Infrastructure/data/fred_availability.R(+ .py) 가 판정서 ② 규약대로
#   "관측일이 아니라 가용일로" 결합하는가. 근거 = 04_Research/01_reports/pit_c11_20260924/
#   PIT_C11_verdict_20260924.md §② · §⑤-8(C11 양성 대조 테스트) · decision_register PIT-C11-CONVENTIONS ④.
#
# ★양방향. 양성 대조(판정서 실례가 기대값대로 나오는가)만으로는 부족하다 — 같은 날짜 결합·
#   exposure_return=decision_close·주간 라벨 결합·규칙 파일 변조를 주입했을 때 **빨개지는가**를 함께 잰다.
#   주입이 초록이면 검사가 죽은 것이다(pit.md: 양성 대조 없는 계기는 방어선으로 세지 않는다).
#
# 축: B 양성 대조(공용 픽스처) · C fail-closed · D 위반 주입(돌연변이) · E 실데이터(읽기 전용) · F R↔py 교차
# 쓰기: tempdir() 만. 운영 .cache·원장·로그에 쓰지 않는다.
# 실행: Rscript 08_Tests/data/test_fred_availability.R   (R_ENVIRON_USER=<빈 파일> 권장)

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ROOT))
HELPER    <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
HELPER_PY <- file.path(ROOT, "02_Infrastructure/data/fred_availability.py")
RULES     <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
CASES     <- file.path(ROOT, "08_Tests/fixtures/fred_availability_cases.json")

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

TD <- file.path(tempdir(), paste0("fredavail_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)

cat("=== 전제: 도우미·규칙·픽스처 로드 ===\n")
for (p in c(HELPER, HELPER_PY, RULES, CASES)) chk(paste("존재", basename(p)), file.exists(p), p)
source(HELPER)
options(fred_avail.root = ROOT)                      # 이 사본의 규칙 파일을 쓴다(워크트리 안전)
RL <- fred_avail_rules(RULES)
fx <- fromJSON(CASES, simplifyVector = FALSE)

syn_cal <- local({
  d <- seq(as.Date(fx$calendar$start), as.Date(fx$calendar$end), by = "day")
  d <- d[.fa_iso_wday(d) <= 5L]
  d[!(d %in% as.Date(unlist(fx$calendar$holidays)))]
})
cat(sprintf("  합성 달력 %s ~ %s (%d 거래일)\n", min(syn_cal), max(syn_cal), length(syn_cal)))

# ── 공용 판정기: 주어진 가용일 함수·결합 함수로 픽스처를 돌려 불일치 id 를 돌려준다 ──────────
exp_date <- function(x) if (is.null(x)) as.Date(NA) else as.Date(x)
avail_mismatch <- function(avail_fun, only = NULL) {
  bad <- character(0)
  for (cs in fx$avail_cases) {
    if (!is.null(only) && !(cs$series %in% only)) next
    got <- tryCatch(avail_fun(cs$series, as.Date(cs$obs)), error = function(e) as.Date("1900-01-01"))
    if (!identical(as.character(got), as.character(exp_date(cs$expect)))) bad <- c(bad, cs$id)
  }
  bad
}
join_mismatch <- function(join_fun, only = NULL) {
  bad <- character(0)
  for (cs in fx$join_cases) {
    if (!is.null(only) && !(cs$id %in% only)) next
    sd <- data.table(Date = as.Date(unlist(cs$obs)), Value = as.numeric(unlist(cs$values)))
    got <- tryCatch(join_fun(as.Date(unlist(cs$kr_dates)), sd, cs$series, cs$mode), error = function(e) NULL)
    ok <- !is.null(got) && identical(as.character(got$obs_date), unlist(cs$expect_obs))
    if (ok && !is.null(cs$expect_decision))
      ok <- identical(as.character(got$decision_date), unlist(cs$expect_decision))
    if (!ok) bad <- c(bad, cs$id)
  }
  bad
}
real_avail <- function(sid, obs) fred_avail_date(sid, obs, syn_cal, RL)
real_join  <- function(kd, sd, sid, mode) fred_asof_join(kd, sd, sid, mode, kr_calendar = syn_cal, rules = RL)

cat("\n=== B 양성 대조 — 판정서 ② 실례(공용 픽스처, 손으로 유도한 기대값) ===\n")
for (cs in fx$avail_cases) {
  got <- tryCatch(as.character(real_avail(cs$series, as.Date(cs$obs))), error = function(e) paste("ERR", conditionMessage(e)))
  want <- as.character(exp_date(cs$expect))
  chk(sprintf("%s %s %s → %s", cs$id, cs$series, cs$obs, want), identical(got, want), sprintf("(got %s · %s)", got, cs$why))
}
for (cs in fx$join_cases) {
  b <- join_mismatch(real_join, only = cs$id)
  chk(sprintf("%s %s %s", cs$id, cs$series, cs$mode), length(b) == 0L, cs$why)
}
for (cs in fx$join_core_cases) {
  got <- .fa_join_idx(as.integer(unlist(cs$dec)),
                      as.integer(unlist(cs$obs)),
                      as.integer(vapply(cs$avail, function(v) if (is.null(v)) NA_integer_ else as.integer(v), 1L)))
  want <- vapply(cs$expect_idx, function(v) if (is.null(v)) NA_integer_ else as.integer(v), 1L)
  chk(sprintf("%s 결합 핵심(지배 관측 제거)", cs$id), identical(as.integer(got), want),
      sprintf("(got %s · %s)", paste(got, collapse = ","), cs$why))
}
chk("B-meta 결합 산출에 규칙 버전·md5 가 실린다",
    identical(attr(real_join(as.Date("2026-09-01"), data.table(Date = as.Date("2026-08-28"), Value = 1), "VIXCLS", "decision_close"), "rules_md5"),
              unname(as.character(tools::md5sum(RULES)))))
chk("B-vintage 개정 계열(NFCI)은 vintage_resolved=FALSE",
    isFALSE(real_join(as.Date("2026-09-03"), data.table(Date = as.Date("2026-08-28"), Value = 1), "NFCI", "decision_close")$vintage_resolved))

cat("\n=== C fail-closed — 규칙 없는 계열·금지 계열·모호한 입력은 거부 ===\n")
for (sid in unlist(fx$error_cases)) chk(sprintf("C 거부: %s", sid), raises(real_avail(sid, as.Date("2026-09-01"))))
chk("C DEXKOUS 거부 메시지가 대체 계열 ECOS_KRW_USD 를 가리킨다",
    grepl("ECOS_KRW_USD", tryCatch(fred_series_rule("DEXKOUS", RL), error = function(e) conditionMessage(e)), fixed = TRUE))
chk("C exposure_return 에 비거래일 kr_date(2026-09-24 합성 휴일) → 거부",
    raises(fred_asof_join(as.Date("2026-09-24"), data.table(Date = as.Date("2026-09-21"), Value = 1), "VIXCLS",
                          "exposure_return", kr_calendar = syn_cal, rules = RL)))
chk("C 같은 관측일 2행 → 거부",
    raises(fred_asof_join(as.Date("2026-09-02"), data.table(Date = as.Date(c("2026-08-28", "2026-08-28")), Value = c(1, 2)),
                          "VIXCLS", "decision_close", kr_calendar = syn_cal, rules = RL)))
chk("C Series_ID 가 섞인 입력 → 거부",
    raises(fred_asof_join(as.Date("2026-09-02"), data.table(Date = as.Date(c("2026-08-27", "2026-08-28")), Value = c(1, 2),
                                                            Series_ID = c("VIXCLS", "NFCI")),
                          "VIXCLS", "decision_close", kr_calendar = syn_cal, rules = RL)))
chk("C Series_ID 가 요청과 다른 입력 → 거부",
    raises(fred_asof_join(as.Date("2026-09-02"), data.table(Date = as.Date("2026-08-28"), Value = 1, Series_ID = "NFCI"),
                          "VIXCLS", "decision_close", kr_calendar = syn_cal, rules = RL)))

mut_rules <- function(tag, f) {           # 규칙 파일 사본을 변조해 tempdir 에 쓴다
  raw <- fromJSON(RULES, simplifyVector = FALSE)
  raw <- f(raw)
  p <- file.path(TD, sprintf("rules_%s.json", tag))
  writeLines(toJSON(raw, auto_unbox = TRUE, null = "null", digits = NA, pretty = FALSE), p, useBytes = TRUE)
  p
}
sidx <- function(raw, id) which(vapply(raw$series, function(s) identical(s$id, id), TRUE))
p_novix <- mut_rules("novix", function(r) { r$series[[sidx(r, "VIXCLS")]] <- NULL; r })
chk("C 규칙 파일에서 VIXCLS 삭제 → 결합 거부", raises(fred_avail_date("VIXCLS", as.Date("2026-09-01"), syn_cal, p_novix)))
p_badty <- mut_rules("badtype", function(r) { r$series[[sidx(r, "NFCI")]]$bounds[[1]]$type <- "same_day"; r })
chk("C 알 수 없는 bound type → 규칙 로드 거부", raises(fred_avail_rules(p_badty)))
p_nobasis <- mut_rules("nobasis", function(r) { r$series[[sidx(r, "ICSA")]]$bounds[[1]]$basis <- ""; r })
chk("C 근거(basis) 빈 bound → 규칙 로드 거부", raises(fred_avail_rules(p_nobasis)))
p_alias <- mut_rules("alias", function(r) { r$series[[sidx(r, "NFCI")]]$aliases <- list("VIX"); r })
chk("C 별칭 충돌(NFCI 에 'VIX') → 규칙 로드 거부", raises(fred_avail_rules(p_alias)))
p_status <- mut_rules("status", function(r) { r$series[[sidx(r, "VIXCLS")]]$status <- "draft"; r })
chk("C status 가 active|prohibited 밖 → 규칙 로드 거부", raises(fred_avail_rules(p_status)))

cat("\n=== D 위반 주입 — 돌연변이는 반드시 빨개져야 한다 ===\n")
# D1 같은 날짜 결합(현 D32 빌더·phase6 방식): 가용일 = 관측일
mut_same_date <- function(sid, obs) { fred_series_rule(sid, RL); obs }
b <- avail_mismatch(mut_same_date)
chk("D1 같은 날짜 결합 돌연변이 → 양성 대조가 잡는다", length(b) >= 30L, sprintf("(불일치 %d건: %s)", length(b), paste(head(b, 8), collapse = ",")))
chk("D1a 특히 P01(VIX 08-31→09-01)이 빨개진다", "P01" %in% b)
join_same_date <- function(kd, sd, sid, mode) {              # obs ≤ kr_date 롤 결합(가용일 무시)
  fred_series_rule(sid, RL)
  dec <- if (mode == "exposure_return") fred_decision_date(kd, mode, syn_cal) else kd
  j <- findInterval(as.integer(dec), as.integer(sd$Date)); j[j == 0L] <- NA
  data.table(kr_date = kd, decision_date = dec, obs_date = sd$Date[j], value = sd$Value[j])
}
chk("D1b 같은 날짜 결합 돌연변이 → 결합 대조(J1)가 잡는다", "J1" %in% join_mismatch(join_same_date))
# D2 exposure_return 이 decision_close 와 같음
join_expo_is_dec <- function(kd, sd, sid, mode) real_join(kd, sd, sid, "decision_close")
chk("D2 exposure_return=decision_close 돌연변이 → J2 가 잡는다", "J2" %in% join_mismatch(join_expo_is_dec))
# D3 한국 격자 1행 lag(V-06 기전): 결정일 = 직전 거래일이지만 그날 같은 날짜 결합 → 미국 t−1 이 들어온다
chk("D3 '1행 lag'(직전 거래일에 같은 날짜 결합) 돌연변이 → J2 가 잡는다", "J2" %in% join_mismatch(join_same_date, only = "J2"))
# D4 주간 라벨(관측일) 결합 — NFCI 만 관측일로
mut_weekly_label <- function(sid, obs) if (fred_series_rule(sid, RL)$id %in% c("NFCI", "STLFSI4", "ICSA", "WALCL")) obs else real_avail(sid, obs)
b <- avail_mismatch(mut_weekly_label, only = c("NFCI", "STLFSI4", "ICSA", "WALCL"))
chk("D4 주간 계열 관측일 결합 돌연변이 → 주간 대조 전부 빨강", length(b) >= 7L, sprintf("(불일치 %s)", paste(b, collapse = ",")))
# D5 월간 공표 무시(라벨 결합) — CPI 를 관측일로
mut_monthly_label <- function(sid, obs) if (fred_series_rule(sid, RL)$id %in% c("CPIAUCSL", "INDPRO", "UNRATE")) obs else real_avail(sid, obs)
chk("D5 월간 계열 라벨 결합 돌연변이 → P09·P11·P13 빨강",
    all(c("P09", "P11", "P13") %in% avail_mismatch(mut_monthly_label, only = c("CPIAUCSL", "INDPRO", "UNRATE"))))
# D6 규칙 파일 변조: NFCI 를 라벨+0 하나로 → 실제 함수가 빨개져야 한다
p_nfci0 <- mut_rules("nfci0", function(r) {
  i <- sidx(r, "NFCI"); r$series[[i]]$bounds <- list(list(type = "label_plus_days", days = 0L, basis = "mutant")); r })
chk("D6 규칙 변조(NFCI +6→+0, 공표일 bound 삭제) → P05 빨강",
    "P05" %in% avail_mismatch(function(sid, obs) fred_avail_date(sid, obs, syn_cal, p_nfci0), only = "NFCI"))
p_vix0 <- mut_rules("vix0", function(r) { r$series[[sidx(r, "VIXCLS")]]$bounds[[1]]$n <- 0L; r })
chk("D7 규칙 변조(VIX n=1→0 = 같은 날짜) → P01 빨강",
    "P01" %in% avail_mismatch(function(sid, obs) fred_avail_date(sid, obs, syn_cal, p_vix0), only = "VIXCLS"))
p_ice1 <- mut_rules("ice1", function(r) { i <- sidx(r, "BAMLH0A0HYM2"); r$series[[i]]$bounds <- r$series[[i]]$bounds[1]; r$series[[i]]$bounds[[1]]$n <- 1L; r })
chk("D8 규칙 변조(ICE d+2→d+1, 공표일 bound 삭제) → P16·P17 빨강",
    all(c("P16", "P17") %in% avail_mismatch(function(sid, obs) fred_avail_date(sid, obs, syn_cal, p_ice1), only = "BAMLH0A0HYM2")))
p_noroll <- mut_rules("noroll", function(r) { i <- sidx(r, "NFCI"); r$series[[i]]$bounds <- r$series[[i]]$bounds[1]; r })
chk("D9 규칙 변조(NFCI 미국 휴일 공표 bound 삭제) → P18 빨강",
    "P18" %in% avail_mismatch(function(sid, obs) fred_avail_date(sid, obs, syn_cal, p_noroll), only = "NFCI"))
# r1(b2): CPI 2025-09 override(10-24)는 새 영업일 상한(10월 17번째 = 10-24)과 같아져 P10 으로는 override 삭제가 안 보인다.
#   override 가 규칙보다 늦은 INDPRO 2025-10(12-03 판) = P38 로 옮긴다.
p_noov <- mut_rules("noov", function(r) { r$series[[sidx(r, "INDPRO")]]$release_overrides <- NULL; r })
chk("D10 규칙 변조(INDPRO 셧다운 override 삭제) → P38 빨강",
    "P38" %in% avail_mismatch(function(sid, obs) fred_avail_date(sid, obs, syn_cal, p_noov), only = "INDPRO"))
# D11 위반 탐지기(pit_verify_fred_lag 용) 양방향
kd <- as.Date(c("2026-08-31", "2026-09-01", "2026-09-02"))
v_bad <- fred_join_violations(kd, kd, "VIXCLS", "decision_close", syn_cal, RL)                  # 같은 날짜 쌍
v_ok  <- fred_join_violations(kd, as.Date(c("2026-08-28", "2026-08-31", "2026-09-01")), "VIXCLS", "decision_close", syn_cal, RL)
v_exp <- fred_join_violations(kd, as.Date(c("2026-08-28", "2026-08-31", "2026-09-01")), "VIXCLS", "exposure_return", syn_cal, RL)
chk("D11a 탐지기: 같은 날짜 쌍 3/3 위반", nrow(v_bad) == 3L, sprintf("(%d)", nrow(v_bad)))
chk("D11b 탐지기: PIT 쌍 0 위반(decision_close)", nrow(v_ok) == 0L, sprintf("(%d)", nrow(v_ok)))
chk("D11c 탐지기: 같은 쌍도 exposure_return 에선 3/3 위반(t−1 값은 r_t 에 못 쓴다)", nrow(v_exp) == 3L, sprintf("(%d)", nrow(v_exp)))

cat("\n=== E 실데이터(읽기 전용) — 커버리지·전 이력 무위반·V-08 실값 ===\n")
fm_paths <- file.path(DATA_ROOT, ".cache", c("macro_fred.parquet", "fred_macro.parquet"))
eb_path  <- file.path(DATA_ROOT, ".cache", "ecos_bond_rates.parquet")
cal_path <- file.path(DATA_ROOT, ".cache", "trading_calendar.parquet")
real_ok <- all(file.exists(c(fm_paths, eb_path, cal_path))) && requireNamespace("arrow", quietly = TRUE)
REAL_CAL <- NULL
if (!real_ok) {
  skip("E_real_data", "운영 캐시 부재 — 실데이터 축 미측정(통과 아님)", paste(c(fm_paths, eb_path, cal_path)[!file.exists(c(fm_paths, eb_path, cal_path))], collapse = ";"))
} else {
  rd <- function(p, cols = NULL) {
    x <- as.data.table(arrow::read_parquet(p, as_data_frame = TRUE, mmap = FALSE))   # 일간 경로가 덮어쓰는 파일 — 매핑 금지
    if (!is.null(cols)) x <- x[, cols, with = FALSE]
    x
  }
  ids <- unique(unlist(lapply(fm_paths, function(p) unique(rd(p, "Series_ID")$Series_ID))))
  ecos <- c("ECOS_KRW_USD", unique(rd(eb_path, "Series")$Series))
  have <- names(RL$index)
  miss <- setdiff(c(ids, ecos), have)
  chk(sprintf("E1 데이터 계열 %d종 전수에 규칙 존재(누락 = 결합 불가)", length(c(ids, ecos))), length(miss) == 0L,
      sprintf("(누락: %s)", paste(miss, collapse = ",")))
  chk("E1b 규칙 파일 series 수 ≥ 데이터 계열 수", length(RL$raw$series) >= length(unique(c(ids, ecos))))
  REAL_CAL <- fred_kr_calendar(cal_path)
  fm <- rd(fm_paths[2])
  fm[, Date := as.Date(Date)]
  kr <- REAL_CAL[REAL_CAL >= as.Date("2005-01-03")]
  for (sid in c("VIXCLS", "NFCI", "STLFSI4", "ICSA", "CPIAUCSL", "INDPRO", "BAMLH0A0HYM2", "T10Y2Y", "FEDFUNDS", "UMCSENT")) {
    sd <- fm[Series_ID == sid, .(Date, Value)]
    if (!nrow(sd)) { chk(sprintf("E2 %s 데이터 존재", sid), FALSE); next }
    for (md in c("decision_close", "exposure_return")) {
      j <- fred_asof_join(kr, sd, sid, md, kr_calendar = REAL_CAL, rules = RL)
      jj <- j[!is.na(obs_date)]
      ok <- nrow(jj) > 0L && all(jj$avail_date <= jj$decision_date) && all(jj$obs_date < jj$kr_date)
      if (md == "exposure_return") ok <- ok && all(jj$decision_date < jj$kr_date)
      nv <- nrow(fred_join_violations(jj$kr_date, jj$obs_date, sid, md, REAL_CAL, RL))
      chk(sprintf("E2 %-13s %-15s 전 이력 %d행 가용일 위반 0", sid, md, nrow(jj)), ok && nv == 0L, sprintf("(violations=%d)", nv))
    }
  }
  vix <- fm[Series_ID == "VIXCLS", .(Date, Value)][order(Date)]
  j <- fred_asof_join(as.Date(c("2026-08-31", "2026-09-01")), vix, "VIXCLS", "decision_close", kr_calendar = REAL_CAL, rules = RL)
  chk("E3 V-08 실값: 한국 2026-08-31 결정 VIX = 미국 08-28 14.43", identical(as.character(j$obs_date[1]), "2026-08-28") && isTRUE(all.equal(j$value[1], 14.43)),
      sprintf("(got %s %s)", j$obs_date[1], j$value[1]))
  chk("E3b 미국 08-31 14.92 는 한국 09-01 부터", identical(as.character(j$obs_date[2]), "2026-08-31") && isTRUE(all.equal(j$value[2], 14.92)))
  # E4 빌더식 같은 날짜 결합(V-08 기전)을 탐지기가 잡는가 — 한국 월말 × 관측일 ≤ 월말 롤
  me <- REAL_CAL[REAL_CAL >= as.Date("2005-01-01") & REAL_CAL <= as.Date("2026-08-31")]
  me <- me[c(diff(as.integer(format(me, "%m"))) != 0L, TRUE)]
  jr <- findInterval(as.integer(me), as.integer(vix$Date)); jr[jr == 0L] <- NA
  v_same <- fred_join_violations(me, vix$Date[jr], "VIXCLS", "decision_close", REAL_CAL, RL)
  chk(sprintf("E4 빌더식 같은 날짜 결합: 월말 %d개 중 위반 ≥200(판정서: 260개 중 255개가 같은 날짜 VIX)", length(me)),
      nrow(v_same) >= 200L, sprintf("(violations=%d)", nrow(v_same)))
  jp <- fred_asof_join(me, vix, "VIXCLS", "decision_close", kr_calendar = REAL_CAL, rules = RL)
  chk("E4b 같은 월말을 가용일 결합하면 위반 0", nrow(fred_join_violations(jp$kr_date, jp$obs_date, "VIXCLS", "decision_close", REAL_CAL, RL)) == 0L)
  nf <- fm[Series_ID == "NFCI", .(Date, Value)][order(Date)]
  jn <- findInterval(as.integer(kr), as.integer(nf$Date)); jn[jn == 0L] <- NA
  v_nf <- fred_join_violations(kr, nf$Date[jn], "NFCI", "decision_close", REAL_CAL, RL)
  chk(sprintf("E5 NFCI 관측일 LOCF(V-11 기전): 한국 %d일 중 미공표 사용일 다수 탐지", length(kr)),
      nrow(v_nf) > 0.5 * length(kr), sprintf("(violations=%d = %.1f%%, 판정서 V-11 의 59.8%%는 1행 shift 판 기준)", nrow(v_nf), 100 * nrow(v_nf) / length(kr)))
  jn1 <- c(NA_integer_, jn[-length(jn)])                      # V-11 의 '1행 shift' 보정판
  v_nf1 <- fred_join_violations(kr, nf$Date[jn1], "NFCI", "decision_close", REAL_CAL, RL)
  chk("E5b 관측일 LOCF 에 한국 격자 1행 shift 를 걸어도 미공표 사용일이 남는다(1행 lag ≠ 가용일 결합)",
      nrow(v_nf1) > 0.4 * length(kr), sprintf("(violations=%d = %.1f%%; 판정서 V-11 = 59.8%%)", nrow(v_nf1), 100 * nrow(v_nf1) / length(kr)))
  chk("E6 rules_meta md5 = 파일 md5", identical(fred_avail_rules_meta(RULES)$md5, unname(as.character(tools::md5sum(RULES)))))
}

cat("\n=== F R↔py 교차 — 같은 규칙 파일·같은 달력·같은 결과 ===\n")
py <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", ""))
if (!nzchar(py) || !file.exists(gsub("\\\\", "/", py))) py <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")
py <- gsub("\\\\", "/", py)
if (!file.exists(py)) {
  chk("F 파이썬 해석기 존재(QVEST_PY_BIN/QVEST_PY/venv) — 교차 축은 필수", FALSE, py)
} else {
  cal_x <- if (is.null(REAL_CAL)) syn_cal else REAL_CAL
  obs_sweep <- seq(as.Date("2000-01-01"), max(cal_x) + 90L, by = "day")
  active <- Filter(function(s) identical(s$status, "active"), RL$raw$series)
  q <- list(rules_path = RULES, calendar = as.character(cal_x),
            avail = lapply(active, function(s) list(series = s$id, obs = as.character(obs_sweep))),
            join = list(), expect_error = unlist(fx$error_cases))
  if (!is.null(REAL_CAL)) {
    fm <- as.data.table(arrow::read_parquet(fm_paths[2], as_data_frame = TRUE, mmap = FALSE)); fm[, Date := as.Date(Date)]
    kr <- REAL_CAL[REAL_CAL >= as.Date("2005-01-03")]
    for (sid in c("VIXCLS", "NFCI", "CPIAUCSL", "BAMLH0A0HYM2", "UNRATE")) for (md in c("decision_close", "exposure_return")) {
      sd <- fm[Series_ID == sid][order(Date)]
      q$join[[length(q$join) + 1L]] <- list(series = sid, mode = md, kr_dates = as.character(kr),
                                              obs = as.character(sd$Date), values = sd$Value)
    }
  }
  fin <- file.path(TD, "parity_in.json"); fout <- file.path(TD, "parity_out.json")
  writeLines(toJSON(q, auto_unbox = TRUE, digits = NA, null = "null", na = "null"), fin, useBytes = TRUE)
  t0 <- Sys.time()
  so <- suppressWarnings(system2(py, c(shQuote(HELPER_PY), "--parity", shQuote(fin), shQuote(fout)), stdout = TRUE, stderr = TRUE))
  st <- attr(so, "status"); if (is.null(st)) st <- 0L
  chk(sprintf("F0 파이썬 교차 실행 exit 0 (%.1fs)", as.numeric(difftime(Sys.time(), t0, units = "secs"))),
      st == 0L && file.exists(fout), paste(tail(so, 5), collapse = " | "))
  if (st == 0L && file.exists(fout)) {
    res <- fromJSON(fout, simplifyVector = FALSE)
    chk("F1 규칙 md5 동일(R tools::md5sum = py hashlib)", identical(res$meta$md5, RL$md5))
    chk("F1b regime_key 동일", identical(res$meta$regime_key, fred_avail_rules_meta(RULES)$regime_key))
    nd <- 0L; nd_basis <- 0L; bad_series <- character(0)
    calI <- .fa_cal(cal_x)
    for (k in seq_along(res$avail)) {
      a <- res$avail[[k]]; s <- fred_series_rule(a$series, RL)
      rr <- .fa_avail_core(s, as.integer(obs_sweep), calI, RL)
      r_av <- as.character(as.Date(rr$avail)); r_av[is.na(r_av)] <- "NA"
      p_av <- vapply(a$avail, function(v) if (is.null(v)) "NA" else v, "")
      d <- sum(r_av != p_av); nd <- nd + d
      db <- sum(rr$basis != unlist(a$basis)); nd_basis <- nd_basis + db
      if (d > 0L || db > 0L) bad_series <- c(bad_series, a$series)
    }
    chk(sprintf("F2 가용일 전수 동일: %d계열 × %d관측일", length(res$avail), length(obs_sweep)), nd == 0L && nd_basis == 0L,
        sprintf("(불일치 가용일 %d · basis %d · 계열 %s)", nd, nd_basis, paste(bad_series, collapse = ",")))
    if (length(q$join)) {
      nj <- 0L
      for (k in seq_along(q$join)) {
        jq <- q$join[[k]]; jp <- res$join[[k]]
        rj <- fred_asof_join(as.Date(jq$kr_dates), data.table(Date = as.Date(jq$obs), Value = jq$values), jq$series, jq$mode,
                             kr_calendar = cal_x, rules = RL)
        ro <- as.character(rj$obs_date); ro[is.na(ro)] <- "NA"
        po <- vapply(jp$obs_date, function(v) if (is.null(v)) "NA" else v, "")
        rdd <- as.character(rj$decision_date); rdd[is.na(rdd)] <- "NA"
        pdd <- vapply(jp$decision_date, function(v) if (is.null(v)) "NA" else v, "")
        pv <- vapply(jp$value, function(v) if (is.null(v)) NA_real_ else as.numeric(v), 1)
        same_v <- isTRUE(all.equal(rj$value, pv, tolerance = 1e-12))
        if (!(all(ro == po) && all(rdd == pdd) && same_v)) nj <- nj + 1L
      }
      chk(sprintf("F3 실데이터 결합 %d건(계열×모드) R=py", length(q$join)), nj == 0L, sprintf("(불일치 %d건)", nj))
    } else skip("F3_join_parity", "실데이터 부재 — 결합 교차 미측정", "trading_calendar/fred_macro")
    chk("F4 py 도 fail-closed 거부 동일", all(vapply(res$errors, function(e) isTRUE(e$raised), TRUE)) &&
          length(res$errors) == length(fx$error_cases))
    # F5 교차 계기의 양성 대조: py 쪽만 변조 규칙(NFCI +0)으로 돌리면 F2 식 비교가 불일치를 내야 한다
    q5 <- list(rules_path = p_nfci0, calendar = as.character(cal_x),
               avail = list(list(series = "NFCI", obs = as.character(obs_sweep))), join = list(), expect_error = list())
    fin5 <- file.path(TD, "parity_in5.json"); fout5 <- file.path(TD, "parity_out5.json")
    writeLines(toJSON(q5, auto_unbox = TRUE, digits = NA, null = "null", na = "null"), fin5, useBytes = TRUE)
    so5 <- suppressWarnings(system2(py, c(shQuote(HELPER_PY), "--parity", shQuote(fin5), shQuote(fout5)), stdout = TRUE, stderr = TRUE))
    if (file.exists(fout5)) {
      r5 <- fromJSON(fout5, simplifyVector = FALSE)$avail[[1]]
      rr <- .fa_avail_core(fred_series_rule("NFCI", RL), as.integer(obs_sweep), calI, RL)
      r_av <- as.character(as.Date(rr$avail)); r_av[is.na(r_av)] <- "NA"
      p_av <- vapply(r5$avail, function(v) if (is.null(v)) "NA" else v, "")
      chk("F5 교차 계기 양성 대조: py 규칙만 변조하면 불일치가 잡힌다", sum(r_av != p_av) > 1000L,
          sprintf("(불일치 %d)", sum(r_av != p_av)))
    } else chk("F5 교차 계기 양성 대조 실행", FALSE, paste(tail(so5, 3), collapse = " | "))
  }
}

unlink(TD, recursive = TRUE)
cat(sprintf("\n=== 결과: PASS %d · FAIL %d · SKIP %d ===\n", PASS, FAIL, length(SKIPS)))
cat(toJSON(list(test = "fred_availability", pass = PASS, fail = FAIL, skipped = length(SKIPS),
                total = PASS + FAIL, skips = SKIPS), auto_unbox = TRUE), "\n", sep = "")
quit(status = if (FAIL > 0L) 1L else 0L, save = "no")
