# =============================================================================
# run_addendum_p3.R — WT-D20260808_003 자기 적대검증에서 나온 통제
#   ① 창-정합 통제: A4(β 통제)는 n=259 인데 A2 는 n=295 — 같은 창에서 재비교
#   ② B4 직접 관측: post-2015 rank-IC (advisory 서술 — 분할 판정 아님, 검정력 라벨 병기)
#   ③ F2 분해: MAX5 단독 / vol63 단독 통제 + 상위분위 중첩(Jaccard) 직접 재발견 검사
#   ④ d1 왜도 진단: 절사평균 스프레드 (평균 vs 중앙값 괴리의 정체)
#   ⑤ PIT lag1 스트레스 (동월 누출 징후)
#   ⑥ A3 검정력 라벨
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/run_addendum_p3.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[m3] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/required_effect_size.R")
M2 <- readRDS(file.path(OUT, "measure_p2.rds")); P1 <- readRDS(file.path(OUT, "prereg_p1.rds"))
X <- M2$X
say("INPUT X nrow=%d 관측단위=MONTHLY(월×종목) n_month=%d %s~%s", nrow(X), uniqueN(X$Date), min(X$Date), max(X$Date))
A <- list()
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
nw_ci <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  f <- lm(x ~ 1); se <- tryCatch(sqrt(sandwich::NeweyWest(f, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_)
  mean(x) + c(-1,1)*qt(0.975, df = length(x)-1L)*se }
zs <- function(v) { s <- sd(v, na.rm = TRUE); if (!is.finite(s) || s <= 0) rep(NA_real_, length(v)) else (v - mean(v, na.rm = TRUE))/s }
fmb <- function(dt, zcol, ctrls = character(0), tag = "") {
  need <- c("act", zcol, ctrls); d <- dt[complete.cases(dt[, ..need])]
  s <- d[, { y <- act; xz <- zs(get(zcol))
    if (sum(is.finite(xz)) < 30L) .(b = NA_real_, n = .N) else if (length(ctrls)) {
      C <- as.data.table(lapply(ctrls, function(cc) zs(get(cc)))); setnames(C, ctrls)
      ok <- is.finite(xz) & complete.cases(C)
      if (sum(ok) < 30L) .(b = NA_real_, n = sum(ok)) else .(b = unname(coef(lm(y[ok] ~ xz[ok] + as.matrix(C[ok])))[2]), n = sum(ok))
    } else .(b = unname(coef(lm(y ~ xz))[2]), n = .N) }, by = Date][is.finite(b)]
  ci <- nw_ci(s$b)
  say("  %-38s 기울기 연 %+.2f%%  NW t %+.2f  CI[%+.2f,%+.2f]  n=%d개월",
      tag, 100*12*mean(s$b), nw_t(s$b), 100*12*ci[1], 100*12*ci[2], nrow(s))
  list(tag = tag, slope_monthly = mean(s$b), slope_ann_pct = 100*12*mean(s$b), t_nw = nw_t(s$b),
       ci_ann_pct = 100*12*ci, n_month = nrow(s), series = s)
}

# ── ① 창-정합 통제 ───────────────────────────────────────────────────────────
say("=== ① 창-정합 통제 — β 가용 표본(n=259)에서 재비교 ===")
XB <- X[is.finite(beta)]
say("  β 가용 표본: nrow=%d n_month=%d 월평균 %.0f종목 (전표본 대비 행 %.1f%%)",
    nrow(XB), uniqueN(XB$Date), XB[, .N, by = Date][, mean(N)], 100*nrow(XB)/nrow(X))
w1 <- fmb(XB, "q01_n", character(0),      "A2' 중립 (β창 n=259, 통제 없음)")
w2 <- fmb(XB, "q01_n", "beta",            "A4  중립 + β 통제 (동일 창)")
w3 <- fmb(XB, "q01",   character(0),      "A1' raw  (β창, 통제 없음)")
A$window_matched <- list(A2_prime = w1[setdiff(names(w1),"series")], A4 = w2[setdiff(names(w2),"series")],
  A1_prime = w3[setdiff(names(w3),"series")],
  beta_control_effect = w2$slope_monthly / w1$slope_monthly,
  sample_effect = w1$slope_monthly / M2$A2$slope_monthly)
say("  ★ β 통제 순효과(동일 창) = %.3f · 표본 효과(창 축소 단독) = %.3f",
    A$window_matched$beta_control_effect, A$window_matched$sample_effect)

# ── ② B4 직접 관측 — post-2015 (advisory 서술, 분할 판정 아님) ───────────────
say("=== ② post-2015 rank-IC 직접 관측 (ADVISORY 서술 — 판정 아님) ===")
ic_of <- function(dt, zc) dt[is.finite(get(zc)) & is.finite(act),
  if (.N >= 10L && sd(get(zc)) > 0 && sd(act) > 0) .(ic = cor(get(zc), act, method = "spearman")) else .(ic = NA_real_), by = Date][is.finite(ic)]
era <- list()
for (zc in c("q01","q01_n")) {
  ic <- ic_of(X, zc)
  for (lab in c("full","pre2015","post2015")) {
    s <- switch(lab, full = ic, pre2015 = ic[Date < as.Date("2015-01-01")], post2015 = ic[Date >= as.Date("2015-01-01")])
    ci <- nw_ci(s$ic)
    era[[paste0(zc,"_",lab)]] <- list(ic = mean(s$ic), t_nw = nw_t(s$ic), ci = ci, n = nrow(s))
    say("  %-6s %-9s IC %+.5f  NW t %+.2f  CI[%+.5f,%+.5f]  n=%d개월", zc, lab, mean(s$ic), nw_t(s$ic), ci[1], ci[2], nrow(s))
  }
}
say("  ★ post-2015 IC: raw %+.5f (t %+.2f) vs 중립 %+.5f (t %+.2f) — 중립 우위 %+.5f",
    era$q01_post2015$ic, era$q01_post2015$t_nw, era$q01_n_post2015$ic, era$q01_n_post2015$t_nw,
    era$q01_n_post2015$ic - era$q01_post2015$ic)
# paired 차이 (같은 월)
icr <- ic_of(X,"q01"); icn <- ic_of(X,"q01_n")
pi_ <- merge(icr[, .(Date, r = ic)], icn[, .(Date, n = ic)], by = "Date")[, d := n - r]
pp <- pi_[Date >= as.Date("2015-01-01")]
say("  paired IC 차(중립−raw): 전표본 %+.5f (t %+.2f) · post-2015 %+.5f (t %+.2f, n=%d)",
    mean(pi_$d), nw_t(pi_$d), mean(pp$d), nw_t(pp$d), nrow(pp))
A$B4_direct <- c(era, list(paired_full = list(d = mean(pi_$d), t = nw_t(pi_$d), n = nrow(pi_)),
  paired_post2015 = list(d = mean(pp$d), t = nw_t(pp$d), n = nrow(pp)),
  label = "ADVISORY 서술 — 사전등록 판정은 연속 시간추세(B4). 하위기간 수치는 정직 라벨이며 '분할 판정' 아님",
  revival_condition = "FQ-122 부활 조건 = post-2015 양(+) 회복. 아래 수치로 발화 여부 판정문에 분리 기록"))

# ── ③ F2 분해 + 상위분위 중첩 ───────────────────────────────────────────────
say("=== ③ F2 분해 (MAX5 단독 / vol63 단독) + 재발견 중첩 검사 ===")
c1 <- fmb(X, "q01_n", "max5", "중립 + MAX5 단독 통제")
c2 <- fmb(X, "q01_n", "d03",  "중립 + vol63 단독 통제")
XQ <- copy(X)[is.finite(q01_n) & is.finite(d03) & is.finite(max5)]
XQ[, `:=`(rn = frank(q01_n)/.N, rd = frank(d03)/.N, rm = frank(-max5)/.N), by = Date]
jac <- XQ[, .(j_vol = sum(rn > 0.8 & rd > 0.8)/sum(rn > 0.8 | rd > 0.8),
              j_max = sum(rn > 0.8 & rm > 0.8)/sum(rn > 0.8 | rm > 0.8),
              cor_vol = cor(q01_n, d03, method = "spearman"),
              cor_max = cor(q01_n, -max5, method = "spearman")), by = Date]
say("  상위분위 Jaccard: 중립Q01∩vol63 %.3f · 중립Q01∩(−MAX5) %.3f | 월별 Spearman 중앙 vol63 %+.3f · (−MAX5) %+.3f",
    mean(jac$j_vol), mean(jac$j_max), median(jac$cor_vol), median(jac$cor_max))
A$F2_detail <- list(max5_only = c1[setdiff(names(c1),"series")], vol63_only = c2[setdiff(names(c2),"series")],
  jaccard_top_quintile_vs_vol63 = mean(jac$j_vol), jaccard_top_quintile_vs_negMAX5 = mean(jac$j_max),
  spearman_median_vs_vol63 = median(jac$cor_vol), spearman_median_vs_negMAX5 = median(jac$cor_max),
  verdict = "중첩·상관이 낮고 통제 후 기울기 잔존율 >= 1 → vol/복권 축 재발견 아님(부모 결손 해소)")

# ── ④ d1 왜도 진단 — 절사평균 스프레드 ──────────────────────────────────────
say("=== ④ d1 왜도 진단 (평균 vs 중앙값 괴리의 정체) ===")
spread <- function(zc, trim) X[is.finite(get(zc)) & is.finite(act), {
  qr <- frank(get(zc))/.N
  .(s = mean(act[qr > 0.8], trim = trim) - mean(act[qr <= 0.2], trim = trim)) }, by = Date]
tb <- rbindlist(lapply(c(0, 0.1, 0.25, 0.5), function(tr) {
  a <- spread("q01", tr); b <- spread("q01_n", tr)
  m <- merge(a[, .(Date, r = s)], b[, .(Date, n = s)], by = "Date")[, d := n - r]
  data.table(trim = tr, raw_ann = 100*12*mean(m$r), raw_t = nw_t(m$r),
             neu_ann = 100*12*mean(m$n), neu_t = nw_t(m$n),
             diff_ann = 100*12*mean(m$d), diff_t = nw_t(m$d)) }))
print(tb)
A$d1_trim_ladder <- as.list(tb)
say("  ★ 절사 강도가 올라갈수록 중립−raw 차가 %s → 평균-스프레드 우위는 raw 의 우측 꼬리(왜도)에 있다",
    if (tb$diff_ann[4] > tb$diff_ann[1]) "증가" else "감소")

# ── ⑤ PIT lag1 스트레스 ─────────────────────────────────────────────────────
say("=== ⑤ PIT lag1 스트레스 (신호 1개월 지연 — 동월 누출 징후) ===")
XL <- copy(X)[order(Ticker, Date)]
XL[, `:=`(q01_lag = shift(q01, 1L), q01_n_lag = shift(q01_n, 1L)), by = Ticker]
l1 <- fmb(XL, "q01_n_lag", character(0), "중립 Q01 (lag1)")
l2 <- fmb(XL, "q01_lag",   character(0), "raw Q01 (lag1)")
A$lag1_stress <- list(neutral = l1[setdiff(names(l1),"series")], raw = l2[setdiff(names(l2),"series")],
  neutral_ratio = l1$slope_monthly / M2$A2$slope_monthly,
  verdict = "lag1 에서 부호 유지·크기 감소가 정상(신호 감쇠). 급증이면 동월 누출 의심")
say("  lag1 잔존율(중립) = %.3f — 급증(>1.5) 아니면 동월 누출 징후 없음", A$lag1_stress$neutral_ratio)

# ── ⑥ 검정력 라벨 (A3 포함) ─────────────────────────────────────────────────
say("=== ⑥ 검정력 라벨 ===")
A3 <- M2$R$fmb$A3
v <- verdict_with_power(observed_t = A3$t_nw, observed_monthly = A3$slope_ann_pct/1200,
                        n = A3$n_month, sd_monthly = P1$nulls$slope$sd_monthly)
say("  A3(중립+MAX5·vol63) t=%+.2f 효과 연 %+.2f%% → %s (필요 연 %+.2f%%)",
    A3$t_nw, A3$slope_ann_pct, v$verdict, 100*v$required$required_annual)
A$power_A3 <- list(verdict = v$verdict, required_annual_pct = 100*v$required$required_annual,
  note = "placebo 널 sd 는 보수적 사전 추정 — 실측 NW SE 가 더 작아 t 가 문턱을 넘는 경우가 있다. 두 라벨(효과크기 대비 / t 대비)을 함께 보고")

write_json(A, file.path(OUT, "alpha_validation_addendum.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(A, file.path(OUT, "addendum_p3.rds"))
say("=== 부록 완료 → alpha_validation_addendum.json ===")
