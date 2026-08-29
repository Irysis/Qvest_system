# S5 — 기전 부수 관측(실현 공시창 수익률) + advisory 배터리 + PIT 하드 게이트
# WT-R20260829_003
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
P <- readRDS(file.path(OUT, "panel.rds")); DAILY <- P$DAILY
O <- readRDS(file.path(OUT, "s2_objects.rds")); ER <- O$ER; E <- O$E; bench <- O$bench; SIZE <- O$SIZE
S4 <- readRDS(file.path(OUT, "s4_objects.rds"))

nw_t1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }

## ═══ 1. 기전 부수 관측 — 실현 공시창 시장조정 수익률 ═══════════════════════
##   ★C01_SUE 단독 근거 금지(1/20 fail_lookahead_suspected). DART 고정 공시일 규약
##     (연간 익년 3/31 · 분기 5/15·8/15·11/15 — pit.md C4)에 3거래일 창을 잡고
##     실현 (Ret - BM_Ret) 로 측정한다. 사후 실현값 = 신호 미진입 진단.
setorder(DAILY, Date)
tdays <- sort(unique(DAILY$Date)); tidx <- data.table(Date = tdays, di = seq_along(tdays))
D <- merge(DAILY, tidx, by = "Date"); D[, ex := Ret - BM_Ret]
yrs <- sort(unique(year(tdays)))
evc <- rbindlist(lapply(yrs, function(y) data.table(
  cal = as.Date(c(sprintf("%d-03-31", y), sprintf("%d-05-15", y), sprintf("%d-08-15", y), sprintf("%d-11-15", y))),
  kind = c("annual","q1","q2","q3"))))
evc[, ev_date := tdays[findInterval(cal, tdays) + 1L]]     # cal 이후 첫 거래일
evc <- evc[is.finite(as.integer(ev_date))]
evc <- merge(evc, tidx, by.x = "ev_date", by.y = "Date")
CAR <- rbindlist(lapply(seq_len(nrow(evc)), function(i) {
  w <- D[di >= evc$di[i] - 1L & di <= evc$di[i] + 1L, .(car3 = sum(ex)), by = Ticker]
  w[, `:=`(ev_date = evc$ev_date[i], kind = evc$kind[i])][] }))
cat(sprintf("[S5] 공시창 이벤트 %d개 · CAR 관측 %d건\n", nrow(evc), nrow(CAR)))

memb <- ER[mdec == 10L & vter %in% c(1L,3L), .(Date, Ticker, vter)]
mm <- merge(memb, CAR, by = "Ticker", allow.cartesian = TRUE)
mm <- mm[ev_date > Date & ev_date <= Date + 730L]          # 형성 후 8분기(약 2년)
side_by_v <- mm[, .(n = .N, car3_mean = mean(car3), car3_median = median(car3)), by = vter][order(vter)]
## 형성월 단위 집계 후 NW (중첩 인식)
per_form <- dcast(mm[, .(m = mean(car3), n = .N), by = .(Date, vter)], Date ~ vter, value.var = "m")
setnames(per_form, c("Date","V1","V3")); per_form <- per_form[is.finite(V1) & is.finite(V3)]
per_form[, d := V1 - V3]
f <- lm(d ~ 1, data = per_form); ct <- coeftest(f, vcov = NeweyWest(f, lag = 11, prewhite = FALSE))
side_test <- list(
  n_formation_months = nrow(per_form), v1_car3_mean = mean(per_form$V1), v3_car3_mean = mean(per_form$V3),
  diff = mean(per_form$d), nw_lag11_t = as.numeric(ct[1,3]),
  hit_rate = mean(per_form$d > 0),
  spec = "3거래일(공시 고정일 -1..+1) 시장조정 수익 합. 형성 후 8분기 이벤트 전부 평균 -> 형성월별 집계 -> NW lag-11(중첩 24개월).",
  pit_note = "실현 사후 관측(신호 미진입). C01_SUE 미사용 — 1/20 의 정적검증기 FAIL_LOOKAHEAD 축을 우회.",
  interpretation = "LS2000 기전이 참이면 diff>0 (저회전 승자의 후속 공시 반응 우위).")

## 보조: 실현 DART 순이익 성장 (라벨 — 단독 근거 아님)
fg <- tryCatch({
  fq <- as.data.table(read_parquet(".cache/fundamental_dart_quarterly.parquet"))
  fq <- fq[is.finite(NetIncomeGrowth), .(Ticker, Factor_Date = as.Date(Factor_Date), NetIncomeGrowth)]
  z <- merge(memb, fq, by = "Ticker", allow.cartesian = TRUE)
  z <- z[Factor_Date > Date & Factor_Date <= Date + 730L]
  z[, .(n = .N, nig_median = median(NetIncomeGrowth), nig_mean_w = mean(pmax(pmin(NetIncomeGrowth, 2), -2))), by = vter][order(vter)]
}, error = function(e) data.table(note = conditionMessage(e)))

