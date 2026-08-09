## 위기신호 역방향 — P2: 라벨 ON 조건부 **forward** 벤치수익 (1급 판정량)
## 사전등록: preregistration.json (측정 전 작성). 1급 = forward, 당월은 기전 서술용.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/crisis_contrarian")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

B <- readRDS(file.path(OUT, "p1_bench.rds"))$bench
setorder(B, Date); B[, ym := format(Date, "%Y-%m")]
B[, `:=`(f1 = shift(BM_Ret, 1L, type="lead"),
         f2 = shift(BM_Ret, 2L, type="lead"),
         f3 = shift(BM_Ret, 3L, type="lead"))]
say("벤치 %d개월 · %s ~ %s", nrow(B), min(B$Date), max(B$Date))

## ---- 라벨 적재: 월간 정렬 가능한 것만 -----------------------------------------
labs <- list()
try_load <- function(path, tag) {
  if (!file.exists(path)) { say("  %s 부재", path); return(invisible()) }
  D <- tryCatch(as.data.table(read_parquet(path)), error=function(e) NULL)
  if (is.null(D)) { say("  %s 읽기 실패", path); return(invisible()) }
  say("  --- %s: %d행 · 컬럼 %s", tag, nrow(D), paste(head(names(D), 12), collapse=", "))
  labs[[tag]] <<- D
}
say("=== 라벨 적재 ===")
try_load(".cache/unified_regime_signal.parquet", "unified")
try_load(".cache/msm_hybrid_latest.parquet",     "msm_hybrid")
try_load(".cache/macro_regime.parquet",          "macro")
try_load(".cache/regime_forecast_series.parquet","forecast")

## 각 라벨에서 (ym, state) 추출 — 날짜열·상태열 자동 식별 후 실측 보고
extract <- function(D, tag) {
  dc <- names(D)[vapply(D, function(x) inherits(x,"Date")||inherits(x,"POSIXct"), logical(1))]
  if (!length(dc)) dc <- grep("^(Date|date|dt|DATE|ym)$", names(D), value=TRUE)
  if (!length(dc)) { say("  %s: 날짜열 없음 — 제외", tag); return(NULL) }
  dc <- dc[1]
  cc <- setdiff(names(D), dc)
  ## 상태 후보 = **저-cardinality** 컬럼만 (문자든 수치든 2~8개 수준). YM 같은 키 컬럼 배제.
  cand <- cc[vapply(cc, function(k) {
    u <- uniqueN(D[[k]]); u >= 2L && u <= 8L &&
      (is.character(D[[k]]) || is.factor(D[[k]]) || is.numeric(D[[k]]) || is.logical(D[[k]]))
  }, logical(1))]
  say("  %s: 날짜열=%s · 상태후보(카디널리티 2~8)=%s", tag, dc,
      if (length(cand)) paste(cand, collapse=", ") else "(없음)")
  if (!length(cand)) return(NULL)
  X <- copy(D)
  dv <- X[[dc]]
  parse_dt <- function(v) {
    if (inherits(v, "Date") || inherits(v, "POSIXct")) return(as.Date(v))
    s <- as.character(v)
    ## "YYYY-MM-DD" / "YYYY-MM" / "YYYYMM" 전부 수용 (형식을 가정하지 않고 실측 분기)
    s2 <- ifelse(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", s), substr(s, 1, 10),
          ifelse(grepl("^[0-9]{4}-[0-9]{2}$",        s), paste0(s, "-01"),
          ifelse(grepl("^[0-9]{6}$",                 s),
                 paste0(substr(s,1,4), "-", substr(s,5,6), "-01"), NA_character_)))
    suppressWarnings(as.Date(s2))
  }
  X[, .dt := parse_dt(dv)]
  bad <- mean(is.na(X$.dt))
  if (bad > 0) say("  %s: 날짜 파싱 결측 %.1f%% (샘플 '%s')", tag, bad*100, as.character(dv)[1])
  if (bad == 1) { say("  %s: 날짜 전건 파싱 실패 — 제외(침묵 아님)", tag); return(NULL) }
  X <- X[!is.na(.dt)]
  X[, ym := format(.dt, "%Y-%m")]
  out <- list()
  for (k in cand) {
    Z <- X[, .(v = tail(get(k), 1L)), by = ym]     # 월말값(가장 늦은 관측)
    tb <- sort(table(Z$v), decreasing = TRUE)
    say("    %s::%s 분포 %s", tag, k, paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse=" · "))
    out[[k]] <- Z
  }
  out
}
say("=== 라벨 구조 실측 ===")
EX <- list()
for (tg in names(labs)) EX[[tg]] <- extract(labs[[tg]], tg)

