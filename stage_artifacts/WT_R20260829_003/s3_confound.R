# S3 — 교란 기각 검정 (L-family 직교성 · 결과량 층화 · 누출 귀무 · 절단면 프로파일)
#      + 조건부(승자 내부) 층화 변형 + 이벤트타임 Year1/Year2 수평선
# WT-R20260829_003
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
O <- readRDS(file.path(OUT, "s2_objects.rds")); ER <- O$ER; bench <- O$bench; E <- O$E
L <- readRDS(file.path(OUT, "lfamily.rds"))
CTRLS <- c("L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda")

nw_t1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); if (length(k) < 12L) return(list(alpha_ann=NA,t_alpha=NA,beta=NA,n=length(k)))
  x <- x[k]; b <- b[k]; f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag=3, prewhite=FALSE))
  list(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], beta = ct[2,1], n = length(x)) }
spread_stats <- function(m) list(n_months = nrow(m), mean_ann = 12*mean(m$sp), nw_t = nw_t1(m$sp),
                                 sd_monthly = sd(m$sp), hit_rate = mean(m$sp > 0),
                                 beta_controlled = beta_alpha(m$sp, m$BM_Ret))
## 임의 stratifier(x, 높을수록 '고회전' 방향) 로 승자 데실 층화 스프레드 (저층 - 고층)
sp_from <- function(D, xcol, mode = c("independent","conditional"), minn = 3L) {
  mode <- match.arg(mode); d <- copy(D)[is.finite(get(xcol))]
  if (mode == "independent") {
    d[, .pct := (frank(get(xcol), ties.method="average")-0.5)/.N, by = .(Date, mkt)]
    d <- d[mdec == 10L]
  } else {
    d <- d[mdec == 10L]
    d[, .pct := (frank(get(xcol), ties.method="average")-0.5)/.N, by = .(Date, mkt)]
  }
  d[, .grp := as.integer(pmin(3L, 1L + floor(.pct*3)))]
  a <- d[.grp == 1L, .(r_lo = mean(Ret_1m), n_lo = .N), by = Date][n_lo >= minn]
  b <- d[.grp == 3L, .(r_hi = mean(Ret_1m), n_hi = .N), by = Date][n_hi >= minn]
  m <- merge(a, b, by = "Date"); m <- merge(m, bench[, .(Date, BM_Ret)], by = "Date")
  m[, sp := r_lo - r_hi][order(Date)] }

## ── 통제변수 결합 ───────────────────────────────────────────────────────────
X <- merge(ER, L, by = c("Date","Ticker"), all.x = TRUE)
cov_ctrl <- sapply(CTRLS, function(c) mean(is.finite(X[[c]])))
X[, adv_rank := (frank(adv, ties.method="average", na.last="keep")-0.5)/sum(is.finite(adv)), by = Date]
XC <- X[complete.cases(X[, ..CTRLS])]
cat(sprintf("[S3] L-family 결합: %d -> %d rows (완전관측) · 커버 %s\n", nrow(X), nrow(XC),
            paste(sprintf("%s=%.3f", CTRLS, cov_ctrl), collapse=" ")))

## ── (A) 조건부(승자 내부) 층화 — 요청 문구판 1급 ────────────────────────────
SP_cond <- sp_from(ER, "turn_form", "conditional")
SP_indep <- sp_from(ER, "turn_form", "independent")

## ── (B) L-family 직교화 — 변환 규약 2종(raw / rank) 병기 ────────────────────
orth <- function(D, transform = c("raw","rank")) {
  transform <- match.arg(transform); d <- copy(D)
  d[, y := log(pmax(turn_form, 1e-12))]
  if (transform == "rank") for (c in CTRLS) d[, (c) := (frank(get(c), ties.method="average")-0.5)/.N, by = Date]
  d[, resid_turn := { f <- lm(y ~ L01_Amihud + L09_Amihud_20d + L11_Kyle_Lambda); as.numeric(residuals(f)) }, by = Date]
  d }
