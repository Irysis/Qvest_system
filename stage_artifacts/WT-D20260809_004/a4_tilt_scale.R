## A4 — 틸트의 수치 스케일 진단 (★수익률 미사용 — 신호 패널만. 결과 엿보기 아님)
## 목적: exp(λ·β_s·infl) 가 정원 n_s 를 실제로 움직이는가. 움직이지 못하면 층2 null 은
##       기전 부재가 아니라 **산술적 불활성**이며, 그 구별을 arm 측정 *전에* 해야 한다.
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
say <- function(fmt, ...) cat(sprintf(paste0("[A4] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds")); L <- readRDS(file.path(OUT, "layers.rds"))
ELIG <- P$ELIG; BETA <- L$BETA; INF <- L$INF

## base_s = 월별 자격 유니버스 내 섹터 종목수 비중
BASE <- ELIG[, .(n_s = .N), by = .(sig_date = Date, Sector)]
BASE[, base := n_s / sum(n_s), by = sig_date]

D <- merge(BASE, BETA[, .(sig_date, Sector, beta)], by = c("sig_date","Sector"))
D <- merge(D, INF[, .(sig_date, infl)], by = "sig_date")
D <- D[!is.na(beta) & !is.na(infl)]
say("틸트 입력 패널 %d행 · sig_date %d (%s ~ %s) · 섹터/월 평균 %.1f",
    nrow(D), uniqueN(D$sig_date), as.character(min(D$sig_date)), as.character(max(D$sig_date)),
    nrow(D)/uniqueN(D$sig_date))

## 섹터 횡단면 z 표준화 β (스케일 정규화판)
D[, zbeta := { s <- sd(beta); if (is.finite(s) && s > 0) (beta - mean(beta))/s else 0 }, by = sig_date]

say("")
say("=== 지수 인자 |λ·β·infl| 의 크기 ===")
for (lam in c(0.5, 1.0)) {
  say("  λ=%.1f  raw β : |exp| 중앙 %.4f · 95분위 %.4f · 최대 %.4f  →  승수 범위 [%.3f, %.3f]",
      lam, median(abs(lam*D$beta*D$infl)), quantile(abs(lam*D$beta*D$infl), .95),
      max(abs(lam*D$beta*D$infl)), exp(-max(abs(lam*D$beta*D$infl))), exp(max(abs(lam*D$beta*D$infl))))
  say("  λ=%.1f  z β   : |exp| 중앙 %.4f · 95분위 %.4f · 최대 %.4f  →  승수 범위 [%.3f, %.3f]",
      lam, median(abs(lam*D$zbeta*D$infl)), quantile(abs(lam*D$zbeta*D$infl), .95),
      max(abs(lam*D$zbeta*D$infl)), exp(-max(abs(lam*D$zbeta*D$infl))), exp(max(abs(lam*D$zbeta*D$infl))))
}

## 정원 배분기 (largest remainder, 섹터 자격종목수 상한)
alloc <- function(w, cap, total = 25L) {
  w <- w / sum(w)
  q <- w * total
  n <- pmin(floor(q), cap)
  rem <- total - sum(n)
  if (rem > 0) {
    fr <- q - floor(q); fr[n >= cap] <- -1
    ord <- order(-fr)
    i <- 1L
    while (rem > 0 && i <= length(ord)) {
      k <- ord[i]
      if (n[k] < cap[k]) { n[k] <- n[k] + 1L; rem <- rem - 1L }
      i <- i + 1L
      if (i > length(ord) && rem > 0) { ord <- order(-(cap - n)); i <- 1L
        if (all(n >= cap)) break }
    }
  }
  as.integer(n)
}

say("")
say("=== 정원 n_s 가 λ=0 대비 실제로 바뀌는가 (Σ|Δn_s|/2 = 교체 슬롯 수) ===")
res <- rbindlist(lapply(c("raw","z"), function(bk) rbindlist(lapply(c(0.5, 1.0), function(lam) {
  x <- D[, {
    b <- if (bk == "raw") beta else zbeta
    w0 <- base
    w1 <- base * exp(lam * b * infl)
    n0 <- alloc(w0, n_s); n1 <- alloc(w1, n_s)
    .(swap = sum(abs(n1 - n0))/2, n_eff0 = sum(n0 > 0), n_eff1 = sum(n1 > 0))
  }, by = sig_date]
  data.table(beta_kind = bk, lambda = lam, swap_mean = mean(x$swap), swap_med = median(x$swap),
             swap_max = max(x$swap), zero_swap_months_pct = 100*mean(x$swap == 0),
             n_eff_mean = mean(x$n_eff1))
}))))
print(res)

say("")
say("★판독: raw β 판에서 교체 슬롯이 0 인 달의 비율이 높으면 λ 그리드가 산술적으로 불활성이다.")
say("  그 경우의 층2 null 은 '기전 부재'가 아니라 '틸트가 25슬롯 격자를 넘지 못함' 이다.")

write_json(list(generated_at = as.character(Sys.time()),
                purpose = "틸트 스케일 진단 — 수익률 미사용",
                exponent_scale = list(
                  raw_beta_abs_median_l1 = median(abs(D$beta*D$infl)),
                  z_beta_abs_median_l1 = median(abs(D$zbeta*D$infl))),
                quota_divergence = res),
           file.path(OUT, "a4_tilt_scale.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(list(BASE = BASE, D = D, alloc = alloc), file.path(OUT, "tilt_inputs.rds"))
say("저장 완료")
