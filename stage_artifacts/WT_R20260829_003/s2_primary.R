# S2 — 1급(사전등록) 층화 스프레드 + adv20 층 내부 통제 + 10x3 그리드 (WT-R20260829_003)
#  ★구현 금지 사양(handoff ①): 연속 composite 환원 금지 — 이중정렬 층화만.
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
P <- readRDS(file.path(OUT, "panel.rds"))
FACTORS <- P$FACTORS; TURN <- P$TURN; fwd <- P$fwd; SIZE <- P$SIZE
LIQ_MIN <- 2e8; PPY <- 12L

nw_t1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); if (length(k) < 12L) return(list(alpha_ann=NA,t_alpha=NA,beta=NA,n=length(k)))
  x <- x[k]; b <- b[k]; f <- lm(x ~ b)
  ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  list(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], beta = ct[2,1], t_beta = ct[2,3],
       beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x)) }

## ── 적격집합 (2/20 규약 동일) ────────────────────────────────────────────────
E <- merge(FACTORS[, .(Date, Ticker, mkt, score = Score)],
           TURN[, .(Date, Ticker, turn_form, d_turn)], by = c("Date","Ticker"))
E <- merge(E, fwd$liq_dt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
n_pre <- nrow(E); n_naadv <- sum(is.na(E$adv)); n_noturn <- nrow(FACTORS) - nrow(E)
E <- E[is.na(adv) | adv >= LIQ_MIN]
E <- merge(E, SIZE, by = c("Date","Ticker"), all.x = TRUE)
cat(sprintf("[S2] eligible %d -> %d (turn 결측배제 %d · adv NA pass %d) | 월 중앙 %.0f종\n",
            n_pre, nrow(E), n_noturn, n_naadv, median(E[, .N, by = Date]$N)))

R <- as.data.table(fwd$returns_dt)[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
bench <- as.data.table(fwd$bench_dt)

## ── 층화 축 ─────────────────────────────────────────────────────────────────
E[, mdec  := as.integer(pmin(10L, 1L + floor(frank(score, ties.method="first")/(.N+1e-9)*10))), by = Date]
E[, tr    := (frank(turn_form, ties.method="average") - 0.5)/.N, by = .(Date, mkt)]
E[, vter  := as.integer(pmin(3L, 1L + floor(tr*3)))]
E[, advt  := as.integer(pmin(3L, 1L + floor((frank(adv, ties.method="average", na.last="keep")-0.5)/sum(is.finite(adv))*3))), by = Date]
E[, size_pct := (frank(-Size, ties.method="average")-0.5)/.N, by = Date]
E[, tr_all := (frank(turn_form, ties.method="average") - 0.5)/.N, by = Date]

ER <- merge(E, R, by = c("Date","Ticker"))
cat(sprintf("[S2] panel with returns: %d rows · %d months\n", nrow(ER), uniqueN(ER$Date)))

## ── 교란 진단 0 ─────────────────────────────────────────────────────────────
cor_axes <- E[is.finite(turn_form) & turn_form > 0 & is.finite(Size) & is.finite(adv),
              .(rho_size = cor(tr, size_pct, method="spearman"),
                rho_adv  = cor(tr, frank(adv)/.N, method="spearman"),
                rho_mkt_dummy = cor(tr_all, as.integer(mkt=="KQ150"), method="spearman"),
                rho_mktint_dummy = cor(tr, as.integer(mkt=="KQ150"), method="spearman")), by = Date]
axes_summary <- as.list(colMeans(cor_axes[, -1], na.rm = TRUE))
axes_summary$note <- "rho_mkt_dummy(혼합 랭킹) vs rho_mktint_dummy(시장-내 랭킹) 대비 = LS2000 Nasdaq 배제의 KR 대응 실증. size_pct 0=최대형이므로 rho_size>0 이면 고회전=소형."

## ── 교란 진단 1: 층 내부 회전율 분산 선측정 ─────────────────────────────────
W10 <- E[mdec == 10L]
disp <- W10[is.finite(turn_form) & turn_form > 0,
            .(n = .N, sd_log_turn = sd(log(turn_form)), iqr_log_turn = IQR(log(turn_form))),
            by = .(Date, mkt, advt)]
disp_all <- E[is.finite(turn_form) & turn_form > 0, .(n=.N, sd_log_turn = sd(log(turn_form))), by = .(Date, mkt)]
dispersion <- list(
  winner_x_advt_x_mkt = as.list(disp[, .(cells = .N, n_median = median(n), n_min = min(n),
                                         sd_log_turn_median = median(sd_log_turn, na.rm=TRUE),
                                         iqr_log_turn_median = median(iqr_log_turn, na.rm=TRUE))]),
  universe_x_mkt = as.list(disp_all[, .(n_median = median(n), sd_log_turn_median = median(sd_log_turn, na.rm=TRUE))]),
  retention_ratio = median(disp$sd_log_turn, na.rm=TRUE) / median(disp_all$sd_log_turn, na.rm=TRUE),
  verdict_rule = "retention_ratio 붕괴(<0.3) 또는 n_median<6 이면 층 내부 검정력 부족 -> '미결' 라벨")

## ── 1급 (사전등록) ──────────────────────────────────────────────────────────
cellret <- function(dt, minn = 3L) dt[, .(r = mean(Ret_1m), n = .N), by = Date][n >= minn]
mk_spread <- function(dt_lo, dt_hi, minn = 3L) {
  a <- cellret(dt_lo, minn); b <- cellret(dt_hi, minn)
  m <- merge(a, b, by = "Date", suffixes = c("_lo","_hi"))
  m <- merge(m, bench[, .(Date, BM_Ret)], by = "Date")
  m[, sp := r_lo - r_hi][order(Date)] }
SP_win <- mk_spread(ER[mdec == 10L & vter == 1L], ER[mdec == 10L & vter == 3L])
primary <- list(
  definition = "R10V1 - R10V3 : 승자 데실 내부, 형성기 일평균 회전율 시장-내 랭킹 저층(V1) - 고층(V3) 의 forward 1M EW 수익 차. 독립 2-way(LS2000 절차).",
  metric_basis = "gross (신호 수준 스프레드 — 매매 미발생. 소비형 순수익 판정은 S4)",
  n_months = nrow(SP_win), mean_monthly = mean(SP_win$sp), mean_ann = 12*mean(SP_win$sp),
  sd_monthly = sd(SP_win$sp), nw_t = nw_t1(SP_win$sp),
  beta_controlled = beta_alpha(SP_win$sp, SP_win$BM_Ret),
  cell_n_lo_median = median(SP_win$n_lo), cell_n_hi_median = median(SP_win$n_hi),
  hit_rate = mean(SP_win$sp > 0))

## ── 1급-통제판: adv20 층 내부 ───────────────────────────────────────────────
W <- ER[mdec == 10L]
W[, tr_in := (frank(turn_form, ties.method="average") - 0.5)/.N, by = .(Date, mkt, advt)]
W[, half_in := fifelse(tr_in <= 0.5, "lo", "hi")]
strat_by <- W[, .(r = mean(Ret_1m), n = .N), by = .(Date, advt, half_in)]
strat_w <- dcast(strat_by, Date + advt ~ half_in, value.var = c("r","n"))
strat_w <- strat_w[is.finite(r_lo) & is.finite(r_hi) & n_lo >= 3L & n_hi >= 3L]
strat_w[, sp := r_lo - r_hi]
STRAT <- strat_w[, .(sp = mean(sp), k_strata = .N), by = Date][k_strata >= 2L][order(Date)]
STRAT <- merge(STRAT, bench[, .(Date, BM_Ret)], by = "Date")
per_stratum <- strat_w[, .(n_months = .N, mean_ann = 12*mean(sp), nw_t = nw_t1(sp),
                           n_lo_med = as.numeric(median(n_lo)), n_hi_med = as.numeric(median(n_hi))), by = advt][order(advt)]
primary_stratified <- list(
  definition = "adv20 터사일 층 내부에서 (Date,mkt,advt) 재랭킹 중앙값 분할 저회전-고회전 스프레드 -> 층 평균(등가중). 유동성 축 기계적 통제(결과량 층화).",
  n_months = nrow(STRAT), mean_ann = 12*mean(STRAT$sp), sd_monthly = sd(STRAT$sp),
  nw_t = nw_t1(STRAT$sp), beta_controlled = beta_alpha(STRAT$sp, STRAT$BM_Ret),
  hit_rate = mean(STRAT$sp > 0),
  per_stratum = lapply(split(per_stratum, per_stratum$advt), as.list),
  advt_note = "advt 1=최저 거래대금 층 · 3=최고")

## ── 10x3 그리드 ─────────────────────────────────────────────────────────────
grid <- ER[, .(r_ann = 12*mean(Ret_1m), n_obs = .N), by = .(mdec, vter)][order(mdec, vter)]
grid_monthly <- ER[, .(r = mean(Ret_1m), n = .N), by = .(Date, mdec, vter)][n >= 3L]
gtests <- rbindlist(lapply(c(1L,5L,10L), function(dd) {
  a <- grid_monthly[mdec == dd & vter == 1L, .(Date, r1 = r)]
  b <- grid_monthly[mdec == dd & vter == 3L, .(Date, r3 = r)]
  m <- merge(a, b, by = "Date"); m[, d := r1 - r3]
  data.table(mdec = dd, n = nrow(m), v1_minus_v3_ann = 12*mean(m$d), nw_t = nw_t1(m$d)) }))
mono_win <- grid[mdec == 10L][order(vter)]$r_ann

## ── 혼합 랭킹 대조 ──────────────────────────────────────────────────────────
EM <- copy(ER); EM[, vter_mix := as.integer(pmin(3L, 1L + floor(tr_all*3)))]
SP_mix <- mk_spread(EM[mdec == 10L & vter_mix == 1L], EM[mdec == 10L & vter_mix == 3L])
mixed_rank_control <- list(
  mean_ann = 12*mean(SP_mix$sp), nw_t = nw_t1(SP_mix$sp), n_months = nrow(SP_mix),
  kq_share_V1 = EM[mdec==10L & vter_mix==1L, mean(mkt=="KQ150")],
  kq_share_V3 = EM[mdec==10L & vter_mix==3L, mean(mkt=="KQ150")],
  kq_share_V1_mktint = ER[mdec==10L & vter==1L, mean(mkt=="KQ150")],
  kq_share_V3_mktint = ER[mdec==10L & vter==3L, mean(mkt=="KQ150")],
  note = "혼합 랭킹은 V 분위가 시장 더미로 오염된다(KQ150 비중 격차). 시장-내 랭킹이 그것을 제거하는지 실측.")

## ── 검정력 계약 ─────────────────────────────────────────────────────────────
pw <- function(sd_m, n, implied_monthly, series) {
  re <- required_effect(n = n, t_threshold = 2.0, sd_monthly = sd_m, design = "full", series = series)
  mde80 <- re$required_monthly * (2.8016/2.0); ratio <- implied_monthly/mde80
  list(n = n, sd_monthly = sd_m, nw_inflation = re$nw_inflation, nw_inflation_source = re$nw_inflation_source,
       mde80_monthly = mde80, implied_monthly = implied_monthly, ratio = ratio,
       expected_t = ratio*2.8016, power = pnorm(ratio*2.8016 - 1.96)) }
LS_IMPLIED <- c(low = 0.0006, mid = 0.0012, high = 0.0018)
power_primary <- lapply(LS_IMPLIED, function(v) pw(sd(SP_win$sp), nrow(SP_win), v, SP_win$sp))
power_stratified <- lapply(LS_IMPLIED, function(v) pw(sd(STRAT$sp), nrow(STRAT), v, STRAT$sp))

res <- list(
  meta = list(wt_id = "WT-R20260829_003", as_of = "2026-08-29", metric_type = "canonical_screen_diag",
              liq_ruler = fwd$liq_ruler, liq_ruler_source = fwd$liq_ruler_source, liq_min = LIQ_MIN,
              n_months = uniqueN(ER$Date), elig_median = median(E[, .N, by=Date]$N),
              window = paste(as.character(range(ER$Date)), collapse = " ~ "),
              turnover_definition = "LS2000 원정의 — 일별 거래주식수/상장주식수 = Vol*Close/Size, 형성기(t-2..t-7) 월평균의 평균. 시장-내(K200/KQ150 별도) 백분위 랭킹.",
              composite_prohibition = "연속 composite(mom rank - turnover rank) 미구현 — 이중정렬 층화만(handoff 승계조건 ①)"),
  confound_axes = axes_summary,
  dispersion_precheck = dispersion,
  primary_preregistered = primary,
  primary_adv20_stratified = primary_stratified,
  grid_10x3 = list(cells = lapply(split(grid, seq_len(nrow(grid))), as.list),
                   winner_row_v1_v2_v3_ann = mono_win,
                   decile_tests = lapply(split(gtests, seq_len(nrow(gtests))), as.list)),
  mixed_rank_control = mixed_rank_control,
  power = list(primary = power_primary, stratified = power_stratified,
               anchor_source = "LS2000 Table II/VI 승자 사이드 V1-V3 Year-1: J=6 K=3 +0.06%/mo · J=9 +0.18%/mo"))
write_json(res, file.path(OUT, "s2_primary.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(E = E, ER = ER, R = R, bench = bench, SP_win = SP_win, STRAT = STRAT, W = W, SIZE = SIZE),
        file.path(OUT, "s2_objects.rds"))

cat("\n===== confound axes (mean monthly Spearman) =====\n")
cat(sprintf("rho(tr,size_pct)=%+.3f  rho(tr,adv_rank)=%+.3f  rho(tr_mixed,KQ)=%+.3f  rho(tr_mktint,KQ)=%+.3f\n",
            axes_summary$rho_size, axes_summary$rho_adv, axes_summary$rho_mkt_dummy, axes_summary$rho_mktint_dummy))
cat("\n===== dispersion precheck =====\n")
cat(sprintf("winner x advt x mkt: n_med=%.0f (min %d) sd(log turn) med=%.3f | universe sd med=%.3f | retention=%.3f\n",
            dispersion$winner_x_advt_x_mkt$n_median, dispersion$winner_x_advt_x_mkt$n_min,
            dispersion$winner_x_advt_x_mkt$sd_log_turn_median, dispersion$universe_x_mkt$sd_log_turn_median,
            dispersion$retention_ratio))
cat("\n===== PRIMARY =====\n")
cat(sprintf("R10V1-R10V3 : n=%d %+.2f%%/yr NW-t=%+.3f | b-ctl a=%+.2f%%/yr t=%+.3f b=%+.2f | hit=%.3f cell n=%.0f/%.0f\n",
            primary$n_months, 100*primary$mean_ann, primary$nw_t,
            100*primary$beta_controlled$alpha_ann, primary$beta_controlled$t_alpha, primary$beta_controlled$beta,
            primary$hit_rate, primary$cell_n_lo_median, primary$cell_n_hi_median))
cat(sprintf("adv20-strat : n=%d %+.2f%%/yr NW-t=%+.3f | b-ctl a=%+.2f%%/yr t=%+.3f\n",
            primary_stratified$n_months, 100*primary_stratified$mean_ann, primary_stratified$nw_t,
            100*primary_stratified$beta_controlled$alpha_ann, primary_stratified$beta_controlled$t_alpha))
print(per_stratum)
cat("\n===== 10x3 GRID (ann %) =====\n")
gg <- dcast(grid, mdec ~ vter, value.var = "r_ann"); for (j in 2:4) set(gg, j = j, value = round(100*gg[[j]], 2))
print(gg)
cat("\n===== decile V1-V3 =====\n"); print(gtests)
cat("\n===== mixed-rank control =====\n")
cat(sprintf("mixed %+.2f%%/yr t=%+.3f | KQ share V1 %.3f vs V3 %.3f || mkt-internal: V1 %.3f vs V3 %.3f\n",
            100*mixed_rank_control$mean_ann, mixed_rank_control$nw_t,
            mixed_rank_control$kq_share_V1, mixed_rank_control$kq_share_V3,
            mixed_rank_control$kq_share_V1_mktint, mixed_rank_control$kq_share_V3_mktint))
cat("\n===== POWER =====\n")
for (k in names(power_primary)) cat(sprintf("primary %-4s implied=%.5f MDE80=%.5f ratio=%.4f E[t]=%.3f power=%.3f\n",
  k, power_primary[[k]]$implied_monthly, power_primary[[k]]$mde80_monthly, power_primary[[k]]$ratio,
  power_primary[[k]]$expected_t, power_primary[[k]]$power))
for (k in names(power_stratified)) cat(sprintf("strat   %-4s implied=%.5f MDE80=%.5f ratio=%.4f E[t]=%.3f power=%.3f\n",
  k, power_stratified[[k]]$implied_monthly, power_stratified[[k]]$mde80_monthly, power_stratified[[k]]$ratio,
  power_stratified[[k]]$expected_t, power_stratified[[k]]$power))
