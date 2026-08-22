## WT-D20260822_011 — 관문 FAIL 후 진단 (처치 백테스트 없음)
## 목적: ①base 패널 advisory 진단(처치 무관) ②설계 상속도 ③관문이 막은 뒤 눈에 들어온
##       부수 census 관측의 **정직한 크기·라벨** 산출. ★어느 것도 판정 수치가 아니다.
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_011")
say <- function(f, ...) cat(sprintf(paste0("[d] ", f, "\n"), ...))
D <- list()
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

O <- readRDS(file.path(OUT, "00_precheck_objects.rds"))
SEL <- as.data.table(O$SEL); RT <- as.data.table(O$RT); EPS <- O$EPS
Wb <- as.data.table(O$Wb); C1 <- O$C1
PC <- fromJSON(file.path(OUT, "00_precheck.json"))

## ── 1. base 패널 advisory (처치와 무관 — base 성질) ────────────────────────
B <- merge(SEL, RT, by = c("Date","Ticker"), all.x = TRUE)[is.finite(Ret_1m)]
ic <- B[, .(ic = if (.N >= 20L) suppressWarnings(cor(sc, Ret_1m, method = "spearman")) else NA_real_), by = Date]$ic
ic <- ic[is.finite(ic)]
D$base_advisory <- list(rank_ic = mean(ic), rank_ic_sd = sd(ic), icir = mean(ic)/sd(ic),
  ic_n_months = length(ic), ic_nw_t = nw_t(ic),
  metric_type = "advisory_diagnostic", scope = "base score_eff (처치 아님)",
  note = "measurement-graduation §3 — rank-IC 계열은 advisory. 판정 권위 아님.")
say("base rank IC = %.5f (ICIR %.3f, NW t %.2f, n=%d월) — advisory",
    D$base_advisory$rank_ic, D$base_advisory$icir, D$base_advisory$ic_nw_t, D$base_advisory$ic_n_months)

## ── 2. 설계 상속도 (수익 미사용 — 순수 설계 성질) ──────────────────────────
A <- copy(SEL)[, sc_adj := sc - EPS * as.numeric(excluded)]
D$inheritance <- list(
  pearson_sc_adj_vs_sc = cor(A$sc_adj, A$sc),
  spearman_sc_adj_vs_sc = suppressWarnings(cor(A$sc_adj, A$sc, method = "spearman")),
  epsilon_in_sd_units = EPS / sd(A$sc),
  flagged_share = A[, mean(excluded)],
  note = "tie-break 는 base score 에 표식 종목만 -epsilon 하는 규칙이므로 alpha 상속도가 1 에 가깝다. wt_type=discovery 인데 상속도 > 0.95 이면 재분류 권고 대상(v1.2 Charter §10) — 본 라운드는 '새 알파'가 아니라 **같은 알파의 소비 형태 변경**임을 수치가 확인한다.")
say("상속도: Pearson %.6f / Spearman %.6f (표식 비율 %.1f%%)",
    D$inheritance$pearson_sc_adj_vs_sc, D$inheritance$spearman_sc_adj_vs_sc, 100*D$inheritance$flagged_share)

## ── 3. 부수 census 관측 — 정직한 크기와 라벨 ───────────────────────────────
## ★관문은 '기전-함의' 로 판정한다. 아래는 관문 산술의 부산물로 계산된 **실현 교체 census** 이며
##   판정에 쓰지 않는다. 쓰지 않는 이유를 수치로 명시하는 것이 본 절의 목적.
kk <- function(d) paste(d$Date, d$Ticker)
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
Dt <- copy(SEL)[, sc_adj := sc - EPS * as.numeric(excluded)]
setorder(Dt, Date, -sc_adj); Dt[, rk := seq_len(.N), by = Date]
Wt <- Dt[rk <= 25L][, w := cap_norm(Size), by = Date][, .(Date, Ticker, w, sc)]
kb <- kk(Wb); kt <- kk(Wt)
disp <- merge(Wb[!(kb %chin% kt)], RT, by = c("Date","Ticker"), all.x = TRUE)
ins  <- merge(Wt[!(kt %chin% kb)], RT, by = c("Date","Ticker"), all.x = TRUE)
g <- merge(ins[,  .(gi = sum(w * fifelse(is.finite(Ret_1m), Ret_1m, 0)), wi = sum(w)), by = Date],
           disp[, .(gd = sum(w * fifelse(is.finite(Ret_1m), Ret_1m, 0)), wd = sum(w)), by = Date], by = "Date")
