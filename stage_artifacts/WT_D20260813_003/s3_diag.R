## s3_diag.R — WT-D20260813_003 VT2b 사전등록 tie_rule 정확 적용 + 기전 분해
## ★s2 자기적발: s2 의 verdict 로직이 prereg tie_rule("점추정 음수·비유의면 순효과 부호로 판정")을
##   구현하지 않고 t<=-2.0 만 봤다. 본 스크립트가 사전등록 규칙을 정확히 적용한다(규칙 변경 아님).
## ★s2 자기적발 2: parity 대조가 EV$bm_ret 부재로 numeric(0) -> max()=-Inf 침묵 통과. 여기서 실행.

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/validation/overlay_pit_guard.R")
BC <- new.env(parent = globalenv())
sys.source("02_Infrastructure/contracts/backtest_result_contract.R", envir = BC)
nw_t <- function(x, lag = 3L) BC$.nw_t_mean(x, lag = lag)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
PR <- fromJSON(file.path(OUT, "prereg_VT.json"))
EV <- as.data.table(readRDS(file.path(OUT, "vt_panel.rds"))); setorder(EV, hold_start)
V2 <- fromJSON(file.path(OUT, "vt_result.json"))
E_MIN <- PR$mapping$e_min; E_MAX <- PR$mapping$e_max
r <- EV$r; e <- EV$e; n <- length(r); ebar <- mean(e)
x <- e * r; cc <- ebar * r; d <- (e - ebar) * r

## ── 0. s2 침묵 실패 수리 — 승계 패널 bm_ret 과의 parity 실측 ────────────────
P002 <- as.data.table(read_parquet("stage_artifacts/WT_D20260813_002/alpha_scores.parquet"))[, .(ym, bm_ret)]
PJ <- merge(EV[, .(ym, r)], P002, by = "ym")
stopifnot(nrow(PJ) == n)
parity_max <- max(abs(PJ$r - PJ$bm_ret)); parity_cor <- cor(PJ$r, PJ$bm_ret)
cat(sprintf("[parity-FIXED] 재산출 r vs 승계 bm_ret: n=%d  max|diff|=%.3e  cor=%.8f\n",
            nrow(PJ), parity_max, parity_cor))
if (!is.finite(parity_max) || parity_max > 1e-10) stop("[parity] 승계 수익 계열 불일치 — 중단")

## ── 1. 사전등록 tie_rule 정확 적용 ──────────────────────────────────────────
t_d <- nw_t(d, 3L)
drag_gain_m <- (stats::var(cc) - stats::var(x)) / 2
net_m <- mean(d) + drag_gain_m
## 표준함수 직접 확인 — 근사가 아니라 실제 기하수익 차 (bench-scale 산술, 포트/비용 없음)
xs <- xts(x,  order.by = EV$hold_start); cs <- xts(cc, order.by = EV$hold_start)
geo_x <- as.numeric(Return.annualized(xs, scale = 12))
geo_c <- as.numeric(Return.annualized(cs, scale = 12))
cat(sprintf("\n[VT2b tie_rule] mean(d)=%.3f%%/yr  분산드래그이득=%.3f%%/yr  순효과(근사)=%.3f%%/yr\n",
            100*mean(d)*12, 100*drag_gain_m*12, 100*net_m*12))
cat(sprintf("[VT2b 표준함수] Return.annualized: scaled=%.4f%%  control=%.4f%%  차=%.3f%%p\n",
            100*geo_x, 100*geo_c, 100*(geo_x - geo_c)))
tie_applies <- isTRUE(mean(d) < 0) && isTRUE(t_d > -2.0)
vt2b_reject <- isTRUE(t_d <= -2.0) || (tie_applies && isTRUE(net_m < 0))
cat(sprintf("[VT2b 판정] t=%.3f (>-2.0 -> tie_rule 발동=%s)  순효과 부호=%s  ->  %s\n",
            t_d, tie_applies, ifelse(net_m < 0, "음", "양"),
            if (vt2b_reject) "REJECT (수익 희생)" else "비기각"))

