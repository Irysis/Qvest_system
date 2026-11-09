## test_load_daily_factors.R — 일간 접근자 load_daily_factors 의 방향 정렬 계약(2026-11-09 수리 · decision_register
##   FACTOR-DIRECTION-STORAGE-REPAIR-20261109). 이전에는 이 접근자를 시험하는 검사가 하나도 없었다.
##   ① 부호는 날마다 as-of — 그 날 쓸 수 있던 IC(Usable_Date ≤ 그 날)로 정한다(구판 = 요청 구간 끝 하나 · C1 · C14 위반)
##   ② 일간 · 월간 저장 대응표: same = 그대로 · negated = 부호 반대 · mismatch · 표에 없음 = 정렬 거부(명시 요청 = 오류 · 전 팩터 = 열 제외)
##   ③ 등록부 방향 = 저장값 기준 · IC 가 없으면 등록부로 대체 · registry 모드 = IC 를 보지 않는다
##   ④ 대응표가 없으면 정렬 요청은 멈춘다 · 정렬 없이(align_direction = FALSE)는 원값 그대로
##   돌연변이(소스 텍스트 치환 · 치환 성사 단정): M1 구간 끝 하나로 부호 · M2 대응표 곱 제거 · M3 거부 제거 — 각각 해당 단정이 걸려야 한다
##   합성 자료만 쓴다(운영 .cache 를 읽거나 쓰지 않는다).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
CONN <- file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R")
invisible(capture.output(source(CONN)))
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
quiet <- function(expr) { r <- NULL; invisible(capture.output(r <- tryCatch(expr, error = function(e) structure(conditionMessage(e), class = "err")))); r }
is_err <- function(x) inherits(x, "err")

## ── 합성 환경 ──────────────────────────────────────────────────────────────
TMP <- gsub("\\\\", "/", tempfile("ldf_")); dir.create(file.path(TMP, "daily"), recursive = TRUE)
assign("FACTOR_DB_DIR", TMP, envir = globalenv())                       # IC 방향 디스크 캐시도 여기로
assign("FACTOR_DB_DAILY_DIR", file.path(TMP, "daily"), envir = globalenv())
assign("FACTOR_IC_MONTHLY_PATH", file.path(TMP, "ic.parquet"), envir = globalenv())
assign(".fdc_ic_hist", NULL, envir = globalenv())
FAC <- c("F_SAME", "F_NEG", "F_MIS", "F_ABS", "F_DAILY", "F_REGONLY")
assign(".fdc_registry", list(F_SAME = list(direction = "higher_better"), F_NEG = list(direction = "higher_better"),
                             F_MIS = list(direction = "higher_better"), F_ABS = list(direction = "higher_better"),
                             F_DAILY = list(direction = "higher_better"), F_REGONLY = list(direction = "lower_better")),
       envir = globalenv())
PAR <- file.path(TMP, "parity.json")
write_json(list(schema = "factor_daily_monthly_parity_v1",
                factors = list(F_SAME = list(status = "same"), F_NEG = list(status = "negated"), F_MIS = list(status = "mismatch"),
                               F_DAILY = list(status = "daily_only"), F_REGONLY = list(status = "same"))),
           PAR, auto_unbox = TRUE)
options(qvest.daily_parity_path = PAR)

set.seed(20261109)
days <- seq(as.Date("2020-01-01"), as.Date("2020-03-31"), by = "day"); days <- days[!format(days, "%u") %in% c("6", "7")]
TK <- sprintf("T%02d", 1:60)
RAW <- CJ(Date = days, Ticker = TK)
for (f in FAC) set(RAW, j = f, value = rnorm(nrow(RAW)))
for (ym in unique(format(days, "%Y%m"))) write_parquet(RAW[format(Date, "%Y%m") == ym], file.path(TMP, "daily", sprintf("fdb_daily_%s.parquet", ym)))
## IC: 2017-01 ~ 2020-01 월말 37개 = +0.05 · 2020-02-28 에 크게 음수 → 확장 평균 부호가 2020-02-28 부터 − (as-of 시험)
ud <- c(seq(as.Date("2017-02-01"), as.Date("2020-02-01"), by = "1 month") - 1L, as.Date("2020-02-28"))
IC <- rbindlist(lapply(c("F_SAME", "F_NEG", "F_MIS", "F_ABS", "F_DAILY"), function(f)
  data.table(Factor_Name = f, IC = c(rep(0.05, length(ud) - 1L), -5), Date = ud - 28L, Usable_Date = ud)))
