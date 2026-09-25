# 읽기 전용: ALFRED 빈티지 목록으로 계열별 공표 위치(미국 영업일 색인)를 프로파일링 → 상한 규칙 설계용.
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
options(fred_avail.root = ROOT, fred_avail.data_root = ROOT)
source(file.path(ROOT, "02_Infrastructure/data/fred_availability.R"))
R <- fred_avail_rules()
m <- as.data.table(read_parquet(file.path(ROOT, ".cache/macro_fred.parquet"), mmap = FALSE)); m[, Date := as.Date(Date)]
month_end <- function(d) as.Date(.fa_month_last(.fa_month_first(d, 0L)))
q_end <- function(d) as.Date(.fa_month_last(.fa_month_first(d, 2L)))
hol <- .fa_us_hol_set(as.integer(as.Date("1995-01-01")), as.integer(as.Date("2027-12-31")), R$us)
# 미국 영업일 색인: 달 M+off 의 몇 번째 미국 영업일인가(첫 영업일 = 1)
bd_index_in_month <- function(x) {
  x <- as.integer(x); ms <- .fa_month_first(x, 0L)
  vapply(seq_along(x), function(i) { d <- seq.int(ms[i], x[i]); sum(.fa_is_us_bday(d, hol)) }, 0L)
}
bd_after <- function(a, b) { # a 이후(엄격) b 까지 미국 영업일 수(b 포함)
  vapply(seq_along(a), function(i) { if (b[i] <= a[i]) return(0L); d <- seq.int(a[i] + 1L, b[i]); sum(.fa_is_us_bday(d, hol)) }, 0L)
}
cfg <- list(CPIAUCSL = "m", INDPRO = "m", PERMIT = "m", UNRATE = "m", FEDFUNDS = "m", M2SL = "m", UMCSENT = "m",
            PCOPPUSDM = "m", DRTSCILM = "q", ICSA = "w", NFCI = "w", STLFSI4 = "w", WALCL = "w")
out <- list()
for (s in names(cfg)) {
  V <- sort(as.Date(readLines(paste0("vint_", s, ".txt"))))
  obs <- sort(unique(m[Series_ID == s & !is.na(Value), Date]))
  pe <- switch(cfg[[s]], m = month_end(obs), q = q_end(obs), w = obs)
  npe <- switch(cfg[[s]], m = month_end(pe + 1L), q = q_end(pe + 1L), w = pe + 7L)
  vi <- as.integer(V)
  i1 <- findInterval(as.integer(pe), vi) + 1L
  R1 <- as.Date(ifelse(i1 <= length(V), vi[pmin(i1, length(V))], NA_integer_))
  iL <- findInterval(as.integer(npe), vi)
  RL <- as.Date(ifelse(iL >= i1, vi[pmax(iL, 1L)], NA_integer_)); RL[is.na(RL)] <- R1[is.na(RL)]
  cov <- !is.na(R1) & pe >= V[1] & as.integer(R1 - pe) <= 150L
  dt <- data.table(series = s, obs = obs, pe = pe, R1 = R1, RL = RL, nwin = iL - i1 + 1L, cov = cov)[cov == TRUE]
  if (cfg[[s]] %in% c("m", "q")) {
    dt[, mo_off1 := (as.POSIXlt(R1)$year * 12L + as.POSIXlt(R1)$mon) - (as.POSIXlt(obs)$year * 12L + as.POSIXlt(obs)$mon)]
    dt[, bd1 := bd_index_in_month(R1)]
    dt[, dom1 := as.POSIXlt(R1)$mday]
  } else {
    dt[, bdA1 := bd_after(as.integer(obs), as.integer(R1))]
    dt[, bdAL := bd_after(as.integer(obs), as.integer(RL))]
  }
  out[[s]] <- dt
  cat(sprintf("\n== %s (%d obs 대조, %s~%s) 창 빈티지 수 분포: %s\n", s, nrow(dt), min(dt$obs), max(dt$obs),
              paste(names(table(dt$nwin)), table(dt$nwin), sep = ":", collapse = " ")))
  if (cfg[[s]] %in% c("m", "q")) {
    cat("  R1 월 오프셋 분포:", paste(names(table(dt$mo_off1)), table(dt$mo_off1), sep = ":", collapse = " "), "\n")
    base_off <- as.integer(names(which.max(table(dt$mo_off1))))
    x <- dt[mo_off1 == base_off]
    cat(sprintf("  기본 오프셋 %d 달의 R1 미국영업일 색인: 최소 %d · 최대 %d · 분위 %s\n", base_off, min(x$bd1), max(x$bd1),
                paste(quantile(x$bd1, c(.5, .9, .99)), collapse = "/")))
    cat("  색인 최댓값 상위:", paste(head(x[order(-bd1)][, sprintf("%s→%s(bd%d)", obs, R1, bd1)], 8), collapse = " "), "\n")
    y <- dt[mo_off1 != base_off]
    if (nrow(y)) cat("  비기본 오프셋:", paste(y[, sprintf("%s→%s(+%dm,bd%d)", obs, R1, mo_off1, bd1)], collapse = " "), "\n")
  } else {
    cat("  라벨 이후 미국영업일(R1):", paste(names(table(dt$bdA1)), table(dt$bdA1), sep = ":", collapse = " "), "\n")
    big <- dt[bdA1 > as.integer(names(which.max(table(dt$bdA1)))) ]
    if (nrow(big)) cat("  기본보다 늦은 주:", paste(big[, sprintf("%s→%s(bd%d)", obs, R1, bdA1)], collapse = " "), "\n")
  }
}
saveRDS(out, "profile.rds")