## ═══ 2. Advisory 배터리 ═══════════════════════════════════════════════════
## rank-IC: (a) 모멘텀 점수 (b) 회전율 저층선호(-tr) (c) arm C 정의역 내 모멘텀
ic_m  <- ER[, .(ic = cor(score, Ret_1m, method="spearman")), by = Date]
ic_t  <- ER[, .(ic = cor(-tr,   Ret_1m, method="spearman")), by = Date]
ic_c  <- ER[vter %in% c(1L,2L), .(ic = cor(score, Ret_1m, method="spearman")), by = Date]
icb <- function(x, nm) list(name = nm, rank_ic = mean(x$ic, na.rm=TRUE), ic_sd = sd(x$ic, na.rm=TRUE),
                            icir = mean(x$ic, na.rm=TRUE)/sd(x$ic, na.rm=TRUE),
                            nw_t = nw_t1(x$ic), n = nrow(x))
advisory <- list(momentum_score = icb(ic_m, "M_JT6"), turnover_low_pref = icb(ic_t, "-turnover_rank"),
                 momentum_in_armC_domain = icb(ic_c, "M_JT6 | V1∪V2"))
## 단조성 (10x3 그리드 승자행 · vter 축)
S2J <- fromJSON(file.path(OUT, "s2_primary.json"), simplifyVector = TRUE)
mono <- S2J$grid_10x3$winner_row_v1_v2_v3_ann
advisory$monotonicity_winner_row <- list(v1 = mono[1], v2 = mono[2], v3 = mono[3],
  spearman_rank_vs_ret = cor(1:3, mono, method = "spearman"),
  note = "LS2000 예측은 V1>V2>V3 (단조 감소). 실측 부호 확인용.")
## subperiod stability (arm 별 활성수익 부호 일치율)
arms <- S4$arms
sub <- rbindlist(lapply(names(arms), function(nm) {
  pr <- copy(arms[[nm]]$pr); pr[, act := ret_net - benchmark_ret]
  pr[, per := fifelse(date < as.Date("2014-01-01"), "P1_2005_2013",
              fifelse(date < as.Date("2020-01-01"), "P2_2014_2019", "P3_2020_2026"))]
  pr[, .(arm = nm, active_ann = 12*mean(act), nw_t = nw_t1(act), n = .N), by = per] }))
advisory$subperiod <- lapply(split(sub, seq_len(nrow(sub))), as.list)
advisory$subperiod_stability_armC <- mean(sub[arm=="C_exclude_V3_top25", active_ann] > 0)
## turnover proxy / DSR 진단 / oos_retention 근사
dsr_diag <- function(pr, n_trials) {
  act <- pr$ret_net - pr$benchmark_ret; sr <- mean(act)/sd(act)*sqrt(12); n <- length(act)
  g1 <- mean((act-mean(act))^3)/sd(act)^3; g2 <- mean((act-mean(act))^4)/sd(act)^4
  emax <- (1-0.5772)*qnorm(1-1/max(n_trials,2)) + 0.5772*qnorm(1-1/(max(n_trials,2)*exp(1)))
  sr0 <- emax * sd(act)*sqrt(12)/sqrt(n) * 0 + emax*(sd(act/sd(act))/sqrt(n))*sqrt(12)
  srm <- sr/sqrt(12); sr0m <- sr0/sqrt(12)
  pnorm(((srm - sr0m)*sqrt(n-1))/sqrt(1 - g1*srm + (g2-1)/4*srm^2)) }
oos_ret <- function(pr) {
  act <- pr$ret_net - pr$benchmark_ret; n <- length(act)
  sapply(c(0.55,0.65,0.75), function(f) { k <- floor(n*f)
    is_sr <- mean(act[1:k])/sd(act[1:k]); os_sr <- mean(act[(k+1):n])/sd(act[(k+1):n])
    if (!is.finite(is_sr) || is_sr <= 0) NA_real_ else os_sr/is_sr }) }
advisory$dsr_diagnostic <- setNames(lapply(names(arms), function(nm) dsr_diag(arms[[nm]]$pr, 5L)), names(arms))
advisory$oos_retention_approx <- setNames(lapply(names(arms), function(nm) {
  v <- oos_ret(arms[[nm]]$pr); list(splits = as.list(v), median = median(v, na.rm=TRUE)) }), names(arms))
advisory$turnover_annual <- setNames(lapply(names(arms), function(nm) arms[[nm]]$turnover_annual), names(arms))