## 순효과 부호의 불확실성 — 이동블록 부트스트랩 (block=6)
set.seed(20260813L)
bb_net <- vapply(seq_len(4000L), function(b) {
  nb <- ceiling(n / 6L); st <- sample.int(n - 6L + 1L, nb, TRUE)
  idx <- unlist(lapply(st, function(s) s:(s + 5L)))[seq_len(n)]
  ee <- e[idx]; rr <- r[idx]; eb <- mean(ee)
  mean((ee - eb) * rr) + (stats::var(eb * rr) - stats::var(ee * rr)) / 2
}, numeric(1))
bb_net <- bb_net[is.finite(bb_net)] * 12
cat(sprintf("[VT2b boot] 순효과 %%/yr: point=%.3f  P(net>0)=%.3f  CI90=[%.3f, %.3f]  B=%d\n",
            100*net_m*12, mean(bb_net > 0), 100*quantile(bb_net,.05), 100*quantile(bb_net,.95), length(bb_net)))

## ── 2. 시대-드리프트 교란 분해 (primary vs robust 불일치 진단) ──────────────
## e 는 시대별 평균이 다르다(pre2008 0.798 vs post2017 0.947). 전표본 상수 통제는
## 시대-간 성분을 cov(e,r) 에 섞는다. 시대 내부에서 다시 exposure-match 해 분리.
EV[, sub := fifelse(hold_start < as.Date("2008-01-01"), "pre2008",
             fifelse(hold_start < as.Date("2017-01-01"), "2008_2016", "post2017"))]
EV[, e_sub_bar := mean(e), by = sub]
d_within <- (EV$e - EV$e_sub_bar) * r
d_between <- (EV$e_sub_bar - ebar) * r
cat(sprintf("\n[분해] cov(e,r) = within-era %.3f%%/yr + between-era %.3f%%/yr  (합 %.3f%%/yr)\n",
            100*mean(d_within)*12, 100*mean(d_between)*12, 100*mean(d)*12))
cat(sprintf("[분해] within-era NW t = %.3f   between-era NW t = %.3f\n",
            nw_t(d_within,3L), nw_t(d_between,3L)))
sub_tab <- EV[, .(n = .N, mean_e = mean(e), mean_r_pct = 100*mean(r),
                  d_within_ann_pct = 100*mean((e - mean(e)) * r) * 12), by = sub]
print(sub_tab)

## ── 3. 기전 특정 — 손실이 어디서 나는가 (승계 regime_scope 예측 검증) ───────
## 승계 예측: (i) 리바운드 클리핑 (ii) 첫 충격 회피 불가 (iii) clip 영역 무차별
EV[, bind := e < E_MAX - 1e-12]
EV[, r_prev3 := shift(frollsum(log1p(r), 3L), 1L)]          # 직전 3개월 로그수익 (t 이전 정보)
EV[, rebound := bind & is.finite(r_prev3) & r_prev3 < log(0.90)]
seg <- EV[, .(n = .N, mean_r_pct = 100*mean(r), mean_e = mean(e),
              contrib_ann_pct = 100 * sum((e - ebar) * r) / nrow(EV) * 12),
          by = .(seg = fifelse(!bind, "clip(e=1)", fifelse(rebound, "bind_rebound(직전3M<-10%)", "bind_normal")))]
cat("\n[기전] cov(e,r) 기여 분해 (승계 regime_scope 예측 대조):\n"); print(seg)
## bind 월의 실현 수익 평균 vs clip 월
cat(sprintf("[기전] bind 월 평균수익 %.3f%%/월 (n=%d) vs clip 월 %.3f%%/월 (n=%d)  Welch t=%.3f p=%.4f\n",
            100*mean(r[EV$bind]), sum(EV$bind), 100*mean(r[!EV$bind]), sum(!EV$bind),
            t.test(r[EV$bind], r[!EV$bind])$statistic, t.test(r[EV$bind], r[!EV$bind])$p.value))
## 분산 축은 반대 방향이어야 (bind 월이 실제로 고변동인가) — 기전 정합 확인
cat(sprintf("[기전] bind 월 실현vol %.4f vs clip 월 %.4f (기전 정합: bind 가 커야)\n",
            mean(EV$realized_vol[EV$bind]), mean(EV$realized_vol[!EV$bind])))