XO_raw  <- orth(XC, "raw"); XO_rank <- orth(XC, "rank")
orth_res <- list(
  no_control_indep = spread_stats(sp_from(XC, "turn_form", "independent")),
  no_control_cond  = spread_stats(sp_from(XC, "turn_form", "conditional")),
  raw_control_indep  = spread_stats(sp_from(XO_raw,  "resid_turn", "independent")),
  raw_control_cond   = spread_stats(sp_from(XO_raw,  "resid_turn", "conditional")),
  rank_control_indep = spread_stats(sp_from(XO_rank, "resid_turn", "independent")),
  rank_control_cond  = spread_stats(sp_from(XO_rank, "resid_turn", "conditional")),
  transform_convention = "raw = Z_Score_Aligned 원값 선형 직교화 / rank = 통제축 월별 백분위 랭크 변환 후 선형 직교화. 두 규약 병기 의무(measurement-graduation §3 통제 변환 규약 기록).",
  note = "직교화 대상 = log(형성기 회전율). 잔차를 시장-내 재랭킹해 층화.")

## ── (C) 결과량 층화 통제 — L-family 십분위 내부에서 회전율 층화 ─────────────
##   (진단만으로는 걷어내지 못한다 — 실제 제거는 층화로만)
lstrat <- function(ctrl, K = 5L, minn = 3L) {
  d <- XC[mdec == 10L]
  d[, .cq := as.integer(pmin(K, 1L + floor(((frank(get(ctrl), ties.method="average")-0.5)/.N)*K))), by = Date]
  d[, .tp := (frank(turn_form, ties.method="average")-0.5)/.N, by = .(Date, mkt, .cq)]
  d[, .half := fifelse(.tp <= 0.5, "lo", "hi")]
  z <- d[, .(r = mean(Ret_1m), n = .N), by = .(Date, .cq, .half)]
  w <- dcast(z, Date + .cq ~ .half, value.var = c("r","n"))
  w <- w[is.finite(r_lo) & is.finite(r_hi) & n_lo >= minn & n_hi >= minn]
  w[, sp := r_lo - r_hi]
  m <- w[, .(sp = mean(sp), k = .N), by = Date][k >= 2L]
  m <- merge(m, bench[, .(Date, BM_Ret)], by = "Date")[order(Date)]
  spread_stats(m) }
outcome_stratified <- setNames(lapply(CTRLS, lstrat), CTRLS)
outcome_stratified$method <- "각 통제축 5분위 내부에서 (Date,mkt,분위) 회전율 재랭킹 중앙값 분할 -> 분위 평균. 승자 데실 한정."

## ── (D) 축별 누출 귀무 — 순수 통제변수를 stratifier 로 주입 ─────────────────
leak_null <- lapply(c(CTRLS, "adv_rank", "size_pct"), function(cc) {
  s_i <- spread_stats(sp_from(XC, cc, "independent")); s_c <- spread_stats(sp_from(XC, cc, "conditional"))
  list(axis = cc, independent_nw_t = s_i$nw_t, independent_mean_ann = s_i$mean_ann,
       conditional_nw_t = s_c$nw_t, conditional_mean_ann = s_c$mean_ann) })
names(leak_null) <- c(CTRLS, "adv_rank", "size_pct")
leak_verdict_rule <- "신호(회전율)의 |t| 가 어떤 순수-통제 귀무의 |t| 를 넘지 못하면 그 축의 독립성 미증명(VOL_INDEPENDENCE_UNPROVEN 대응)."

## ── (E) 절단면 프로파일 — 선택집합에서 통제축 자신이 되살아나는가 ───────────
cut <- XC[mdec == 10L]
cut[, vgrp := as.integer(pmin(3L, 1L + floor(((frank(turn_form, ties.method="average")-0.5)/.N)*3))), by = .(Date, mkt)]
prof_cols <- c(CTRLS, "adv_rank", "size_pct", "tr")
cutplane <- cut[vgrp %in% c(1L,3L), lapply(.SD, mean, na.rm = TRUE), by = vgrp, .SDcols = prof_cols]
## 통제축 자신의 20분위 프로파일(V1 집합) — 전 구간 상관과 나란히 기록
q20 <- function(cc) {
  d <- XO_rank[mdec == 10L]
  d[, vg := as.integer(pmin(3L, 1L + floor(((frank(resid_turn, ties.method="average")-0.5)/.N)*3))), by = .(Date, mkt)]
  d[, q := as.integer(pmin(20L, 1L + floor(((frank(get(cc), ties.method="average")-0.5)/.N)*20))), by = Date]
  tab <- d[vg %in% c(1L,3L), .(share = .N), by = .(vg, q)]
  tot <- tab[, .(tt = sum(share)), by = vg]; tab <- merge(tab, tot, by="vg")[, share := share/tt]
  w <- dcast(tab, q ~ vg, value.var = "share")
  setnames(w, c("q","V1","V3"))
  ends <- w[q <= 2L | q >= 19L, sum(V1)]; mid <- w[q >= 10L & q <= 11L, sum(V1)]
  list(profile_V1 = as.list(setNames(round(w$V1,4), paste0("q",w$q))),
       ends_over_mid_V1 = ends/ (mid*5),
       full_sample_spearman = cor(d$resid_turn, d[[cc]], method="spearman", use="complete.obs")) }