g[, raw := gi - gd]                          # 비중 비대칭 포함(= 순 노출 증가분 포함)
g[, matched := wd * (gi/wi - gd/wd)]          # 명목 일치(양 다리 동일 명목) 교체효과
D$incidental_swap_census <- list(
  raw_mean_monthly = g[, mean(raw)], raw_annual_pp = 1200*g[, mean(raw)],
  raw_nw_t = nw_t(g$raw), raw_sd = g[, sd(raw)],
  matched_mean_monthly = g[, mean(matched)], matched_annual_pp = 1200*g[, mean(matched)],
  matched_nw_t = nw_t(g$matched), matched_sd = g[, sd(matched)],
  n_months = nrow(g),
  weight_asymmetry = g[, mean(wi)]/g[, mean(wd)],
  mean_ret_displaced = disp[, mean(Ret_1m, na.rm=TRUE)], mean_ret_inserted = ins[, mean(Ret_1m, na.rm=TRUE)],
  tail_displaced = disp[, mean(is.finite(Ret_1m) & Ret_1m <= -0.20)],
  tail_inserted  = ins[,  mean(is.finite(Ret_1m) & Ret_1m <= -0.20)],
  mechanism_implied_monthly = PC$gate$benefit_monthly,
  ratio_observed_to_mechanism = g[, mean(matched)] / PC$gate$benefit_monthly,
  metric_type = "census_not_backtest",
  label = NA_character_)
D$incidental_swap_census$label <- paste0(
  "판정 아님 · 기전 귀속 불가 · 노이즈와 미분리. 근거 3: ",
  "(1) 명목-일치 관측치가 기전-함의의 ", sprintf("%.0f", D$incidental_swap_census$ratio_observed_to_mechanism),
  "배 — 사전등록 꼬리 기전이 산출할 수 있는 크기가 아니다(꼬리 격차 ",
  sprintf("%.5f", D$incidental_swap_census$tail_displaced - D$incidental_swap_census$tail_inserted),
  " 가 설명하는 몫은 그 중 ", sprintf("%.1f%%", 100/max(D$incidental_swap_census$ratio_observed_to_mechanism,1e-9)), "). ",
  "(2) NW t = ", sprintf("%.2f", D$incidental_swap_census$matched_nw_t),
  " — 이 창의 전도성 상한(양성 대조 paired t 1.566)에 비춰 유의성 판정 불가 구간. ",
  "(3) raw 판은 양 다리 명목이 ", sprintf("%.2f", D$incidental_swap_census$weight_asymmetry),
  "배 비대칭이라 교체효과가 아니라 대형주 순노출 증가를 일부 포함한다(WT-009 2.30배 / WT-010 1.14배와 같은 계통의 아티팩트).")
say("부수 census: raw %+.6f/월 (연 %+.3f%%p, NW t %+.2f) | 명목일치 %+.6f/월 (연 %+.3f%%p, NW t %+.2f) | 비중비대칭 %.2f배",
    D$incidental_swap_census$raw_mean_monthly, D$incidental_swap_census$raw_annual_pp, D$incidental_swap_census$raw_nw_t,
    D$incidental_swap_census$matched_mean_monthly, D$incidental_swap_census$matched_annual_pp,
    D$incidental_swap_census$matched_nw_t, D$incidental_swap_census$weight_asymmetry)
say("   기전-함의 대비 배율 = %.1f배 → 기전 귀속 불가", D$incidental_swap_census$ratio_observed_to_mechanism)

## ── 4. beta_hat 재검 — 여백에 지킬 알파가 있는가 ───────────────────────────
setorder(B, Date, -sc); B[, rk := seq_len(.N), by = Date]
prof <- rbindlist(lapply(list(c(1,25), c(20,40), c(1,40), c(1,100)), function(rg) {
  sub <- B[rk >= rg[1] & rk <= rg[2]]
  sl <- sub[, if (.N >= 10L && sd(sc) > 0) as.numeric(coef(lm(Ret_1m ~ sc))[2]) else NA_real_, by = Date]$V1
  sl <- sl[is.finite(sl)]
  data.table(rank_lo = rg[1], rank_hi = rg[2], beta = mean(sl), nw_t = nw_t(sl), n = length(sl)) }))
D$score_slope_profile <- list(table = as.data.frame(prof),
  reading = "여백(랭킹 근방)에서 score_eff -> Ret_1m 기울기가 유의한가. 유의하지 않으면 '여백 손실'은 작지만 동시에 '여백을 지켜서 얻을 것'도 작다 — epsilon 레버의 양날.")
for (i in seq_len(nrow(prof)))
  say("slope rank %3d-%3d: beta=%+.6f NW t=%+.2f (n=%d월)", prof$rank_lo[i], prof$rank_hi[i], prof$beta[i], prof$nw_t[i], prof$n[i])

write_json(D, file.path(OUT, "11_diag.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
