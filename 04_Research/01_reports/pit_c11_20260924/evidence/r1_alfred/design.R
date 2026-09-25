# 읽기 전용 설계: ALFRED 빈티지 목록 → 계열별 보수 공표일 R* 와 영업일 상한 n, 잔여 override 목록.
# R*(obs) = 창 (기간끝, 다음 기간끝] 안 마지막 빈티지(개정 전용 빈티지가 공표 앞·뒤 어디에 있든 공표 이상) ·
#           창에 빈티지가 없으면 기간끝 이후 첫 빈티지(공표가 다음 기간으로 밀린 경우).
# 출력: design.json (series → {n, month_offset|kind, overrides[{obs, us_release}], stats})
suppressWarnings(suppressMessages({ library(data.table); library(arrow); library(jsonlite) }))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
options(fred_avail.root = ROOT, fred_avail.data_root = ROOT)
source(file.path(ROOT, "02_Infrastructure/data/fred_availability.R"))
RR <- fred_avail_rules()
m <- as.data.table(read_parquet(file.path(ROOT, ".cache/macro_fred.parquet"), mmap = FALSE)); m[, Date := as.Date(Date)]
hol <- .fa_us_hol_set(as.integer(as.Date("1995-01-01")), as.integer(as.Date("2027-12-31")), RR$us)
month_end <- function(d) as.Date(.fa_month_last(.fa_month_first(d, 0L)))
mon_idx <- function(d) { lt <- as.POSIXlt(d); lt$year * 12L + lt$mon }
# 달 (label 월 + off) 시작부터 x 까지 미국 영업일 수(x 가 영업일이면 x 포함)
bd_from_month <- function(label, off, x) {
  ms <- .fa_month_first(label, off)
  vapply(seq_along(x), function(i) { if (x[i] < ms[i]) return(0L); d <- seq.int(ms[i], x[i]); sum(.fa_is_us_bday(d, hol)) }, 0L)
}
bd_after <- function(a, b) vapply(seq_along(a), function(i) { if (b[i] <= a[i]) return(0L); d <- seq.int(a[i] + 1L, b[i]); sum(.fa_is_us_bday(d, hol)) }, 0L)
known_shut <- list(CPIAUCSL = c("2013-09-01", "2013-10-01", "2025-09-01", "2025-11-01"),
                   INDPRO   = c("2013-09-01", "2025-09-01", "2025-10-01", "2025-11-01"),
                   PERMIT   = c("2013-09-01", "2013-10-01", "2018-12-01", "2019-01-01", "2025-09-01", "2025-10-01", "2025-11-01"),
                   UNRATE   = c("2013-09-01", "2013-10-01", "2025-09-01", "2025-11-01"))
cfg <- list(
  CPIAUCSL  = list(f = "m", off = 1L), INDPRO = list(f = "m", off = 1L), PERMIT = list(f = "m", off = 1L),
  FEDFUNDS  = list(f = "m", off = 1L), PCOPPUSDM = list(f = "m", off = 1L), DRTSCILM = list(f = "q", off = 4L),
  UNRATE    = list(f = "m", off = 1L), M2SL = list(f = "m", off = 1L), UMCSENT = list(f = "m", off = 1L),
  NFCI = list(f = "w"), ICSA = list(f = "w"), WALCL = list(f = "w"), STLFSI4 = list(f = "w"))
res <- list()
for (s in names(cfg)) {
  f <- cfg[[s]]$f
  V <- sort(as.Date(readLines(paste0("vint_", s, ".txt")))); vi <- as.integer(V)
  obs <- sort(unique(m[Series_ID == s & !is.na(Value), Date]))
  pe  <- switch(f, m = month_end(obs), q = as.Date(.fa_month_last(.fa_month_first(obs, 2L))), w = obs)
  npe <- switch(f, m = month_end(pe + 1L), q = as.Date(.fa_month_last(.fa_month_first(pe + 1L, 2L))), w = pe + 7L)
  i1 <- findInterval(as.integer(pe), vi) + 1L; iL <- findInterval(as.integer(npe), vi)
  R1 <- rep(as.Date(NA), length(obs)); ok1 <- i1 <= length(V); R1[ok1] <- V[i1[ok1]]
  RS <- R1; w <- iL >= i1 & ok1; RS[w] <- V[iL[w]]
  cov <- !is.na(R1) & pe >= V[1] & as.integer(R1 - pe) <= 200L
  dt <- data.table(obs, pe, R1, RS, nwin = pmax(iL - i1 + 1L, 0L))[cov]
  if (f %in% c("m", "q")) {
    off <- cfg[[s]]$off
    dt[, moff := mon_idx(RS) - mon_idx(obs)]
    dt[, bd := bd_from_month(as.integer(obs), off, as.integer(RS))]
    ks <- as.Date(unlist(known_shut[[s]]))
    base <- dt[moff == off & nwin == 1L & !(obs %in% ks)]
    n <- max(base$bd)
    # 규칙 가용 미국일 = off 달의 n번째 미국 영업일
    ms <- .fa_month_first(as.integer(dt$obs), off)
    rule_us <- .fa_us_bdays_after(ms - 1L, n, hol)
    dt[, rule_us := as.Date(rule_us)]
    ovr <- dt[RS > rule_us]
    res[[s]] <- list(kind = "month_nth_us_business_day", month_offset = off, n = n,
                     n_obs = nrow(dt), n_unamb = nrow(base), first = format(min(dt$obs)), last = format(max(dt$obs)),
                     overrides = lapply(seq_len(nrow(ovr)), function(i) list(obs = format(ovr$obs[i]), us_release = format(ovr$RS[i]),
                                                                              first_vintage = format(ovr$R1[i]), nwin = ovr$nwin[i])))
    cat(sprintf("%-9s n=%d (월+%d · 비모호 %d/%d) · override %d : %s\n", s, n, off, nrow(base), nrow(dt), nrow(ovr),
                paste(sprintf("%s→%s", ovr$obs, ovr$RS), collapse = " ")))
  } else {
    dt[, bdS := bd_after(as.integer(obs), as.integer(RS))]
    base <- dt[nwin == 1L]
    n <- as.integer(names(which.max(table(base$bdS))))    # 최빈(정규 공표 요일)
    rule_us <- .fa_us_bdays_after(as.integer(dt$obs), n, hol)
    dt[, rule_us := as.Date(rule_us)]
    ovr <- dt[RS > rule_us]
    res[[s]] <- list(kind = "us_business_days_after", n = n, n_obs = nrow(dt), first = format(min(dt$obs)), last = format(max(dt$obs)),
                     bd_table = as.list(table(dt$bdS)),
                     overrides = lapply(seq_len(nrow(ovr)), function(i) list(obs = format(ovr$obs[i]), us_release = format(ovr$RS[i]),
                                                                              first_vintage = format(ovr$R1[i]), nwin = ovr$nwin[i])))
    cat(sprintf("%-9s n=%d (라벨 이후 미국 영업일 · 분포 %s) · override %d : %s\n", s, n,
                paste(names(table(dt$bdS)), table(dt$bdS), sep = ":", collapse = " "), nrow(ovr),
                paste(sprintf("%s→%s", ovr$obs, ovr$RS), collapse = " ")))
  }
}
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE), "design.json")
