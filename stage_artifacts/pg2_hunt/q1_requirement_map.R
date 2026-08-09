## q1 — 요구조건 지도: (상관 rho, 슬리브 standalone IR) → ΔIR
##
## ★구성 방법 (선언):
##   a_i = incumbent net-active (ret_net − benchmark_ret). z_i = (a_i − mean)/sd  (표본 sd 정확히 1)
##   e ~ N(0,1) draw → z_i 에 회귀(절편 포함)한 **잔차**로 직교화 → 표준화 = z_e (표본 cor(z_e,z_i)=0 정확)
##   u = rho*z_i + sqrt(1−rho^2)*z_e     ⇒ 표본 cor(u,z_i)=rho 정확, 표본 sd(u)=1 정확
##   a_s = sigma_s*u + mu_s ,  sigma_s = sigma_ratio * sd(a_i) ,  mu_s = IR_target*sigma_s/sqrt(12)
##   sleeve ret_net = benchmark_ret + a_s   ← bm_delta_ir 는 (1−w)*inc + w*sleeve 를 만들고
##                                             벤치를 빼므로 book active = (1−w)a_i + w a_s (항등)
## ★측정은 계약 경로 bm_delta_ir()/bm_delta_ir_sweep() 로만. 손계산 IR 없음.
## ★해석 상한: 이 지도는 **PG2 자기 벤치(KOSPI200) 기준**이다. 후보를 다른 벤치로 채점하면 무효.

suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[q1] ", fmt, "\n"), ...)); flush.console() }
OUT <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/contracts/book_marginal.R")

B <- bm_load_incumbent()
say("=== 입력 실측 (incumbent) ===")
say("  %d개월 · %s ~ %s", nrow(B), min(B$date), max(B$date))
say("  ret_net 평균 %+.6f · bench 평균 %+.6f · active 평균 %+.6f · sd(active) %.6f",
    mean(B$ret_net), mean(B$benchmark_ret), mean(B$active), sd(B$active))
IR_I <- bm_ir(B$active); SD_I <- sd(B$active)
say("  incumbent IR(net_active_recon_v1) = %.6f · 목표 문턱 ΔIR >= 0.05 → book_ir >= %.6f",
    IR_I, IR_I + 0.05)
say("  active NA %d · 벤치 NA %d", sum(!is.finite(B$active)), sum(!is.finite(B$benchmark_ret)))

z_i <- as.numeric(scale(B$active))            # 표본 mean 0, sd 1
n   <- nrow(B)

make_sleeve <- function(rho, ir_target, sigma_ratio = 1.0, seed) {
  set.seed(seed)
  e  <- rnorm(n)
  r  <- residuals(lm(e ~ z_i))
  z_e <- as.numeric(scale(r))
  u  <- rho * z_i + sqrt(max(0, 1 - rho^2)) * z_e
  sig <- sigma_ratio * SD_I
  mu  <- ir_target * sig / sqrt(12)
  a_s <- sig * u + mu
  data.table(date = B$date, ret_net = B$benchmark_ret + a_s)
}

## ---------- 0. 구성 검증 (양방향) ----------
say("=== 0. 구성 검증 — 목표 rho/IR 이 실제로 실현되는가 (위반 주입 없이 판정 금지) ===")
chk <- rbindlist(lapply(c(-0.2, 0, 0.4, 0.8), function(rr) {
  s <- make_sleeve(rr, 0.6, 1.0, seed = 101)
  o <- bm_delta_ir(s, weight = 0.20, incumbent = B)
  data.table(rho_target = rr, rho_realized = o$correlation_with_incumbent,
             ir_target = 0.6, ir_realized = o$sleeve_standalone_ir)
}))
print(chk)
stopifnot(max(abs(chk$rho_target - chk$rho_realized)) < 1e-9,
          max(abs(chk$ir_target  - chk$ir_realized))  < 1e-9)
say("  ★구성 정확 (오차 < 1e-9) — 목표가 실현된다")

## 음성 대조: rho=1 이면 직교 이득 0 이어야(같은 IR 일 때 ΔIR=0)
neg <- bm_delta_ir(make_sleeve(1.0, IR_I, 1.0, seed = 7), weight = 0.20, incumbent = B)
say("  [음성 대조] rho=1 ∧ IR=incumbent → ΔIR %+.2e (0 이어야) → %s",
    neg$delta_ir, if (abs(neg$delta_ir) < 1e-9) "PASS" else "★FAIL")
## 양성 대조: rho=0 ∧ IR=incumbent → ΔIR>0 이어야
pos <- bm_delta_ir(make_sleeve(0.0, IR_I, 1.0, seed = 7), weight = 0.20, incumbent = B)
say("  [양성 대조] rho=0 ∧ IR=incumbent → ΔIR %+.4f (>0 이어야) → %s",
    pos$delta_ir, if (pos$delta_ir > 0) "PASS" else "★FAIL")