## ---- forward 측정 -------------------------------------------------------------
say("=== ★1급 판정: 라벨 ON 조건부 forward 벤치수익 ===")
rows <- list()
for (tg in names(EX)) {
  if (is.null(EX[[tg]])) next
  for (k in names(EX[[tg]])) {
    Z <- EX[[tg]][[k]]
    M <- merge(B[, .(ym, BM_Ret, f1, f2, f3)], Z, by = "ym")
    states <- unique(M$v); states <- states[!is.na(states)]
    if (length(states) < 2L || length(states) > 8L) next
    for (s in states) {
      on <- !is.na(M$v) & M$v == s          # NA 상태월은 ON 아님 (비교 결과 NA 방지)
      n_on <- sum(on & !is.na(M$f1)); n_off <- sum(!on & !is.na(M$f1))
      if (!is.finite(n_on) || !is.finite(n_off) || n_off < 5L) next
      if (n_on < 5L) next
      d1 <- mean(M$f1[on], na.rm=TRUE) - mean(M$f1[!on], na.rm=TRUE)
      se <- sd(M$f1, na.rm=TRUE) * sqrt(1/n_on + 1/n_off) * 1.25
      rows[[length(rows)+1L]] <- data.table(
        label = paste0(tg, "::", k), state = as.character(s),
        n_on = n_on, n_off = n_off,
        cur_ann = mean(M$BM_Ret[on], na.rm=TRUE)*12*100,
        f1_on_ann = mean(M$f1[on], na.rm=TRUE)*12*100,
        f1_off_ann = mean(M$f1[!on], na.rm=TRUE)*12*100,
        f1_diff_ann = d1*12*100, f1_t = d1/se,
        f2_diff_ann = (mean(M$f2[on],na.rm=TRUE)-mean(M$f2[!on],na.rm=TRUE))*12*100,
        f3_diff_ann = (mean(M$f3[on],na.rm=TRUE)-mean(M$f3[!on],na.rm=TRUE))*12*100,
        required_ann = 2.0*se*12*100)
    }
  }
}
if (!length(rows)) { say("★측정 가능한 (라벨,상태) 셀 0 — 라벨 구조 재확인 필요"); quit(status=0) }
R <- rbindlist(rows)
R[, verdict := fifelse(abs(f1_t) >= 2.0, "SIGNIFICANT",
                fifelse(abs(f1_diff_ann) >= required_ann, "NULL_POWERED", "INCONCLUSIVE_UNDERPOWERED"))]
setorder(R, -f1_diff_ann)
print(R[, .(label, state, n_on, cur_ann=round(cur_ann,1), f1_on_ann=round(f1_on_ann,1),
            f1_diff_ann=round(f1_diff_ann,1), f1_t=round(f1_t,2),
            required_ann=round(required_ann,1), verdict)])

say("=== 요약 ===")
say("  셀 %d · forward 유의(+) %d · forward 유의(−) %d · 검정력미달 %d",
    nrow(R), R[f1_t>=2, .N], R[f1_t<=-2, .N], R[verdict=="INCONCLUSIVE_UNDERPOWERED", .N])
say("  ★당월(cur) 양(+) 이면서 forward 도 양(+) 인 셀: %d", R[cur_ann>0 & f1_diff_ann>0, .N])
say("  ★당월 양(+) 인데 forward 는 음(−) 인 셀(= 거래 불가 함정): %d", R[cur_ann>0 & f1_diff_ann<0, .N])

saveRDS(list(cells = R), file.path(OUT, "p2_results.rds"))
fwrite(R, file.path(OUT, "p2_forward_cells.csv"))
say("=== P2 완료 ===")