write_parquet(IC, FACTOR_IC_MONTHLY_PATH)
FLIP_DAY <- as.Date("2020-02-28")
rawv <- function(f, d) RAW[Date %in% d][order(Date, Ticker)][[f]]
got  <- function(D, f, d) D[Date %in% d][order(Date, Ticker)][[f]]
pre  <- days[days >= as.Date("2020-02-03") & days < FLIP_DAY]; post <- days[days >= FLIP_DAY & days <= as.Date("2020-03-31")]

## ── 본 시험 ────────────────────────────────────────────────────────────────
run_checks <- function(LDF, tag = "") {
  res <- list()
  e1 <- quiet(LDF(date_range = c("2020-02-01", "2020-03-31"), factors = c("F_SAME", "F_MIS")))
  res$refuse_mis <- is_err(e1) && grepl("F_MIS(mismatch)", e1, fixed = TRUE)
  e2 <- quiet(LDF(date_range = c("2020-02-01", "2020-03-31"), factors = "F_ABS"))
  res$refuse_abs <- is_err(e2) && grepl("F_ABS(absent)", e2, fixed = TRUE)
  A <- quiet(LDF(date_range = c("2020-02-01", "2020-03-31")))
  res$drop_all <- !is_err(A) && !any(c("F_MIS", "F_ABS") %in% names(A)) && all(c("F_SAME", "F_NEG", "F_DAILY", "F_REGONLY") %in% names(A)) &&
    setequal(attr(A, "dropped_parity"), c("F_MIS", "F_ABS"))
  if (is_err(A)) return(res)
  res$asof_same_pre  <- isTRUE(all.equal(got(A, "F_SAME", pre), rawv("F_SAME", pre)))          # as-of 2020-01-31 = +
  res$asof_same_post <- isTRUE(all.equal(got(A, "F_SAME", post), -rawv("F_SAME", post)))       # as-of 2020-02-28 이후 = −
  res$neg_pre  <- isTRUE(all.equal(got(A, "F_NEG", pre), -rawv("F_NEG", pre)))                  # 대응표 negated × (+)
  res$neg_post <- isTRUE(all.equal(got(A, "F_NEG", post), rawv("F_NEG", post)))                 # negated × (−)
  res$reg_fallback <- isTRUE(all.equal(got(A, "F_REGONLY", c(pre, post)), -rawv("F_REGONLY", c(pre, post))))  # IC 없음 → 등록부 lower_better
  res$daily_only <- isTRUE(all.equal(got(A, "F_DAILY", pre), rawv("F_DAILY", pre))) && isTRUE(all.equal(got(A, "F_DAILY", post), -rawv("F_DAILY", post)))
  m <- attr(A, "ic_sign_map")
  res$map_segments <- is.data.table(m) && all(c("asof", "parity", "mult", "base", "sign", "src") %in% names(m)) &&
    setequal(unique(m$asof), as.Date(c("2020-01-31", "2020-02-28")))   # 2/3~2/27 → 1/31 · 2/28~3/31 → 2/28
  R <- quiet(LDF(date_range = c("2020-02-01", "2020-03-31"), factors = c("F_SAME", "F_NEG", "F_REGONLY"), direction = "registry"))
  res$registry_mode <- !is_err(R) && isTRUE(all.equal(got(R, "F_SAME", post), rawv("F_SAME", post))) &&
    isTRUE(all.equal(got(R, "F_NEG", post), -rawv("F_NEG", post))) && isTRUE(all.equal(got(R, "F_REGONLY", pre), -rawv("F_REGONLY", pre)))
  res$pit_upper <- max(A$Date) <= as.Date("2020-03-31") && {
    S <- quiet(LDF(date_range = c("2020-02-01", "2020-02-14"), factors = "F_SAME")); !is_err(S) && max(S$Date) <= as.Date("2020-02-14") }
  res
}