## post-neutralization IC (size 중립화 후 회전율 저층선호 IC)
NZ <- merge(ER, SIZE, by = c("Date","Ticker"), suffixes = c("","_y"))
NZ[, lsz := log(pmax(Size, 1))]
NZ[, tr_n := as.numeric(residuals(lm(-tr ~ lsz))), by = Date]
ic_tn <- NZ[, .(ic = cor(tr_n, Ret_1m, method="spearman")), by = Date]
advisory$post_neutralization <- list(pre = mean(ic_t$ic, na.rm=TRUE), post = mean(ic_tn$ic, na.rm=TRUE),
                                     post_nw_t = nw_t1(ic_tn$ic),
                                     retention = mean(ic_tn$ic, na.rm=TRUE)/mean(ic_t$ic, na.rm=TRUE))

## ═══ 3. PIT 하드 게이트 ═══════════════════════════════════════════════════
src <- file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")
pit_gate <- tryCatch({
  source(src)
  files <- c(file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"),
             file.path(OUT, "s1_panel.R"), file.path(OUT, "s2_primary.R"),
             file.path(OUT, "s3_confound.R"), file.path(OUT, "s4_arms.R"), file.path(OUT, "s5_side_pit.R"))
  out <- lapply(files, function(f) { r <- detect_lookahead(f, verbose = FALSE)
    v <- if (is.null(r$violations)) list() else r$violations
    list(file = basename(f), clean = isTRUE(r$clean), scanned = isTRUE(r$scanned),
         n_violations = length(v),
         detail = if (length(v)) utils::head(lapply(v, as.list), 10L) else NULL) })
  list(tool = "detect_lookahead", files = out,
       total_violations = sum(vapply(out, function(z) as.integer(z$n_violations), integer(1))),
       all_clean = all(vapply(out, function(z) isTRUE(z$clean), logical(1))))
}, error = function(e) list(error = conditionMessage(e)))

res <- list(
  meta = list(wt_id = "WT-R20260829_003", metric_type = "canonical_screen_diag"),
  side_observation_announcement_window = list(by_vter = lapply(split(side_by_v, seq_len(nrow(side_by_v))), as.list),
                                              test = side_test),
  side_observation_realized_earnings_growth = list(
    label = "보조 관측 — 단독 근거 아님(1/20 C01_SUE PIT caveat 승계). 실현 DART 순이익성장(사후).",
    by_vter = if ("vter" %in% names(fg)) lapply(split(fg, seq_len(nrow(fg))), as.list) else as.list(fg)),
  advisory_battery = advisory,
  pit_hard_gate = pit_gate)
write_json(res, file.path(OUT, "s5_side_pit.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

cat("\n===== SIDE OBSERVATION (announcement window, realized) =====\n"); print(side_by_v)
cat(sprintf("V1 CAR3=%+.4f%% vs V3=%+.4f%% | diff=%+.4f%% NW(11)-t=%+.3f | hit=%.3f (n_form=%d)\n",
            100*side_test$v1_car3_mean, 100*side_test$v3_car3_mean, 100*side_test$diff,
            side_test$nw_lag11_t, side_test$hit_rate, side_test$n_formation_months))
cat("\n--- realized DART NetIncomeGrowth (보조) ---\n"); print(fg)
cat("\n===== ADVISORY =====\n")
for (k in c("momentum_score","turnover_low_pref","momentum_in_armC_domain"))
  cat(sprintf("%-24s rank_ic=%+.4f icir=%+.3f nw_t=%+.3f n=%d\n", advisory[[k]]$name,
              advisory[[k]]$rank_ic, advisory[[k]]$icir, advisory[[k]]$nw_t, advisory[[k]]$n))
cat(sprintf("winner row V1/V2/V3 ann = %.2f%% / %.2f%% / %.2f%% (spearman %.1f)\n",
            100*mono[1], 100*mono[2], 100*mono[3], advisory$monotonicity_winner_row$spearman_rank_vs_ret))
cat(sprintf("post-neutral IC: pre=%+.4f post=%+.4f (t=%+.3f) retention=%.3f\n",
            advisory$post_neutralization$pre, advisory$post_neutralization$post,
            advisory$post_neutralization$post_nw_t, advisory$post_neutralization$retention))
print(sub)
cat("\n===== PIT GATE =====\n")
if (!is.null(pit_gate$error)) cat("ERROR:", pit_gate$error, "\n") else {
  for (z in pit_gate$files) cat(sprintf("%-26s clean=%s scanned=%s violations=%d\n",
    z$file, z$clean, z$scanned, z$n_violations))
  cat(sprintf("TOTAL violations = %d | all_clean = %s\n", pit_gate$total_violations, pit_gate$all_clean)) }
