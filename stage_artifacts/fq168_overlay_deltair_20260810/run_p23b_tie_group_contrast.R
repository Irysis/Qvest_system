## P23b — 동점군 대조 (P23 의 자기 결함 수리)
## 사전등록(측정 전 고정):
##  P23 의 결함: rel14 는 **경계 동점**이 크다(odd: 0 에 12건, 1 에 16건).
##    "상위5" 는 16개 동점 중 **임의 5개**라 대조가 정의되지 않는다 — 방향 불안정(+3.296/-1.231)의
##    상당부분이 이 임의성일 수 있다. ⇒ 동점군 **전체**를 군으로 쓴다(임의 선택 제거).
##  대조: rel14 == 1 인 base 전체  vs  rel14 == 0 인 base 전체.
##    (rel14=1 = 14~25 가 base 의 **최고** 구간 / =0 = **최저** 구간 — 기전 예측이 가장 선명한 두 극)
##  예측: rel14=1 군의 swap 이 rel14=0 군보다 **낮다**(diff<0).
##  ★공유항 통제 = 홀/짝 교차만 판정(rel14_odd 로 군 정의 → swap_evn 비교, 및 그 반대).
##  ★음성 대조 = 같은 군 크기로 무작위 분할 1000회 순열 p.
##  ★검정력 사전 산출: 관측 sd 로 최소검출차를 먼저 출력한다(오늘 저검정력 null 3회).
##  판정:
##   H1_TIE_GROUPS_WORK : 양방향 diff<0 ∧ 순열 p<0.05 최소 1방향
##   H2_ONE_DIRECTION   : 한 방향만
##   H3_NO_SIGNAL       : 미달 → rel14 는 **군 정의를 고쳐도 안 선다**. 밴드 예측자 미해결 확정
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
D <- fread(file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809/p17a_predictor.csv"))
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
cat(sprintf("[입력 실측] %d 행\n", nrow(D)))

tie_contrast <- function(pv, ov, lab) {
  d <- data.table(p = D[[pv]], o = D[[ov]])[is.finite(p) & is.finite(o)]
  hi <- d[p >= 1 - 1e-9, o]; lo <- d[p <= 1e-9, o]
  if (length(hi) < 3L || length(lo) < 3L)
    return(list(label = lab, n_hi = length(hi), n_lo = length(lo), skip = TRUE))
  obs <- mean(hi) - mean(lo)
  pooled <- c(hi, lo); nh <- length(hi)
  set.seed(20260810L)
  perm <- replicate(1000L, { s <- sample(pooled); mean(s[seq_len(nh)]) - mean(s[-seq_len(nh)]) })
  ## 최소검출차 (양측 0.05, 순열 분포의 97.5 분위)
  mde <- quantile(abs(perm), 0.95, names = FALSE)
  list(label = lab, n_hi = nh, n_lo = length(lo), hi_mean = mean(hi), lo_mean = mean(lo),
       diff = obs, p_perm = mean(abs(perm) >= abs(obs)), mde = mde,
       direction_ok = obs < 0, skip = FALSE)
}

cat("\n=== 동점군 대조: rel14==1 (14~25 가 최고구간) vs rel14==0 (최저구간) ===\n")
cat("예측: diff < 0  (최고구간을 버리면 비싸다)\n\n")
res <- list(tie_contrast("rel14_odd", "swap_evn", "홀군→짝결과 (판정)"),
            tie_contrast("rel14_evn", "swap_odd", "짝군→홀결과 (판정)"),
            tie_contrast("rel14_all", "swap_all", "all→all (공유항 오염·참고)"))
for (r in res) {
  if (isTRUE(r$skip)) { cat(sprintf("%-26s SKIP (군 크기 %d/%d)\n", r$label, r$n_hi, r$n_lo)); next }
  cat(sprintf("%-26s n %2d vs %2d  hi %+7.3f  lo %+7.3f  diff **%+7.3f**  p_perm %.3f  최소검출차 %.3f  %s\n",
              r$label, r$n_hi, r$n_lo, r$hi_mean, r$lo_mean, r$diff, r$p_perm, r$mde,
              if (isTRUE(r$direction_ok)) "방향 O" else "방향 X"))
}
cross <- Filter(function(r) !isTRUE(r$skip), res[1:2])
ok_dir <- vapply(cross, function(r) isTRUE(r$direction_ok), TRUE)
ok_p   <- vapply(cross, function(r) isTRUE(r$p_perm < 0.05), TRUE)
verdict <- if (length(cross) == 2L && all(ok_dir) && any(ok_p)) "H1_TIE_GROUPS_WORK" else
           if (any(ok_dir & ok_p)) "H2_ONE_DIRECTION" else "H3_NO_SIGNAL"
cat(sprintf("\n판정: **%s**  (방향 %d/%d · 순열 유의 %d/%d)\n",
            verdict, sum(ok_dir), length(cross), sum(ok_p), length(cross)))

cat("\n[검정력] 관측 diff 가 최소검출차보다 작으면 '기각'이 아니라 '못 봄'이다\n")
for (r in cross)
  cat(sprintf("  %-26s |diff| %.3f vs 최소검출차 %.3f → %s\n", r$label, abs(r$diff), r$mde,
              if (abs(r$diff) < r$mde) "**해상도 아래**" else "해상도 위"))

cat("\n[교차 안정성] 홀/짝 군 정의가 서로 얼마나 일치하는가 — 군 자체가 흔들리면 대조가 무의미\n")
a <- D$rel14_odd >= 1-1e-9; b <- D$rel14_evn >= 1-1e-9
cat(sprintf("  rel14==1 군: 홀 %d · 짝 %d · **교집합 %d** (Jaccard %.3f)\n",
            sum(a, na.rm=TRUE), sum(b, na.rm=TRUE), sum(a & b, na.rm=TRUE),
            sum(a & b, na.rm=TRUE) / max(1L, sum(a | b, na.rm=TRUE))))

write_json(list(verdict = verdict, contrasts = rbindlist(lapply(res, as.data.table), fill=TRUE),
                note = "P23 의 임의-상위k 결함을 동점군 전체로 수리한 판본"),
           file.path(OUT, "p23b_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