LIVE <- run_checks(load_daily_factors)
chk("① 명시 요청한 mismatch 팩터 = 오류(사유에 이름 · 판정)", LIVE$refuse_mis)
chk("② 대응표에 없는 팩터 = 오류(absent)", LIVE$refuse_abs)
chk("③ 전 팩터 요청 = mismatch · absent 열 제외 + attr dropped_parity", LIVE$drop_all)
chk("④ as-of: 2020-02-28 전 날짜는 그때까지의 IC(+) 부호", isTRUE(LIVE$asof_same_pre))
chk("⑤ as-of: 2020-02-28 부터는 새 IC(−) 부호(구간 끝 하나로 정하지 않음)", isTRUE(LIVE$asof_same_post))
chk("⑥ 대응표 negated = 월간 부호 × −1(앞 구간)", isTRUE(LIVE$neg_pre))
chk("⑦ 대응표 negated = 월간 부호 × −1(뒤 구간)", isTRUE(LIVE$neg_post))
chk("⑧ IC 없음 → 등록부(저장값 기준) lower_better 로 대체", isTRUE(LIVE$reg_fallback))
chk("⑨ daily_only = 대응표 곱 없음(+1) · IC 부호는 그대로", isTRUE(LIVE$daily_only))
chk("⑩ attr ic_sign_map = 구간(asof)별 부호표", isTRUE(LIVE$map_segments))
chk("⑪ registry 모드 = IC 무시 · 등록부 × 대응표", isTRUE(LIVE$registry_mode))
chk("⑫ PIT 상한 — 구간 끝 넘는 행 없음", isTRUE(LIVE$pit_upper))
options(qvest.daily_parity_path = file.path(TMP, "no_such.json"))
e <- quiet(load_daily_factors(ym = 202002, factors = "F_SAME"))
chk("⑬ 대응표 없음 + 정렬 요청 = 멈춤", is_err(e) && grepl("대응표 없음", e, fixed = TRUE))
U <- quiet(load_daily_factors(ym = 202002, factors = c("F_SAME", "F_MIS"), align_direction = FALSE))
chk("⑭ 정렬 없이 = 대응표 없어도 원값 그대로(mismatch 열 포함)", !is_err(U) && isTRUE(all.equal(got(U, "F_MIS", days[format(days, "%Y%m") == "202002"]),
                                                                                        rawv("F_MIS", days[format(days, "%Y%m") == "202002"]))))
options(qvest.daily_parity_path = PAR)

## ── 돌연변이(소스 텍스트 치환 · 치환 성사 단정) ────────────────────────────────
src_ldf <- {
  ex <- parse(CONN, keep.source = TRUE)
  i <- which(vapply(ex, function(z) is.call(z) && identical(as.character(z[[1]]), "<-") && identical(as.character(z[[2]]), "load_daily_factors"), logical(1)))
  stopifnot(length(i) == 1L)
  paste(as.character(attr(ex, "srcref")[[i]]), collapse = "\n")
}
mutant <- function(old, new) {
  n <- lengths(regmatches(src_ldf, gregexpr(old, src_ldf, fixed = TRUE)))
  if (n != 1L) return(structure(sprintf("치환 대상 %d곳(1곳이어야 한다): %s", n, old), class = "err"))
  E <- new.env(parent = globalenv()); eval(parse(text = sub(old, new, src_ldf, fixed = TRUE)), envir = E)
  get("load_daily_factors", envir = E)
}
M1 <- mutant("k <- findInterval(as.numeric(days), as.numeric(ud))",
             "k <- rep(findInterval(as.numeric(max(days)), as.numeric(ud)), length(days))")
M2 <- mutant("m[, `:=`(asof = a, sign = base * mult)]", "m[, `:=`(asof = a, sign = base)]")
M3 <- mutant('refuse <- pm[parity %in% c("mismatch", "no_overlap", "absent"), Factor_Name]', "refuse <- character(0)")
chk("M0 돌연변이 3개 모두 치환 성사(단독 실행 가능한 사본)", is.function(M1) && is.function(M2) && is.function(M3))
if (is.function(M1)) { r <- run_checks(M1); chk("M1 구간 끝 하나로 부호 → ④(as-of 앞 구간) 가 걸린다", !isTRUE(r$asof_same_pre)) }
if (is.function(M2)) { r <- run_checks(M2); chk("M2 대응표 곱 제거 → ⑥ · ⑦(negated) 이 걸린다", !isTRUE(r$neg_pre) && !isTRUE(r$neg_post)) }
if (is.function(M3)) { r <- run_checks(M3); chk("M3 거부 제거 → ①(mismatch 오류) 이 걸린다", !isTRUE(r$refuse_mis)) }

unlink(TMP, recursive = TRUE)
cat(sprintf("\n[test_load_daily_factors] %d passed, %d failed\n", PASS, FAIL))
if (FAIL > 0L) quit(save = "no", status = 1L)
