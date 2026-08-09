## FQ-143 P3 — 라벨 자격을 **PIT 정렬별로** 재측정 (착수 가부의 1차 관문)
##
## 왜 이 순서인가: 08-08 이 보고한 lift(1.16 / 1.97 / 3.19)는 "현행 국면 라벨"의 것인데,
##   그 라벨(unified_regime_signal.parquet)의 Date 는 **월말**이다. 월말 라벨을 그 달 홀딩에 쓰면
##   동월 look-ahead(2026-07-05/06 BearProb 실사고와 동일 계통)이고, 다음 달 홀딩에 써야 clean 이다.
##   ⇒ 자격 수치를 정렬별로 나란히 재고, **clean 정렬에서도 꼬리 자격이 남는지**를 먼저 본다.
##   여기서 무너지면 이 라운드는 측정 전에 끝난다(그 사실 자체가 산출).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
source(file.path(ROOT, "02_Infrastructure/contracts/label_eligibility_gate.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))

## ---- 1. 라벨 실측 ----
u <- as.data.table(read_parquet(file.path(ROOT, ".cache/unified_regime_signal.parquet")))
u[, Date := as.Date(Date)]; setorder(u, Date)
cat(sprintf("[P3-1] 라벨 원천: unified_regime_signal.parquet  nrow=%d  %s ~ %s\n", nrow(u), min(u$Date), max(u$Date)))
cat(sprintf("       Date 가 월말인 행: %d/%d\n",
            sum(format(u$Date, "%Y-%m") == format(u$Date, "%Y-%m") &
                as.integer(format(u$Date + 1, "%d")) == 1L), nrow(u)))
print(u[, .N, by = Category][order(-N)])
u[, ym := format(Date, "%Y-%m")]
u[, lab_on := Category %chin% c("CRISIS", "CAUTION")]
cat(sprintf("[P3-2] 라벨 ON(CRISIS∪CAUTION) = %d/%d = %.3f\n", sum(u$lab_on), nrow(u), mean(u$lab_on)))

## ---- 2. 시장 월수익 (사건 정의의 기준 계열) ----
bm <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
bm[, ym := format(Date, "%Y-%m")]
bmm <- bm[, .(bm_ret = as.numeric(Return.cumulative(xts(BM_Ret, order.by = Date)))), by = ym]
setorder(bmm, ym); bmm[, k := .I]
cat(sprintf("[P3-3] 벤치 월계열 n=%d (%s ~ %s)\n", nrow(bmm), min(bmm$ym), max(bmm$ym)))

## ---- 3. 정렬 2종 x 사건정의 3종 자격표 ----
## A_same : 월말 라벨 -> 같은 달 홀딩  (= 동월 look-ahead 정렬)
## B_clean: 월말 라벨 -> 다음 달 홀딩  (= C5 준수 정렬)
mk <- function(shift_m) {
  m <- merge(u[, .(ym, lab_on)], bmm[, .(ym, k)], by = "ym")
  m[, k_evt := k + shift_m]
  m <- merge(m, bmm[, .(k_evt = k, evt_ret = bm_ret, evt_ym = ym)], by = "k_evt")
  setorder(m, k); m[]
}
res <- list()
for (al in c("A_same", "B_clean")) {
  m <- mk(if (al == "A_same") 0L else 1L)
  for (thr in c(0, -0.05, -0.10)) {
    g <- label_eligibility(m$lab_on, m$evt_ret < thr)
    res[[length(res)+1L]] <- data.table(
      alignment = al, event = sprintf("ret < %.0f%%", thr*100), n = g$n, n_on = g$n_on,
      n_event = g$n_event, recall = g$recall, base = g$base_rate, lift = g$lift,
      fisher_p = g$fisher_p, verdict = g$verdict)
  }
}
tab <- rbindlist(res)
cat("\n=== [P3-4] 라벨 자격: 정렬 x 사건정의 (★ 08-08 수치의 정렬 교락 검증) ===\n")
print(tab[, .(alignment, event, n, n_on, n_event,
              recall = round(recall,4), base = round(base,4), lift = round(lift,3),
              p = signif(fisher_p,3), verdict)])

## ---- 4. 검정력 사전 판정 ----
cat("\n=== [P3-5] 검정력 사전 판정 (착수/폐기) ===\n")
## 오버레이 paired 차이 계열의 sd 는 25EW 스프레드가 아니라 |Δscale| x 시장수익 스케일이다.
## 외부 기준을 쓰되(자기 se 재진술 회피) 실제 설계에 맞춘 sd 를 실측으로 잡는다:
##   최대 가용 깊이(1.0 -> 0.5)를 라벨 ON 월에만 적용했을 때의 차이 계열 sd.
m <- mk(1L)
mm <- merge(m, bmm[, .(evt_ym = ym, r = bm_ret)], by = "evt_ym")
setorder(mm, k)
diff_series <- ifelse(mm$lab_on, -0.5 * mm$r, 0)      # 노출 절반 축소 시 수익 차이
sd_diff <- sd(diff_series)
cat(sprintf("  설계 sd 실측: 라벨 ON 월 노출 -50%% 시 paired 차이 계열 sd = %.5f (월)\n", sd_diff))
cat(sprintf("  ON 비율 p = %.4f, n = %d\n", mean(mm$lab_on), nrow(mm)))
for (des in c("full", "interaction")) {
  re <- required_effect(n = nrow(mm), t_threshold = 2.0, sd_monthly = sd_diff,
                        design = des, regime_frac = mean(mm$lab_on))
  cat(sprintf("  design=%-11s  eff_n=%7.1f  required_monthly=%+.5f  required_annual=%+.4f (%.2f%%/yr)\n",
              des, re$effective_n, re$required_monthly, re$required_annual, re$required_annual*100))
}
## 실현가능 효과의 상한 추정(사전, 부호 미사용): ON 월 시장수익 평균의 -50% 가 만들 수 있는 월평균 차이
ub <- abs(mean(diff_series))
cat(sprintf("  참고 — 이 설계가 만들 수 있는 |월평균 차이| (전표본 평균) = %.5f (%.2f%%/yr)\n", ub, ub*12*100))

## 269개월 배포 창으로 좁힌 경우
mm269 <- mm[evt_ym >= "2004-01" & evt_ym <= "2026-05"]
re269 <- required_effect(n = nrow(mm269), t_threshold = 2.0,
                         sd_monthly = sd(ifelse(mm269$lab_on, -0.5*mm269$r, 0)),
                         design = "full")
cat(sprintf("\n  [배포창 2004-01~2026-05] n=%d  ON=%d(%.3f)  required_monthly=%+.5f (%.2f%%/yr)\n",
            nrow(mm269), sum(mm269$lab_on), mean(mm269$lab_on), re269$required_monthly, re269$required_annual*100))

fwrite(tab, file.path(DIR, "p3_eligibility_table.csv"))
saveRDS(list(u = u, bmm = bmm, mm = mm, tab = tab), file.path(DIR, "p3.rds"))
cat("\n[P3 DONE]\n")
