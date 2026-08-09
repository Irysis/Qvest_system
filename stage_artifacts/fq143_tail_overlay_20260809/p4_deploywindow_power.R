## FQ-143 P4 — 배포창 자격 + 검정력 사전판정 (착수/폐기의 최종 관문)
##
## 세 가지를 한 실행에서 분리해 잰다(교락 방지):
##   (1) 자격을 **배포창(2004-01~2026-05, 269개월)** 에서 다시 — 전표본 자격은 pre-2004 편중일 수 있다.
##   (2) 자격을 **소비 대상 계열(ret_orig = 배포 base 전략수익)** 기준으로도 — 관문은 사이트가 쓰는 것을 재야 한다.
##   (3) 검정력: paired t 문턱 2.0 에 필요한 효과 vs 이 설계가 만들 수 있는 효과.
##       ★ 창을 나눠 비교할 때는 창-정합 후에만 대비를 주장한다(08-08 자가정정 규약).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
source(file.path(ROOT, "02_Infrastructure/contracts/label_eligibility_gate.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
S <- readRDS(file.path(DIR, "p3.rds")); u <- S$u; bmm <- S$bmm
p <- readRDS(file.path(DIR, "panel_p0.rds"))
setDT(p)

## ---- 홀딩월 = return_ym (P1 실측 확정). 라벨은 홀딩월 시작 '전' 월말 = return_ym 의 전월말 ----
p[, hold_ym := return_ym]
p[, sig_ym  := format(as.Date(paste0(return_ym, "-01")) - 1, "%Y-%m")]   # 전월
lab <- u[, .(sig_ym = ym, Category, lab_on)]
p2 <- merge(p, lab, by = "sig_ym", all.x = TRUE)
setorder(p2, hold_ym)
cat(sprintf("[P4-0] 배포 패널 %d행 중 라벨 결합 성공 %d행 (%s ~ %s)\n",
            nrow(p), sum(!is.na(p2$lab_on)), min(p2$hold_ym), max(p2$hold_ym)))
p2 <- p2[!is.na(lab_on)]
cat(sprintf("       배포창 라벨 ON = %d/%d = %.4f\n", sum(p2$lab_on), nrow(p2), mean(p2$lab_on)))

## 시장 월수익도 홀딩월에 정렬
p2 <- merge(p2, bmm[, .(hold_ym = ym, bm_ret)], by = "hold_ym", all.x = TRUE)
setorder(p2, hold_ym)

## ---- (1)+(2) 자격표: 창 x 기준계열 x 사건정의 ----
rows <- list()
add <- function(win, basis, ev_lab, on, evt) {
  g <- label_eligibility(on, evt)
  rows[[length(rows)+1L]] <<- data.table(window = win, basis = basis, event = ev_lab,
    n = g$n, n_on = g$n_on, n_evt = g$n_event, recall = g$recall, base = g$base_rate,
    lift = g$lift, p = g$fisher_p, verdict = g$verdict)
}
for (thr in c(0, -0.05, -0.10)) {
  el <- sprintf("< %.0f%%", thr*100)
  add("deploy 2004-01~2026-05", "market bm_ret", el, p2$lab_on, p2$bm_ret < thr)
  add("deploy 2004-01~2026-05", "base ret_orig", el, p2$lab_on, p2$ret_orig < thr)
}
## 창-정합 대비: 전표본(1990~)을 같은 basis(market)로
mfull <- merge(u[, .(ym, lab_on)], bmm[, .(ym, k = .I)], by = "ym")
mfull[, k_evt := k + 1L]
mfull <- merge(mfull, bmm[, .(k_evt = .I, evt_ret = bm_ret)], by = "k_evt"); setorder(mfull, k)
for (thr in c(0, -0.05, -0.10))
  add("full 1990-11~2026-06", "market bm_ret", sprintf("< %.0f%%", thr*100), mfull$lab_on, mfull$evt_ret < thr)

tab <- rbindlist(rows)
cat("\n=== [P4-1] 자격표 (전부 C5-clean 정렬: 월말라벨 -> 다음달 홀딩) ===\n")
print(tab[, .(window, basis, event, n, n_on, n_evt, recall = round(recall,4),
              base = round(base,4), lift = round(lift,3), p = signif(p,3), verdict)])

## ---- 자격 검정 자체의 검정력: n_on 이 작을 때 어떤 lift 가 검출 가능한가 ----
cat("\n=== [P4-2] 자격 검정의 검출력 (배포창 n_on 이 작다 — null 을 '무자격'으로 읽지 않기 위해) ===\n")
pw <- function(n, n_on, base, lift, nsim = 4000L) {
  n_evt <- round(base * n)
  if (n_evt < 1 || n_on < 1) return(NA_real_)
  ## 라벨 ON 에서 사건확률 = base*lift 인 대안가설 하 fisher 단측 검출률
  set.seed(20260809)
  pon <- min(base * lift, 0.999)
  hits <- vapply(seq_len(nsim), function(i) {
    on_evt  <- rbinom(1, n_on, pon)
    off_evt <- rbinom(1, n - n_on, max((base*n - pon*n_on) / (n - n_on), 0))
    tb <- matrix(c(on_evt, n_on - on_evt, off_evt, (n - n_on) - off_evt), nrow = 2)
    pv <- tryCatch(fisher.test(tb, alternative = "greater")$p.value, error = function(e) 1)
    as.numeric(pv < 0.05)
  }, numeric(1))
  mean(hits)
}
for (thr in c(0, -0.05, -0.10)) {
  b <- mean(p2$bm_ret < thr); non <- sum(p2$lab_on); nn <- nrow(p2)
  cat(sprintf("  배포창 event %-8s base=%.4f n_on=%d : 검출력  lift1.5=%.2f  lift2.0=%.2f  lift2.7=%.2f  lift3.5=%.2f\n",
              sprintf("< %.0f%%", thr*100), b, non,
              pw(nn, non, b, 1.5), pw(nn, non, b, 2.0), pw(nn, non, b, 2.7), pw(nn, non, b, 3.5)))
}

## ---- (3) 설계 검정력: 실제 오버레이 차이 계열 ----
cat("\n=== [P4-3] 설계 검정력 — 배포창에서 이 레버가 만들 수 있는 효과 ===\n")
cat(sprintf("  E[bm_ret | 라벨ON]  = %+.5f (n=%d)\n", mean(p2$bm_ret[p2$lab_on]), sum(p2$lab_on)))
cat(sprintf("  E[bm_ret | 라벨OFF] = %+.5f (n=%d)\n", mean(p2$bm_ret[!p2$lab_on]), sum(!p2$lab_on)))
cat(sprintf("  E[ret_orig | 라벨ON]  = %+.5f\n", mean(p2$ret_orig[p2$lab_on])))
cat(sprintf("  E[ret_orig | 라벨OFF] = %+.5f\n", mean(p2$ret_orig[!p2$lab_on])))
p2[, scale_cur := beta_R05 * m4]
for (depth in c(0.25, 0.50, 0.70)) {
  d <- ifelse(p2$lab_on, -depth * p2$ret_orig, 0)      # base 대비 차이 (비용 전)
  se <- sd(d)/sqrt(length(d)) * NW_INFLATION_DEFAULT
  cat(sprintf("  깊이 -%.0f%%: 월평균차이 %+.5f  sd %.5f  근사 t %+.3f  (필요효과 t=2: %+.5f)\n",
              depth*100, mean(d), sd(d), mean(d)/se, 2.0*se))
}
fwrite(tab, file.path(DIR, "p4_eligibility_windows.csv"))
saveRDS(p2, file.path(DIR, "p4_panel_labeled.rds"))
cat("\n[P4 DONE]\n")