cutplane_q20 <- setNames(lapply(CTRLS, q20), CTRLS)

## ── (F) 이벤트타임 수평선 Year1 / Year2+ (LS2000 효과 본체의 수평선) ────────
MEs <- sort(unique(ER$Date)); midx <- data.table(Date = MEs, mi = seq_along(MEs))
RET <- merge(O$R, midx, by = "Date")
memb <- ER[, .(Date, Ticker, mdec, vter, mi = NULL)]
memb <- merge(memb, midx, by = "Date")
ev <- function(dec, v, hs) {
  cellm <- memb[mdec == dec & vter == v, .(Ticker, mi0 = mi)]
  out <- rbindlist(lapply(hs, function(h) {
    z <- merge(cellm[, .(Ticker, mi = mi0 + h - 1L, mi0)], RET[, .(Ticker, mi, Ret_1m)], by = c("Ticker","mi"))
    z[, .(h = h, r = mean(Ret_1m), n = .N), by = mi0] }))
  out }
horizons <- rbindlist(lapply(list(c(10,1),c(10,3),c(1,1),c(1,3)), function(p) {
  y1 <- ev(p[1], p[2], 1:12); y2 <- ev(p[1], p[2], 13:24); y3 <- ev(p[1], p[2], 25:36)
  data.table(mdec = p[1], vter = p[2],
             y1_ann = 12*mean(y1$r), y1_n = nrow(y1),
             y2_ann = 12*mean(y2$r), y2_n = nrow(y2),
             y3_ann = 12*mean(y3$r), y3_n = nrow(y3)) }))
hz_spread <- function(dec) {
  a <- horizons[mdec == dec & vter == 1L]; b <- horizons[mdec == dec & vter == 3L]
  list(mdec = dec, y1_v1_minus_v3_ann = a$y1_ann - b$y1_ann,
       y2_v1_minus_v3_ann = a$y2_ann - b$y2_ann,
       y3_v1_minus_v3_ann = a$y3_ann - b$y3_ann) }
## Year2 스프레드의 유의성 (formation-date 로 집계 후 NW — 중첩 12개월이므로 lag 확대)
hz_test <- function(dec) {
  a <- ev(dec, 1, 13:24)[, .(r1 = mean(r)), by = mi0]; b <- ev(dec, 3, 13:24)[, .(r3 = mean(r)), by = mi0]
  m <- merge(a, b, by = "mi0"); m[, d := r1 - r3]
  f <- lm(d ~ 1, data = m); ct <- coeftest(f, vcov = NeweyWest(f, lag = 11, prewhite = FALSE))
  list(mdec = dec, n_formation = nrow(m), y2_spread_ann = 12*mean(m$d),
       nw_lag11_t = as.numeric(ct[1,3]),
       overlap_note = "중첩 12개월 이벤트타임 — Hansen-Hodrick 계열 lag-11 NW. LS2000 과 동일 처리.") }
horizon_block <- list(
  by_cell = lapply(split(horizons, seq_len(nrow(horizons))), as.list),
  spreads = list(winner = hz_spread(10), loser = hz_spread(1)),
  tests = list(winner_y2 = hz_test(10), loser_y2 = hz_test(1)),
  label = "exploratory_not_preregistered — Year2+ 수평선은 LS2000 효과 본체의 좌표이며 본 라운드 판정 근거가 아니다.")