## ---------- 1. 격자 (rho x IR x w), 격자점당 20 draw ----------
RHOS <- c(-0.2, 0, 0.2, 0.4, 0.6, 0.8)
IRS  <- c(0.2, 0.4, 0.6, 0.8, 1.0, 1.4)
WS   <- c(0.05, 0.10, 0.20, 0.30)
NDRAW <- 20L

say("=== 1. 격자 측정 (%d rho x %d IR x %d w x %d draw = %d 회 bm_delta_ir) ===",
    length(RHOS), length(IRS), length(WS), NDRAW, length(RHOS)*length(IRS)*length(WS)*NDRAW)
t0 <- Sys.time(); rows <- list()
for (rr in RHOS) for (ii in IRS) for (ww in WS) {
  d <- vapply(seq_len(NDRAW), function(k)
    bm_delta_ir(make_sleeve(rr, ii, 1.0, seed = 1000L*k + 7L), weight = ww,
                incumbent = B)$delta_ir, numeric(1))
  rows[[length(rows)+1L]] <- data.table(rho = rr, sleeve_ir = ii, weight = ww,
    delta_ir_med = median(d), delta_ir_min = min(d), delta_ir_max = max(d),
    draw_spread = max(d) - min(d), beats = median(d) >= 0.05)
}
G <- rbindlist(rows)
say("  경과 %.1f분", as.numeric(difftime(Sys.time(), t0, units="mins")))
say("  ★draw 간 최대 산포 = %.3e — 구성이 rho/IR 을 표본에서 정확히 고정하므로 ΔIR 은 draw 무의존.",
    max(G$draw_spread))
say("   (따라서 이 지도는 단일-draw 취약성 대상이 아니다. 20 draw 는 그 사실의 실측 증거로 돌렸다.)")

fwrite(G, file.path(OUT, "q1_grid.csv"))

say("=== 2. ΔIR 격자표 (중앙값) — w 별 ===")
for (ww in WS) {
  say("  --- weight = %.2f (문턱 0.05) ---", ww)
  W <- dcast(G[weight == ww], rho ~ sleeve_ir, value.var = "delta_ir_med")
  print(W)
}

## ---------- 2. ΔIR>=0.05 최소 sleeve_IR (계약 경로 이분법) ----------
min_ir_for <- function(rho, w, sigma_ratio = 1.0, lo = -1, hi = 8, tol = 1e-4) {
  f <- function(x) bm_delta_ir(make_sleeve(rho, x, sigma_ratio, seed = 20260809L),
                               weight = w, incumbent = B)$delta_ir - 0.05
  if (f(hi) < 0) return(NA_real_)          # 도달 불가
  if (f(lo) >= 0) return(lo)
  for (k in 1:60) { mid <- (lo+hi)/2; if (f(mid) >= 0) hi <- mid else lo <- mid
                    if (hi-lo < tol) break }
  hi
}
say("=== 3. ★표적 정의: ΔIR>=0.05 를 넘는 **최소 sleeve standalone IR** ===")
say("   (sigma_ratio = 슬리브 active 변동 / incumbent active 변동. 기본 1.0)")
TG <- rbindlist(lapply(c(0.5, 1.0, 1.5), function(sr)
  rbindlist(lapply(RHOS, function(rr)
    rbindlist(lapply(WS, function(ww)
      data.table(sigma_ratio = sr, rho = rr, weight = ww,
                 min_sleeve_ir = min_ir_for(rr, ww, sr))))))))
fwrite(TG, file.path(OUT, "q1_min_ir_target.csv"))
for (sr in c(0.5, 1.0, 1.5)) {
  say("  --- sigma_ratio = %.1f ---", sr)
  print(dcast(TG[sigma_ratio == sr], rho ~ weight, value.var = "min_sleeve_ir"))
}

## ---------- 3. 검증: 최소 IR 바로 위/아래에서 판정이 실제로 갈리는가 ----------
say("=== 4. 표적 검증 (경계 ±0.02 에서 판정 반전 확인) ===")
VER <- rbindlist(lapply(RHOS, function(rr) {
  m <- TG[sigma_ratio == 1.0 & rho == rr & weight == 0.20, min_sleeve_ir]
  if (!is.finite(m)) return(NULL)
  lo <- bm_delta_ir(make_sleeve(rr, m - 0.02, 1.0, 5L), 0.20, incumbent = B)$delta_ir
  hi <- bm_delta_ir(make_sleeve(rr, m + 0.02, 1.0, 5L), 0.20, incumbent = B)$delta_ir
  data.table(rho = rr, min_ir = m, dIR_at_minus = lo, dIR_at_plus = hi,
             flips = lo < 0.05 & hi >= 0.05)
}))
print(VER)
say("  경계 반전 %d/%d → %s", sum(VER$flips), nrow(VER),
    if (all(VER$flips)) "PASS" else "★FAIL")

saveRDS(list(grid = G, target = TG, ir_incumbent = IR_I, sd_active = SD_I,
             n = n, verify = VER, construct_check = chk),
        file.path(OUT, "q1_requirement_map.rds"))
say("=== q1 완료 → q1_grid.csv / q1_min_ir_target.csv / q1_requirement_map.rds ===")
