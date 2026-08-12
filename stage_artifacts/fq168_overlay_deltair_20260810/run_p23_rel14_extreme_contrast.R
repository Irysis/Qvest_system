## P23 — rel14 를 **극단 대조**로 다시 묻는다 (P17a 재분석, 새 측정 없음)
## 사전등록(재분석 전 고정, 이 주석이 정본):
##  배경: P17a 가 rel14 를 **52 팩터 계열-간 상관**으로 물어 F3_FAILS(rho 0.162/-0.070, 임계 0.273).
##    그런데 계열-간 상관은 오늘 **6회 미달**한 설계 계열이고, 답을 낸 건 매번 극단/소수 대조였다.
##  ⇒ 같은 데이터에 **설계만 바꿔** 묻는다. 새 측정 없음 — p17a_predictor.csv 재분석.
##  예측(P16a 기전): rel14 높음 = 14~25 가 base 의 최고 구간 ⇒ 버리면 비쌈 ⇒ **swap_d 낮음**.
##  ★공유항: rel14_all 과 swap_all 은 둘 다 r14_25 를 담는다 ⇒ **홀/짝 교차만 판정에 쓴다**
##    (rel14_odd → swap_evn, rel14_evn → swap_odd). all-표본은 참고로만 출력.
##  ★1급 = 극단 대조(상위 k vs 하위 k 의 swap 평균차 + Welch t). k=5 사전고정(52의 ~10%).
##  ★2급 = 상관(P17a 가 이미 답한 것) — 판정에 쓰지 않는다.
##  ★음성 대조: rel14 를 무작위 치환해 같은 대조를 1000회 → 관측 차이의 순열 p.
##  판정:
##   G1_EXTREME_WORKS  : 양방향 교차 모두 상위k swap < 하위k swap ∧ 순열 p<0.05 (둘 중 하나 이상)
##   G2_ONE_DIRECTION  : 한 방향만 성립 — 설계 민감, 주장 불가
##   G3_NO_SIGNAL      : 둘 다 미달 → **rel14 는 설계를 바꿔도 안 선다**. P17a 확정, 밴드 예측자 미해결
##  ★자본 주장 없음. ★이 라운드는 P17a 를 뒤집는 게 아니라 **설계 민감도**를 재는 것이다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
SRC <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809/p17a_predictor.csv")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
stopifnot(file.exists(SRC))
D <- fread(SRC)
cat(sprintf("[입력 실측] 행 %d · 열 %s\n", nrow(D), paste(names(D), collapse=",")))
cat(sprintf("[입력 실측] rel14_all 범위 %.3f~%.3f · swap_all 범위 %.3f~%.3f\n",
            min(D$rel14_all), max(D$rel14_all), min(D$swap_all), max(D$swap_all)))

K <- 5L
contrast <- function(pred, outc, lab) {
  d <- data.table(p = pred, o = outc)[is.finite(p) & is.finite(o)]
  d <- d[order(-p)]
  hi <- head(d$o, K); lo <- tail(d$o, K)
  tt <- tryCatch(t.test(hi, lo), error = function(e) list(p.value = NA_real_, statistic = NA_real_))
  ## 순열 음성 대조 — 예측자를 섞어도 같은 크기 차이가 나오는가
  obs <- mean(hi) - mean(lo)
  set.seed(20260810L)
  perm <- replicate(1000L, { s <- sample(d$p); dd <- d[order(-s)]
                             mean(head(dd$o, K)) - mean(tail(dd$o, K)) })
  p_perm <- mean(abs(perm) >= abs(obs))
  list(label = lab, n = nrow(d), hi_mean = mean(hi), lo_mean = mean(lo), diff = obs,
       t = unname(tt$statistic), p_welch = tt$p.value, p_perm = p_perm,
       direction_ok = obs < 0)
}

cat("\n=== 1급: 극단 대조 (상위5 rel14 vs 하위5) ===\n")
cat("예측: rel14 높을수록 swap 낮음 ⇒ diff < 0\n\n")
res <- list(
  contrast(D$rel14_odd, D$swap_evn, "홀→짝 (교차·판정용)"),
  contrast(D$rel14_evn, D$swap_odd, "짝→홀 (교차·판정용)"),
  contrast(D$rel14_all, D$swap_all, "all→all (공유항 오염·참고만)")
)
R <- rbindlist(lapply(res, as.data.table), fill = TRUE)
for (r in res)
  cat(sprintf("%-28s n=%2d  상위5 %+7.3f  하위5 %+7.3f  diff **%+7.3f**  t %+5.2f  p_welch %.3f  p_perm %.3f  %s\n",
              r$label, r$n, r$hi_mean, r$lo_mean, r$diff, r$t, r$p_welch, r$p_perm,
              if (isTRUE(r$direction_ok)) "방향 O" else "방향 X"))

cross <- res[1:2]
ok_dir <- vapply(cross, function(r) isTRUE(r$direction_ok), TRUE)
ok_p   <- vapply(cross, function(r) isTRUE(r$p_perm < 0.05), TRUE)
verdict <- if (all(ok_dir) && any(ok_p)) "G1_EXTREME_WORKS" else
           if (any(ok_dir & ok_p))      "G2_ONE_DIRECTION" else "G3_NO_SIGNAL"
cat(sprintf("\n판정: **%s**  (교차 방향 %d/2 · 순열 유의 %d/2)\n", verdict, sum(ok_dir), sum(ok_p)))

cat("\n[2급·판정 아님] 상관 (P17a 가 이미 답함)\n")
for (nm in list(c("rel14_odd","swap_evn"), c("rel14_evn","swap_odd"), c("rel14_all","swap_all")))
  cat(sprintf("  spearman(%s, %s) = %+.3f\n", nm[1], nm[2],
              suppressWarnings(cor(D[[nm[1]]], D[[nm[2]]], method="spearman", use="complete.obs"))))

cat("\n[분포 점검] rel14 는 경계에 몰려 있는가 — 극단 대조가 성립할 여지\n")
for (v in c("rel14_all","rel14_odd","rel14_evn"))
  cat(sprintf("  %-10s  =0 %2d건 · =1 %2d건 · 중간 %2d건 (n=%d)\n", v,
              sum(D[[v]] <= 1e-9, na.rm=TRUE), sum(D[[v]] >= 1-1e-9, na.rm=TRUE),
              sum(D[[v]] > 1e-9 & D[[v]] < 1-1e-9, na.rm=TRUE), sum(is.finite(D[[v]]))))

write_json(list(verdict = verdict, k = K, n_base = nrow(D),
                cross_direction_ok = sum(ok_dir), cross_perm_sig = sum(ok_p),
                contrasts = R, source = "p17a_predictor.csv (재분석·새 측정 없음)"),
           file.path(OUT, "p23_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat(sprintf("\n=> %s\n", file.path(OUT, "p23_result.json")))
