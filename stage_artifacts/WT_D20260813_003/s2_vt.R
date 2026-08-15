## s2_vt.R — WT-D20260813_003 VT1/VT2/VT2b/VT3 실측
## ★사전등록 = stage_artifacts/WT_D20260813_003/prereg_VT.json (s1_prereg.R 가 먼저 실행됨)
## 판정 순서 승계: VT1(기록) -> VT2(1차) -> VT2b(결정 관문) -> VT4(성과, 통과 시에만)

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/validation/overlay_pit_guard.R")
BC <- new.env(parent = globalenv())
sys.source("02_Infrastructure/contracts/backtest_result_contract.R", envir = BC)
nw_t <- function(x, lag = 3L) BC$.nw_t_mean(x, lag = lag)

OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
PR  <- fromJSON(file.path(OUT, "prereg_VT.json"))
IN  <- readRDS(file.path(OUT, "vt_inputs.rds"))
EV <- as.data.table(IN$EV); S <- as.data.table(IN$S); BD <- as.data.table(IN$BD)
E_MIN <- PR$mapping$e_min; E_MAX <- PR$mapping$e_max
setorder(EV, hold_start)
cat(sprintf("[eval] n=%d  %s ~ %s   (prereg n=%d)\n", nrow(EV), EV$ym[1], EV$ym[nrow(EV)], PR$panel$n_months_eval))
stopifnot(nrow(EV) == PR$panel$n_months_eval)

## 홀딩월 수익 r_m — 표준함수 경유 (자체합성 금지)
suppressPackageStartupMessages({ library(xts); library(PerformanceAnalytics) })
bx <- xts(BD$BM_Ret, order.by = BD$Date)
bm_m <- apply.monthly(bx, Return.cumulative)
BM <- data.table(ym = format(as.Date(index(bm_m)), "%Y-%m"), r = as.numeric(bm_m))
EV <- merge(EV, BM, by = "ym")[order(hold_start)]
stopifnot(nrow(EV) == PR$panel$n_months_eval)
## 승계 패널 bm_ret 과의 대조 (독립 재산출 parity)
cat(sprintf("[parity] r vs 승계 bm_ret: max|diff| = %.3e\n", max(abs(EV$r - EV$bm_ret))))

r <- EV$r; e <- EV$e; n <- length(r)
ebar <- mean(e)
x <- e * r                      # 스케일 계열 (rf = 0)
cc <- ebar * r                  # exposure-matched 통제

## ── VT1 — 기록 의무 ─────────────────────────────────────────────────────────
## 홀딩월 내 실현 벤치 vol (사후 정보 — VT1 은 예측 링크 기록용, 판정 아님)
rv <- vapply(EV$hold_start, function(cut) {
  nx <- seq(cut, by = "month", length.out = 2)[2]
  rr <- BD[Date >= cut & Date < nx, BM_Ret]
  if (length(rr) < 5) return(NA_real_); stats::sd(rr) }, numeric(1))
EV[, realized_vol := rv]
vt1_sp <- cor(EV$sigma_d, EV$realized_vol, method = "spearman", use = "complete.obs")
vt1_pe <- cor(EV$sigma_d, EV$realized_vol, method = "pearson",  use = "complete.obs")
## 군집 강도 = 실현 vol 의 1차 자기상관 (VT2 이득의 상한 인자)
ac1 <- cor(EV$realized_vol[-1], EV$realized_vol[-n], use = "complete.obs")
cat(sprintf("\n[VT1] spearman(sigma_hat, 홀딩월 실현 vol) = %.4f (pearson %.4f)  |  실현vol ac1 = %.4f\n",
            vt1_sp, vt1_pe, ac1))

## ── VT2 — 분산 타이밍 이득 (1차 판정) ───────────────────────────────────────
Gstat <- function(ev, rr) { eb <- mean(ev); 1 - stats::sd(ev * rr) / stats::sd(eb * rr) }
G <- Gstat(e, r)
cat(sprintf("[VT2] sd(scaled)=%.5f  sd(control)=%.5f  sd(base)=%.5f  ebar=%.4f  G=%.4f\n",
            sd(x), sd(cc), sd(r), ebar, G))

## circular block permutation 영가설 (block=6, B=2000) — e 자기상관 보존, r 정렬만 파괴
set.seed(20260813L)
cbp <- function(v, block = 6L) {
  nn <- length(v); off <- sample.int(nn, 1L)
  vr <- v[c(off:nn, seq_len(off - 1L))]
  nb <- ceiling(nn / block)
  idx <- unlist(split(seq_len(nb * block), rep(seq_len(nb), each = block))[sample(nb)])
  vr[idx[idx <= nn]]
}
B <- 2000L
null_G <- vapply(seq_len(B), function(b) Gstat(cbp(e, 6L), r), numeric(1))
null_G <- null_G[is.finite(null_G)]
q95 <- stats::quantile(null_G, 0.95); p_perm <- mean(null_G >= G)
cat(sprintf("[VT2] null(circ block perm, block=6, B=%d): mean=%.4f  q95=%.4f  ->  p=%.4f\n",
            length(null_G), mean(null_G), q95, p_perm))

