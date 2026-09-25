# 읽기 전용: 규칙 파일(인자 1 = 규칙 경로)의 가용일이 ALFRED 최초 공표일(추정)보다 늦은지 전수 대조.
# R1(obs) = 기간 끝(월간 = 말일, 주간 = 라벨일) 이후 첫 ALFRED 빈티지일(미국 날짜).
# 위반 = avail_KR <= R1 (미국 공표 시각은 한국 15:30 이후 → 한국 날짜가 R1 보다 엄격히 뒤여야 한다).
# 모호 = 기간 끝 ~ 다음 기간 끝 사이 빈티지 ≥2 (개정 전용 빈티지가 공표보다 앞설 수 있음 → R1 이 과소일 수 있다).
# ★postfix(2026-09-24) 정정: 날짜 창(R1·R*)은 보수가 아니다 — 개정 전용 판(그 관측 값이 없는 판)을 공표로 세면 이르다
#   (INDPRO 2025-09·10 · PERMIT 2019-01·2025-11·12·2026-01·02 실증). 정본 판정 = 값 대조 모드 violation_V:
#   FV(obs) = 값의 첫 등장(FRED output_type=4 realtime_start · 인자 3 = initial_release.csv) · 위반 = avail_KR <= FV.
#   FV 가 계열의 첫 ALFRED 빈티지와 같으면(백필 — 실공표 아님) 판정하지 않는다. 200일 커버리지 컷은 제거했다
#   (공표가 기간 끝 뒤 200일을 넘긴 IMF·셧다운 공백 관측을 대조에서 빼 버렸다).
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
args <- commandArgs(TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
rules_path <- if (length(args) >= 1) args[1] else file.path(ROOT, "06_Registry/fred_availability_rules.json")
out_csv <- if (length(args) >= 2) args[2] else "viol.csv"
fv_csv <- if (length(args) >= 3) args[3] else file.path("..", "postfix_value", "initial_release.csv")
FV_ALL <- if (file.exists(fv_csv)) { x <- fread(fv_csv); x[, `:=`(obs = as.Date(obs), first_release = as.Date(first_release))]; x } else NULL
if (is.null(FV_ALL)) cat("값 대조 파일 없음(날짜 창만):", fv_csv, "\n")
options(fred_avail.root = ROOT, fred_avail.data_root = ROOT)
source(file.path(ROOT, "02_Infrastructure/data/fred_availability.R"))
R <- fred_avail_rules(rules_path)
cal <- fred_kr_calendar()
m <- as.data.table(read_parquet(file.path(ROOT, ".cache/macro_fred.parquet"), mmap = FALSE))
m[, Date := as.Date(Date)]
ser <- c(CPIAUCSL = "monthly", INDPRO = "monthly", PERMIT = "monthly", UNRATE = "monthly", FEDFUNDS = "monthly",
         M2SL = "monthly", UMCSENT = "monthly", PCOPPUSDM = "monthly", DRTSCILM = "quarterly",
         ICSA = "weekly", NFCI = "weekly", STLFSI4 = "weekly", WALCL = "weekly")
month_end <- function(d) { lt <- as.POSIXlt(d); as.Date(sprintf("%04d-%02d-01", lt$year + 1900L + (lt$mon + 1L) %/% 12L, (lt$mon + 1L) %% 12L + 1L)) - 1L }
q_end <- function(d) { lt <- as.POSIXlt(d); mo <- lt$mon + 3L; as.Date(sprintf("%04d-%02d-01", lt$year + 1900L + mo %/% 12L, mo %% 12L + 1L)) - 1L }
all_out <- list()
for (s in names(ser)) {
  vf <- paste0("vint_", s, ".txt")
  if (!file.exists(vf)) { cat(s, ": 빈티지 목록 없음\n"); next }
  V <- sort(as.Date(readLines(vf)))
  obs <- sort(unique(m[Series_ID == s & !is.na(Value), Date]))
  if (!length(obs)) { cat(s, ": 데이터 없음\n"); next }
  pe <- switch(ser[[s]], monthly = month_end(obs), quarterly = q_end(obs), weekly = obs)
  i1 <- findInterval(as.integer(pe), as.integer(V)) + 1L
  R1 <- V[pmin(i1, length(V))]; R1[i1 > length(V)] <- NA
  nextpe <- switch(ser[[s]], monthly = month_end(pe + 1L), quarterly = q_end(pe + 1L), weekly = pe + 7L)
  nwin <- findInterval(as.integer(nextpe), as.integer(V)) - findInterval(as.integer(pe), as.integer(V))
  av <- fred_avail_date(s, obs, kr_calendar = cal, rules = R)
  iL <- findInterval(as.integer(nextpe), as.integer(V))
  RS <- R1; wS <- !is.na(R1) & iL >= i1; RS[wS] <- V[iL[wS]]      # 창 안 마지막 빈티지(보수)
  covered <- !is.na(R1) & pe >= V[1]                               # postfix: 200일 컷 제거
  dt <- data.table(series = s, obs = obs, period_end = pe, R1 = R1, RS = RS, lag_label = as.integer(R1 - obs),
                   n_vint_window = nwin, avail_kr = av, covered = covered)
  dt[, violation := covered & !is.na(avail_kr) & avail_kr <= R1]
  dt[, violation_S := covered & !is.na(avail_kr) & avail_kr <= RS]
  dt[, avail_na := covered & is.na(avail_kr)]
  fvs <- if (!is.null(FV_ALL)) FV_ALL[series == s] else NULL
  if (!is.null(fvs) && nrow(fvs)) {
    dt[, FV := fvs$first_release[match(obs, fvs$obs)]]
    dt[, fv_backfill := !is.na(FV) & FV == min(fvs$first_release)]
    dt[, violation_V := !is.na(FV) & !fv_backfill & !is.na(avail_kr) & avail_kr <= FV]
  } else dt[, `:=`(FV = as.Date(NA), fv_backfill = NA, violation_V = NA)]
  all_out[[s]] <- dt
  cv <- dt[covered == TRUE]
  cat(sprintf("%-9s obs %d · 대조 %d (%s~%s) · 위반 %d · 모호창(빈티지≥2) %d · label→R1 최대 %d일 · 값 대조 %s\n",
              s, nrow(dt), nrow(cv), min(cv$obs), max(cv$obs), sum(cv$violation), sum(cv$n_vint_window >= 2L),
              max(cv$lag_label),
              if (all(is.na(dt$violation_V))) "없음" else
                sprintf("%d관측 · 위반_V %d", sum(!is.na(dt$FV) & !dt$fv_backfill), sum(dt$violation_V, na.rm = TRUE))))
  if (isTRUE(any(dt$violation_V))) print(dt[violation_V == TRUE, .(obs, FV, avail_kr, R1, RS)])
  if (sum(cv$violation_S)) { cv[, violation := violation_S]; vv <- cv[violation == TRUE]; cat("   위반 lag_label 분포:", paste(names(table(vv$lag_label)), table(vv$lag_label), sep=":", collapse=" "), " · R1 요일:", paste(names(table(weekdays(vv$R1))), table(weekdays(vv$R1)), sep=":", collapse=" "), "
"); print(head(vv[, .(obs, R1, lag_label, n_vint_window, avail_kr)], 12)) }
}
fwrite(rbindlist(all_out), out_csv)
