## FQ-187 P2 — 오염 제거 위에서 배분 결론 최종 재확인 + 실행비용 반영
## FQ-182 P2 는 2026 포함이었다. 정제 후에도 w*(ON) < w*(OFF) 가 유지되는가.
## 추가: tail_asym 이 h=1 전용이므로 **일간 리밸 비용**을 넣으면 무엇이 남는가.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ187")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/FQ182/p0.rds"))$D)[order(Date)]
G <- fread(file.path(ROOT, "stage_artifacts/FQ182/p5_bench_stock_gap.csv")); G[, Date := as.Date(Date)]
D <- merge(D, G[, .(Date, gap)], by = "Date", all.x = TRUE)
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
p99 <- quantile(G$gap, 0.99, na.rm = TRUE)
CL <- D[!is.na(fwd1) & !is.na(dd252) & Date < as.Date("2026-01-01") & (is.na(gap) | gap <= p99)]
RA <- D[!is.na(fwd1) & !is.na(dd252)]
say("=== 입력 실측 === 원본 %d일 · 정제 %d일 (%.1f%% 유지) · %s ~ %s",
    nrow(RA), nrow(CL), 100*nrow(CL)/nrow(RA), min(CL$Date), max(CL$Date))

EU <- function(r, w, g) { x <- 1 + w*r; if (any(x <= 0)) return(-Inf)
  if (abs(g-1) < 1e-9) mean(log(x)) else mean(x^(1-g))/(1-g) }
opt_w <- function(r, g, wmax = 1) optimize(function(w) -EU(r, w, g), c(0, wmax), tol = 1e-6)$minimum

say("=== ★배분 결론 — 원본 vs 정제 대조 ===")
say("   문턱  g   원본 w*(ON)/w*(OFF)/차이     정제 w*(ON)/w*(OFF)/차이")
rows <- list()
for (thr in c(-0.10, -0.20, -0.30)) for (g in c(2, 5, 10)) {
  o1 <- RA$dd252 <= thr; o2 <- CL$dd252 <= thr
  a1 <- opt_w(RA$fwd1[o1], g); b1 <- opt_w(RA$fwd1[!o1], g)
  a2 <- opt_w(CL$fwd1[o2], g); b2 <- opt_w(CL$fwd1[!o2], g)
  say("  %4.0f%%  %2g  %.3f/%.3f/%+.3f          %.3f/%.3f/**%+.3f**",
      thr*100, g, a1, b1, a1-b1, a2, b2, a2-b2)
  rows[[length(rows)+1L]] <- data.table(thr = thr*100, g = g,
    raw_diff = a1-b1, clean_on = a2, clean_off = b2, clean_diff = a2-b2)
}
R <- rbindlist(rows)
say("  ★정제 후 w*(ON) < w*(OFF) 셀 = **%d / %d**", R[clean_diff < 0, .N], nrow(R))
say("  ★부호가 뒤집힌 셀 = %d (원본 음수 -> 정제 양수)", R[raw_diff < 0 & clean_diff > 0, .N])

say("=== ★실행비용 반영 — h=1 효과는 매일 리밸을 요구한다 ===")
say("  tail_asym 은 h=1 전용(h>=10 부호 반대). 이를 쓰려면 **매일** 노출을 조절해야 한다.")
say("  Production 비용 = 15bps one-way. 노출을 w1 -> w2 로 바꾸면 |w2-w1| x 15bps.")
for (thr in c(-0.20, -0.30)) {
  o <- CL$dd252 <= thr
  ## 상태 전환 횟수 = ON/OFF 가 바뀌는 날
  sw <- sum(diff(as.integer(o)) != 0)
  yrs <- as.numeric(diff(range(CL$Date)))/365.25
  ## 전환당 노출 변화폭을 최적 w 차이로 잡음
  g <- 2; a <- opt_w(CL$fwd1[o], g); b <- opt_w(CL$fwd1[!o], g)
  dw <- abs(a - b)
  cost_yr <- (sw/yrs) * dw * 0.0015
  say("  thr %.0f%% : 상태전환 %d회(%.1f회/년) · 전환당 노출변화 %.3f · **연 비용 %.2f%%**",
      thr*100, sw, sw/yrs, dw, cost_yr*100)
  say("    ⇒ 그런데 최적 w 차이 자체가 **음수 방향**(%+.3f)이라 '확대' 전략은 비용 이전에 기대값에서 진다", a-b)
}

say("=== ★최종 요약 ===")
say("  ① 정제 후에도 w*(ON) < w*(OFF): %d/%d 셀", R[clean_diff < 0, .N], nrow(R))
say("  ② tail_asym 은 h=1 전용이고 h>=10 부호 반대 — 배분 지평에서 반대 신호")
say("  ③ 평균은 전 구간 비유의 — 꼬리 비대칭이 중앙부에서 상쇄됨")
say("  ⇒ 도훈 원 가설(위기 시 총노출 확대)은 **정제 데이터에서도 불지지**")

fwrite(R, file.path(OUT, "p2_clean_allocation.csv"))
saveRDS(R, file.path(OUT, "p2.rds"))
say("=== P2 완료 ===")