MIN_EFFECT <- 0.02
vt2_pass <- isTRUE(G > q95) && isTRUE(G >= MIN_EFFECT)
cat(sprintf("[VT2] 판정: G=%.4f  > q95=%.4f ? %s   AND  >= %.2f ? %s   ->  %s\n",
            G, q95, G > q95, MIN_EFFECT, G >= MIN_EFFECT, if (vt2_pass) "PASS" else "FAIL"))

## ★양성 대조 — 잣대가 살아있는가 (사후 정보 sigma 를 넣으면 G 가 크게 올라야 한다)
sstar_ev <- EV$sigma_star
e_pc <- pmin(E_MAX, pmax(E_MIN, sstar_ev / EV$realized_vol))   # 동월 실현 vol = look-ahead
G_pc <- Gstat(e_pc, r)
cat(sprintf("[VT2-posctrl] 동월 실현 vol 사용(사후정보) G = %.4f  (실측 %.4f 보다 커야 잣대 정상)\n", G_pc, G))
## ★위반 주입 — 무정보 e (i.i.d. 셔플) 는 G<=0 근방이어야
G_shuf <- vapply(seq_len(500L), function(b) Gstat(sample(e), r), numeric(1))
cat(sprintf("[VT2-negctrl] i.i.d. 셔플 e: mean G = %.4f  q95 = %.4f\n", mean(G_shuf), quantile(G_shuf, .95)))

## ── VT2b — 수익 희생 판별 (결정 관문) ───────────────────────────────────────
d <- (e - ebar) * r                      # = cov(e, r) 의 표본 항
t_d <- nw_t(d, lag = 3L)
mean_d_ann <- mean(d) * 12
## 순효과 (기하수익 근사): mean(d) + (var(control) - var(scaled))/2
net_m  <- mean(d) + (stats::var(cc) - stats::var(x)) / 2
net_ann <- net_m * 12
drag_gain_ann <- ((stats::var(cc) - stats::var(x)) / 2) * 12
cat(sprintf("\n[VT2b] mean(d)=%.5f/월 (%.3f%%/yr)  NW lag-3 t = %.3f\n", mean(d), 100*mean_d_ann, t_d))
cat(sprintf("[VT2b] 분산드래그 이득 = %.3f%%/yr   순효과 = %.3f%%/yr\n", 100*drag_gain_ann, 100*net_ann))
vt2b_reject <- isTRUE(t_d <= -2.0)
cat(sprintf("[VT2b] 판정: t <= -2.0 ? %s  ->  %s\n", vt2b_reject, if (vt2b_reject) "REJECT(수익 희생)" else "비기각"))

## PIT-clean 통제 변형 (ebar 를 expanding mean 으로 — 통제군도 인과적)
ebar_exp <- vapply(seq_len(n), function(i) mean(e[1:i]), numeric(1))
cc2 <- ebar_exp * r; x2 <- x
G2 <- 1 - stats::sd(x2) / stats::sd(cc2)
d2 <- (e - ebar_exp) * r; t_d2 <- nw_t(d2, lag = 3L)
cat(sprintf("[VT2/2b-robust] expanding-mean 통제: G=%.4f  mean(d)=%.5f  t=%.3f\n", G2, mean(d2), t_d2))

## ── VT3 — PIT 무효 조건 ─────────────────────────────────────────────────────
assert_overlay_pit(EV$used_cutoff, EV$hold_start, label = "VT_sigma_hat")
## (a) 구조 항등식 — clip(e=1) 월에서 오버레이 == base 여야 함
clip_idx <- which(e >= E_MAX - 1e-12)
struct_max <- if (length(clip_idx)) max(abs(x[clip_idx] - r[clip_idx])) else NA_real_
cat(sprintf("\n[VT3a] clip 월(e=1) n=%d  max|scaled - base| = %.3e (0 이어야 정상)\n", length(clip_idx), struct_max))
## (b) lag1 스트레스
e_lag1 <- c(NA_real_, e[-n]); ok1 <- is.finite(e_lag1)
G_lag1 <- Gstat(e_lag1[ok1], r[ok1])
cat(sprintf("[VT3b] lag1 스트레스: G = %.4f  (base %.4f, 잔존율 %.1f%%)\n", G_lag1, G, 100 * G_lag1 / G))
## (c) strict-PIT A/B — 느슨 컷오프(홀딩월 말 정보 포함) 양성 대조
sig_loose <- vapply(EV$hold_start, function(cut) {
  nx <- seq(cut, by = "month", length.out = 2)[2]
  rr <- BD[Date < nx, BM_Ret]; if (length(rr) < 252) return(NA_real_); stats::sd(tail(rr, 252)) }, numeric(1))