## ── 4. VT3c 재라벨 — 진짜 strict A/B + 주입 양성대조 구분 ───────────────────
ab_true <- overlay_lookahead_ab(V2$VT2$G, V2$VT2$G, metric_name = "VT2_G(current vs strict)")
cat(sprintf("\n[VT3c-정정] 실측 컷오프 == strict 컷오프이므로 인플레 = %.1f%% (동일 대상). ",
            100*ab_true$inflation))
cat(sprintf("주입 양성대조(느슨 컷오프)에서 %.1f%% 인플레 -> 검출기 작동 실증.\n", 100*V2$VT3$ab_inflation))

## ── 5. 산출 ─────────────────────────────────────────────────────────────────
verdict <- if (!isTRUE(V2$VT2$pass)) "VT2_FAIL" else if (vt2b_reject) "VT2b_REJECT" else "PROCEED_VT4"
cat(sprintf("\n★ 최종 VT VERDICT (사전등록 규칙 정확 적용) = %s\n", verdict))
cat(sprintf("★ VT4(성과) 착수 = %s\n", if (verdict == "PROCEED_VT4") "허용" else "금지 (판정 순서 승계)"))

write_json(list(
  wt_id = "WT-D20260813_003", stage = "VT_final", metric_type = "mechanism_observation",
  self_caught = list(
    s2_verdict_bug = "s2_vt.R 의 verdict 로직이 prereg tie_rule 미구현(t<=-2.0 만 검사) -> 'PROCEED_VT4' 오판. 본 스크립트가 사전등록 규칙 그대로 적용해 정정. 규칙 변경 아님.",
    s2_parity_silent_fail = "s2 의 승계-수익 parity 대조가 EV 에 bm_ret 컬럼 부재로 numeric(0) 평가 -> max()=-Inf 로 침묵 통과. s3 에서 실측 수행(max|diff|=0, cor=1)."),
  parity_inherited_returns = list(n = nrow(PJ), max_abs_diff = parity_max, cor = parity_cor),
  VT2b_final = list(
    mean_d_annual_pct = 100*mean(d)*12, nw_lag3_t = t_d,
    variance_drag_gain_annual_pct = 100*drag_gain_m*12,
    net_effect_annual_pct = 100*net_m*12,
    geo_scaled_annual_pct = 100*geo_x, geo_control_annual_pct = 100*geo_c,
    geo_diff_pp = 100*(geo_x - geo_c),
    tie_rule_applied = tie_applies, reject = vt2b_reject,
    bootstrap = list(B = length(bb_net), p_net_gt0 = mean(bb_net > 0),
                     ci90 = as.numeric(100*quantile(bb_net, c(.05,.95))))),
  era_decomposition = list(
    within_era_annual_pct = 100*mean(d_within)*12, within_era_nw_t = nw_t(d_within,3L),
    between_era_annual_pct = 100*mean(d_between)*12, between_era_nw_t = nw_t(d_between,3L),
    by_sub = sub_tab,
    note = "primary(전표본 상수 통제)와 robust(expanding-mean 통제) 불일치의 원인 진단."),
  mechanism_segments = seg,
  bind_vs_clip = list(
    mean_r_bind_pct = 100*mean(r[EV$bind]), n_bind = sum(EV$bind),
    mean_r_clip_pct = 100*mean(r[!EV$bind]), n_clip = sum(!EV$bind),
    welch_t = as.numeric(t.test(r[EV$bind], r[!EV$bind])$statistic),
    welch_p = t.test(r[EV$bind], r[!EV$bind])$p.value,
    realized_vol_bind = mean(EV$realized_vol[EV$bind]),
    realized_vol_clip = mean(EV$realized_vol[!EV$bind])),
  VT3c_relabel = list(
    true_ab_inflation = ab_true$inflation,
    injected_leak_ab_inflation = V2$VT3$ab_inflation,
    interpretation = "실측은 strict 컷오프 자체 -> 인플레 0. 느슨 컷오프 주입 시 14.3% 인플레 = 검출기 검출력 실증(양성 대조). 'LOOK-AHEAD 의심' 메시지는 주입 대조의 정상 발화이지 본 측정의 위반이 아니다."),
  verdict = verdict, vt4_authorized = (verdict == "PROCEED_VT4")
), file.path(OUT, "vt_final.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
saveRDS(EV, file.path(OUT, "vt_panel.rds"))
cat("\n[done] vt_final.json written\n")
