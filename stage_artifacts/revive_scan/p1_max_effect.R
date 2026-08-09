## 되살림 스크린 P1 — ★오염이 PORT_t 를 최대 얼마나 억누를 수 있나 (상한 계산)
## 이게 재검 대상 범위를 정한다. 상한이 작으면 대부분 후보는 재검해도 안 바뀐다 = 라운드 축소.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/revive_scan")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/FQ182/p0.rds"))$D)[order(Date)]
D[, ym := format(Date, "%Y-%m")]
M <- D[, .(r = prod(1 + BM_Ret) - 1, nd = .N), by = ym][nd >= 15]
M[, yr := as.integer(substr(ym, 1, 4))]
say("=== 입력 실측 === 월 %d개 · %s ~ %s", nrow(M), min(M$ym), max(M$ym))

say("=== 1. 월간 벤치 변동성 — 2026 이 얼마나 다른가 ===")
for (y in 2020:2026) {
  s <- M[yr == y]
  if (nrow(s) < 3) next
  say("  %d : %2d개월 · 월수익 sd %.4f · 누적 %+.3f", y, nrow(s), sd(s$r), prod(1+s$r)-1)
}
pre <- M[yr < 2026]; cur <- M[yr == 2026]
infl <- sd(cur$r)/sd(pre$r)
say("  ★2026 월 sd / 2025이전 월 sd = **%.2f배** (2026 %d개월 = 전체의 %.2f%%)",
    infl, nrow(cur), 100*nrow(cur)/nrow(M))

say("=== 2. ★PORT_t 억압 상한 — 분모(활성수익 sd) 팽창 경로 ===")
w <- nrow(cur)/nrow(M)
say("  가정: 활성수익 sd 가 벤치 sd 팽창을 그대로 물려받는 최악의 경우")
for (k in c(1.5, 2, 3, infl)) {
  var_ratio <- (1-w) + w * k^2
  sd_ratio <- sqrt(var_ratio)
  say("  벤치 sd %.2f배 팽창 시 : 전체 sd %.4f배 → PORT_t **%.1f%% 억압** (2.95 도달 필요 원값 %.3f)",
      k, sd_ratio, 100*(1 - 1/sd_ratio), 2.95/sd_ratio)
}
say("  ★실측 팽창 %.2f배 기준 → **PORT_t %.1f%% 억압 · 되살아날 수 있는 구간 = [%.3f, 2.95)**",
    infl, 100*(1-1/sqrt((1-w)+w*infl^2)), 2.95/sqrt((1-w)+w*infl^2))

say("=== 3. 실측 검증 — 실제 벤치 계열로 t 억압을 재본다 ===")
## 가짜 알파 계열(벤치와 상관 0.9, 초과 0.5%/월)로 2026 포함/제외 t 비교
set.seed(20260809)
res <- list()
for (rep in 1:200) {
  a <- 0.005 + 0.9*M$r + rnorm(nrow(M), 0, 0.02)   # 포트 수익
  act <- a - M$r
  t_all <- mean(act)/(sd(act)/sqrt(length(act)))
  i2 <- M$yr < 2026
  t_ex <- mean(act[i2])/(sd(act[i2])/sqrt(sum(i2)))
  res[[rep]] <- data.table(t_all = t_all, t_ex = t_ex, ratio = t_ex/t_all)
}
R <- rbindlist(res)
say("  모의 200회: t(2026 포함) 중앙 %.3f · t(제외) 중앙 %.3f · **비율 중앙 %.4f**",
    median(R$t_all), median(R$t_ex), median(R$ratio))
say("  ⇒ 2026 제외 시 t 가 평균 %.1f%% **상승** (오염이 억누르고 있었다면)", 100*(median(R$ratio)-1))
say("  ★되살아날 수 있는 원 PORT_t 구간 = [%.3f, 2.95)", 2.95/median(R$ratio))

say("=== 4. 후보 필터 ===")
C <- fread(file.path(OUT, "cand_port_t.csv"))
lo <- 2.95/median(R$ratio)
say("  전체 후보 %d건 중 되살림 가능 구간 [%.3f, 2.95) 진입 = **%d건**",
    nrow(C), lo, C[max_near >= lo, .N])
if (C[max_near >= lo, .N]) print(C[max_near >= lo][order(-max_near)][, .(id, max_near, title = substr(title,1,44))])
say("=== 판정 ===")
say("  ⇒ %s", if (C[max_near >= lo, .N] == 0)
  "★되살림 가능 후보 0 — 오염의 PORT_t 억압력이 문턱 근방 실패를 뒤집기에 부족. 라운드 축소/폐기" else
  "재검 대상 확정 — P2 에서 실제 재측정")
fwrite(R, file.path(OUT, "p1_sim.csv"))
saveRDS(list(infl = infl, w = w, ratio = median(R$ratio), lo = lo), file.path(OUT, "p1.rds"))
say("=== P1 완료 ===")