e_loose <- pmin(E_MAX, pmax(E_MIN, sstar_ev / sig_loose))
G_loose <- Gstat(e_loose, r)
ab <- overlay_lookahead_ab(G_loose, G, metric_name = "VT2_G(loose vs strict)")
cat(sprintf("[VT3c] %s\n", ab$message))
## (d) 위반 주입 — 가드가 살아있는가 (느슨 컷오프를 assert 에 통과시키면 stop 나야 정상)
guard_fires <- tryCatch({
  assert_overlay_pit(seq(EV$hold_start[1], by = "month", length.out = 2)[2], EV$hold_start[1], label = "inject")
  FALSE }, error = function(er) TRUE)
cat(sprintf("[VT3d] 위반 주입 -> assert_overlay_pit 발화 = %s (TRUE 여야 정상)\n", guard_fires))
## (e) 저변동 구간 이득 = 누출 역진단 — bind/clip 영역별 분산 기여 분해
q_m <- (e^2 - ebar^2) * r^2
lowvol <- EV$sigma_d <= stats::median(EV$sigma_d)
cat(sprintf("[VT3e] 분산기여 sum(q): 전체=%.5f  bind(e<1)=%.5f  clip(e=1)=%.5f  저sigma절반=%.5f\n",
            sum(q_m), sum(q_m[e < E_MAX - 1e-12]), sum(q_m[clip_idx]), sum(q_m[lowvol])))

## ── 부기간 (기술통계 — 판정 인용 금지) ─────────────────────────────────────
EV[, sub := fifelse(hold_start < as.Date("2008-01-01"), "pre2008",
             fifelse(hold_start < as.Date("2017-01-01"), "2008_2016", "post2017"))]
EV[, `:=`(e_v = e, x_v = x, c_v = cc, d_v = d)]
subd <- EV[, .(n = .N, mean_e = mean(e_v), G = 1 - sd(x_v)/sd(mean(e_v)*r),
               mean_d_ann_pct = 100 * mean(d_v) * 12), by = sub]
cat("\n[desc] 부기간 (기술통계 — 검정력 부족, 판정 아님):\n"); print(subd)

## ── 산출 ────────────────────────────────────────────────────────────────────
verdict <- if (!vt2_pass) "VT2_FAIL" else if (vt2b_reject) "VT2b_REJECT" else "VT2_VT2b_PASS_PROCEED_VT4"
cat(sprintf("\n★ VT VERDICT = %s\n", verdict))

res <- list(
  wt_id = "WT-D20260813_003", stage = "VT", metric_type = "mechanism_observation",
  prereg = "stage_artifacts/WT_D20260813_003/prereg_VT.json",
  n_months = n, window = c(EV$ym[1], EV$ym[n]),
  mean_exposure = ebar, bind_rate = mean(e < E_MAX - 1e-12), floor_rate = mean(e <= E_MIN + 1e-12),
  VT1 = list(role = "record_only", spearman = vt1_sp, pearson = vt1_pe,
             realized_vol_ac1 = ac1,
             note = "예측기 = trailing 252d 실현변동성 자체. '더 나은 예측 입력' 신규성 주장 없음(승계 자인)."),
  VT2 = list(G = G, sd_scaled = sd(x), sd_control = sd(cc), sd_base = sd(r),
             null_mean = mean(null_G), null_q95 = as.numeric(q95), p_perm = p_perm, B = length(null_G),
             min_effect = MIN_EFFECT, pass = vt2_pass,
             positive_control_G_same_month_vol = G_pc,
             negative_control_shuffle_meanG = mean(G_shuf),
             robust_expanding_control_G = G2),
  VT2b = list(mean_d_monthly = mean(d), mean_d_annual_pct = 100 * mean_d_ann,
              nw_lag3_t = t_d, reject = vt2b_reject,
              variance_drag_gain_annual_pct = 100 * drag_gain_ann,
              net_effect_annual_pct = 100 * net_ann,
              robust_expanding_control = list(mean_d = mean(d2), nw_lag3_t = t_d2)),
  VT3 = list(assert_overlay_pit = "PASS", clip_identity_max_abs = struct_max,
             lag1_G = G_lag1, lag1_retention = G_lag1 / G,
             loose_cutoff_G = G_loose, ab_inflation = ab$inflation,
             ab_lookahead_suspected = ab$lookahead_suspected,
             guard_violation_injection_fires = guard_fires,
             variance_contrib = list(total = sum(q_m), bind = sum(q_m[e < E_MAX - 1e-12]),
                                     clip = sum(q_m[clip_idx]), low_sigma_half = sum(q_m[lowvol]))),
  subperiod_descriptive = subd,
  verdict = verdict
)
write_json(res, file.path(OUT, "vt_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
saveRDS(EV, file.path(OUT, "vt_panel.rds"))
cat("\n[done] vt_result.json written\n")