res <- list(
  meta = list(wt_id = "WT-R20260829_003", metric_type = "canonical_screen_diag",
              n_months = uniqueN(ER$Date), lfamily_coverage = as.list(cov_ctrl),
              c15_note = "L-family 는 load_month_factors(factor_names=...) 경유 · Z_Score_Aligned 만 사용(C13/C15)."),
  primary_variants = list(
    independent_LS2000 = spread_stats(SP_indep),
    conditional_within_winner = spread_stats(SP_cond),
    verdict_rule_declared_before_reading = "reject_if ① 은 '두 변형 모두 유의 양(+)' 이 아닐 때 발동한다(연언 규칙 — 결과를 본 뒤 유리한 변형으로 갈아타지 않기 위해 사전 고정)."),
  lfamily_orthogonality = orth_res,
  outcome_stratified_control = outcome_stratified,
  leakage_null_by_axis = c(leak_null, list(rule = leak_verdict_rule)),
  cutplane = list(mean_profile_V1_vs_V3 = lapply(split(cutplane, seq_len(nrow(cutplane))), as.list),
                  q20_profiles = cutplane_q20,
                  note = "전 구간 상관과 20분위 프로파일을 나란히 기록(하나만 내면 되살아남을 놓친다)."),
  horizons = horizon_block)
write_json(res, file.path(OUT, "s3_confound.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(XC = XC, XO_raw = XO_raw, XO_rank = XO_rank, SP_cond = SP_cond, SP_indep = SP_indep,
             midx = midx, RET = RET), file.path(OUT, "s3_objects.rds"))

pp <- function(nm, s) cat(sprintf("%-26s n=%3d %+7.2f%%/yr NW-t=%+7.3f | b-ctl a=%+7.2f%%/yr t=%+6.3f\n",
  nm, s$n_months, 100*s$mean_ann, s$nw_t, 100*s$beta_controlled$alpha_ann, s$beta_controlled$t_alpha))
cat("\n===== PRIMARY VARIANTS =====\n")
pp("independent (LS2000)", res$primary_variants$independent_LS2000)
pp("conditional (within-winner)", res$primary_variants$conditional_within_winner)
cat("\n===== L-FAMILY ORTHOGONALITY =====\n")
for (k in c("no_control_indep","raw_control_indep","rank_control_indep",
            "no_control_cond","raw_control_cond","rank_control_cond")) pp(k, orth_res[[k]])
cat("\n===== OUTCOME-STRATIFIED (control quintile-internal) =====\n")
for (k in CTRLS) pp(k, outcome_stratified[[k]])
cat("\n===== LEAKAGE NULL (pure control as stratifier) =====\n")
for (k in names(leak_null)) cat(sprintf("%-18s indep t=%+7.3f (%+6.2f%%/yr) | cond t=%+7.3f (%+6.2f%%/yr)\n",
  k, leak_null[[k]]$independent_nw_t, 100*leak_null[[k]]$independent_mean_ann,
  leak_null[[k]]$conditional_nw_t, 100*leak_null[[k]]$conditional_mean_ann))
cat("\n===== CUTPLANE mean profile (V1 vs V3, winner decile) =====\n"); print(cutplane)
cat("\n===== CUTPLANE q20 ends/mid ratio (V1 set, rank-orthogonalized) =====\n")
for (k in CTRLS) cat(sprintf("%-18s ends/mid=%.4f  full-sample spearman=%+.4f\n",
  k, cutplane_q20[[k]]$ends_over_mid_V1, cutplane_q20[[k]]$full_sample_spearman))
cat("\n===== EVENT-TIME HORIZONS (exploratory) =====\n"); print(horizons)
cat("winner V1-V3: Y1 ", sprintf("%+.2f%%", 100*hz_spread(10)$y1_v1_minus_v3_ann),
    " Y2 ", sprintf("%+.2f%%", 100*hz_spread(10)$y2_v1_minus_v3_ann),
    " Y3 ", sprintf("%+.2f%%", 100*hz_spread(10)$y3_v1_minus_v3_ann), "\n")
cat("loser  V1-V3: Y1 ", sprintf("%+.2f%%", 100*hz_spread(1)$y1_v1_minus_v3_ann),
    " Y2 ", sprintf("%+.2f%%", 100*hz_spread(1)$y2_v1_minus_v3_ann),
    " Y3 ", sprintf("%+.2f%%", 100*hz_spread(1)$y3_v1_minus_v3_ann), "\n")
cat(sprintf("Y2 tests: winner ann=%+.2f%% t(NW11)=%+.3f (n=%d) | loser ann=%+.2f%% t=%+.3f (n=%d)\n",
  100*hz_test(10)$y2_spread_ann, hz_test(10)$nw_lag11_t, hz_test(10)$n_formation,
  100*hz_test(1)$y2_spread_ann, hz_test(1)$nw_lag11_t, hz_test(1)$n_formation))
