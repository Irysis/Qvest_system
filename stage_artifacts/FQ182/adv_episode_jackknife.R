## FQ-182 적대검증 — 렌즈: episode_jackknife
## 목적: "낙폭 조건부 forward 왜도 반전" 이 소수 에피소드(2008 GFC · 2020 COVID)에 의존하는가.
## 반증 기준(사전 고정):
##   R1) 1~2개 에피소드 제거로 skew diff **부호가 뒤집힌다**            -> refuted
##   R2) 1~2개 에피소드 제거로 ratio(=|diff|/2se) 가 **0.5 미만**으로 떨어진다 -> refuted
##   R3) 개별 에피소드 왜도가 **양(+)인 것이 다수결(>50%)이 아니다**       -> 취약(=refuted 쪽)
## 부수: 에피소드-군집 부트스트랩(에피소드 단위 재표본) se 로 ratio 재산출.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv] ", fmt, "\n"), ...)); flush.console() }

## ---- 0. 입력 실측 (측정 첫 출력 = 입력) ---------------------------------------
D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
say("=== 입력 실측 (원본 p0.rds$D) ===")
say("  행수 %d · 관측단위 daily · 기간 %s ~ %s · 컬럼 %s",
    nrow(D), as.character(min(D$Date)), as.character(max(D$Date)), paste(names(D), collapse=","))
say("  BM_Ret sd %.5f · dd252 범위 [%.4f, %.4f] · NA(BM_Ret) %d · NA(dd252) %d",
    sd(D$BM_Ret), min(D$dd252), max(D$dd252), sum(is.na(D$BM_Ret)), sum(is.na(D$dd252)))
## fwd1 을 직접 재구성해 저장분과 대조 (남의 파생값 신뢰 금지)
D[, fwd1_re := shift(BM_Ret, 1L, type = "lead")]
chk <- D[!is.na(fwd1) | !is.na(fwd1_re)]
say("  ★fwd1 재구성 대조: 불일치 %d건 / NA패턴 불일치 %d건",
    sum(abs(chk$fwd1 - chk$fwd1_re) > 1e-12, na.rm = TRUE),
    sum(is.na(chk$fwd1) != is.na(chk$fwd1_re)))
D[, fwd1 := fwd1_re][, fwd1_re := NULL]
D <- D[!is.na(fwd1) & !is.na(dd252)]
say("  분석 표본 %d일 (fwd1 NA 제거) · fwd1 sd %.5f", nrow(D), sd(D$fwd1))
say("  ★정렬: 신호 dd252[t] -> 대상 fwd1 = BM_Ret[t+1]. 동시점 미사용.")

## ---- 1. 통계량 (p1 과 동일 정의) -----------------------------------------------
skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/n/s^4-3}

## ---- 2. 블록 부트스트랩 (블록 60일, keep 마스크 지원) ---------------------------
## keep=FALSE 인 행(제거 에피소드)은 재표본 후 탈락시킨다 -> 시계열 의존구조 유지.
bb_skew <- function(x, on, keep, B = 400L, blk = 60L, seed = 20260809L) {
  set.seed(seed)
  n <- length(x); nb <- ceiling(n/blk); starts <- seq_len(max(1, n-blk+1))
  o <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    kb <- keep[idx]; idx <- idx[kb]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) next
    o[b] <- skew1(xb[ob]) - skew1(xb[!ob])
  }
  o[is.finite(o)]
}

## ---- 3. 에피소드 분해 (60일-gap 병합) ------------------------------------------
make_episodes <- function(on, gap = 60L) {
  i <- which(on); if (!length(i)) return(data.table())
  brk <- c(TRUE, diff(i) > gap)          # 관측(거래일) 인덱스 간격 > gap 이면 새 에피소드
  ep  <- cumsum(brk)
  data.table(row = i, ep = ep)
}

## ---- 4. 메인 루프 ---------------------------------------------------------------
LOO_all <- list(); PROF_all <- list(); SUM_all <- list()
for (thr in c(-0.20, -0.30)) {
  on  <- D$dd252 <= thr
  x   <- D$fwd1
  keep_all <- rep(TRUE, nrow(D))
  base_diff <- skew1(x[on]) - skew1(x[!on])
  BBb  <- bb_skew(x, on, keep_all, B = 400L, blk = 60L)
  se_b <- sd(BBb)
  ratio_b <- abs(base_diff)/(2*se_b)
  say("")
  say("=========== dd252 <= %.0f%% ===========", thr*100)
  say("  기준선 재측정: skew ON %+.4f (n=%d) · OFF %+.4f (n=%d) · diff %+.4f",
      skew1(x[on]), sum(on), skew1(x[!on]), sum(!on), base_diff)
  say("  블록부트(60일,400회) se %.4f · ratio %.3f", se_b, ratio_b)

  E <- make_episodes(on, 60L)
  ne <- max(E$ep)
  say("  ★에피소드 분해(60거래일 gap 병합): %d개 · ON 총 %d일", ne, nrow(E))

  ## 에피소드 프로파일
  prof <- E[, {
    r <- row
    v <- x[r]
    .(n = length(r), start = as.character(D$Date[min(r)]), end = as.character(D$Date[max(r)]),
      dd_min = min(D$dd252[r]), skew_ep = skew1(v), sd_ep = sd(v), mean_ep = mean(v))
  }, by = ep]
  prof[, thr := thr*100]
  prof[, share := n/sum(n)]
  say("  --- 에피소드별 개별 왜도 ---")
  for (k in seq_len(nrow(prof))) say("   ep%02d %s~%s n=%4d (%4.1f%%) dd_min %+.3f skew %+8.4f sd %.4f",
      prof$ep[k], prof$start[k], prof$end[k], prof$n[k], 100*prof$share[k],
      prof$dd_min[k], prof$skew_ep[k], prof$sd_ep[k])
  npos <- sum(prof$skew_ep > 0, na.rm = TRUE); nval <- sum(is.finite(prof$skew_ep))
  wpos <- sum(prof$n[which(prof$skew_ep > 0)])/sum(prof$n)
  say("  ★개별 왜도 양(+) 에피소드 = %d / %d (%.1f%%) · 일수 가중 %.1f%%",
      npos, nval, 100*npos/nval, 100*wpos)
  say("  ★OFF 왜도 = %+.4f (전 에피소드 대비 기준)", skew1(x[!on]))

  ## LOO-1
  loo <- rbindlist(lapply(seq_len(ne), function(e) {
    rm_rows <- E[ep == e, row]
    keep <- keep_all; keep[rm_rows] <- FALSE
    on2 <- on & keep
    d2  <- skew1(x[on2]) - skew1(x[!on & keep])
    BB2 <- bb_skew(x, on, keep, B = 400L, blk = 60L)
    data.table(thr = thr*100, drop_k = 1L, dropped = sprintf("ep%02d", e),
               label = paste0(prof$start[prof$ep==e], "~", prof$end[prof$ep==e]),
               n_dropped = length(rm_rows), n_on = sum(on2),
               skew_on = skew1(x[on2]), skew_off = skew1(x[!on & keep]),
               diff = d2, se = sd(BB2), ratio = abs(d2)/(2*sd(BB2)),
               sign_flip = (d2 * base_diff) < 0,
               delta_vs_base = d2 - base_diff)
  }))
  say("  --- LOO-1 (에피소드 1개 제거) ---")
  print(loo[order(diff)][, .(dropped, label, n_dropped, diff = round(diff,4),
                             se = round(se,4), ratio = round(ratio,3), sign_flip)])
  say("  ★LOO-1 최소 diff %+.4f (%s) · 최소 ratio %.3f · 부호반전 %d건 · ratio<0.5 %d건",
      min(loo$diff), loo[which.min(diff), dropped], min(loo$ratio),
      sum(loo$sign_flip), sum(loo$ratio < 0.5))

  ## LOO-2 : 영향력 상위 조합 전수 (에피소드 수가 적으므로 모든 쌍)
  pairs <- t(combn(ne, 2))
  loo2 <- rbindlist(lapply(seq_len(nrow(pairs)), function(p) {
    es <- pairs[p, ]
    rm_rows <- E[ep %in% es, row]
    keep <- keep_all; keep[rm_rows] <- FALSE
    on2 <- on & keep
    d2  <- skew1(x[on2]) - skew1(x[!on & keep])
    data.table(thr = thr*100, drop_k = 2L,
               dropped = sprintf("ep%02d+ep%02d", es[1], es[2]),
               label = paste0(prof$start[prof$ep==es[1]], "|", prof$start[prof$ep==es[2]]),
               n_dropped = length(rm_rows), n_on = sum(on2),
               skew_on = skew1(x[on2]), skew_off = skew1(x[!on & keep]),
               diff = d2, se = NA_real_, ratio = NA_real_,
               sign_flip = (d2 * base_diff) < 0, delta_vs_base = d2 - base_diff)
  }))
  ## 최악(=diff 최소) 5쌍만 부트 se 산출
  worst <- loo2[order(diff)][1:min(5, .N)]
  for (w in seq_len(nrow(worst))) {
    es <- as.integer(regmatches(worst$dropped[w], gregexpr("[0-9]+", worst$dropped[w]))[[1]])
    rm_rows <- E[ep %in% es, row]; keep <- keep_all; keep[rm_rows] <- FALSE
    BB2 <- bb_skew(x, on, keep, B = 400L, blk = 60L)
    worst$se[w] <- sd(BB2); worst$ratio[w] <- abs(worst$diff[w])/(2*sd(BB2))
  }
  say("  --- LOO-2 최악 5쌍 (전 %d쌍 중) ---", nrow(loo2))
  print(worst[, .(dropped, label, n_dropped, diff = round(diff,4),
                  se = round(se,4), ratio = round(ratio,3), sign_flip)])
  say("  ★LOO-2 최소 diff %+.4f · 부호반전 %d/%d쌍 · (최악5중) 최소 ratio %.3f",
      min(loo2$diff), sum(loo2$sign_flip), nrow(loo2), min(worst$ratio, na.rm=TRUE))

  ## 에피소드-군집 부트스트랩 (ON 을 에피소드 단위로 재표본)
  set.seed(20260809L)
  Bd <- 1000L; off_skew <- skew1(x[!on]); ed <- rep(NA_real_, Bd)
  epl <- split(E$row, E$ep)
  for (b in seq_len(Bd)) {
    pick <- sample(seq_len(ne), ne, replace = TRUE)
    rr <- unlist(epl[pick], use.names = FALSE)
    ed[b] <- skew1(x[rr]) - off_skew
  }
  se_ep <- sd(ed, na.rm = TRUE)
  say("  ★에피소드-군집 부트(ON 에피소드 재표본 1000회) se %.4f -> ratio %.3f · diff<0 비율 %.3f",
      se_ep, abs(base_diff)/(2*se_ep), mean(ed < 0, na.rm = TRUE))

  SUM_all[[length(SUM_all)+1L]] <- data.table(
    thr = thr*100, n_on = sum(on), n_off = sum(!on), n_ep = ne,
    base_diff = base_diff, se_block = se_b, ratio_block = ratio_b,
    se_episode_cluster = se_ep, ratio_episode_cluster = abs(base_diff)/(2*se_ep),
    ep_pos_skew = npos, ep_total = nval, ep_pos_frac = npos/nval, ep_pos_dayweight = wpos,
    loo1_min_diff = min(loo$diff), loo1_min_ratio = min(loo$ratio),
    loo1_sign_flips = sum(loo$sign_flip), loo1_ratio_lt_05 = sum(loo$ratio < 0.5),
    loo2_min_diff = min(loo2$diff), loo2_sign_flips = sum(loo2$sign_flip),
    loo2_worst5_min_ratio = min(worst$ratio, na.rm = TRUE))
  LOO_all[[length(LOO_all)+1L]] <- rbind(loo, worst, loo2[!dropped %in% worst$dropped])
  PROF_all[[length(PROF_all)+1L]] <- prof
}

LOO <- rbindlist(LOO_all); PROF <- rbindlist(PROF_all); SUM <- rbindlist(SUM_all)
fwrite(LOO,  file.path(OUT, "adv_episode_jackknife.csv"))
fwrite(PROF, file.path(OUT, "adv_episode_profile.csv"))
fwrite(SUM,  file.path(OUT, "adv_episode_summary.csv"))

say("")
say("=========== ★판정 (사전 고정 기준) ===========")
for (i in seq_len(nrow(SUM))) {
  s <- SUM[i]
  r1 <- s$loo1_sign_flips > 0 || s$loo2_sign_flips > 0
  r2 <- s$loo1_ratio_lt_05 > 0 || (is.finite(s$loo2_worst5_min_ratio) && s$loo2_worst5_min_ratio < 0.5)
  r3 <- s$ep_pos_frac <= 0.5
  say(" thr %.0f%% : R1(부호반전) %s · R2(ratio<0.5) %s · R3(양왜도 비다수결) %s -> %s",
      s$thr, ifelse(r1,"YES","no"), ifelse(r2,"YES","no"), ifelse(r3,"YES","no"),
      ifelse(r1||r2||r3, "REFUTED", "survives"))
}
print(SUM)
say("=== adv_episode_jackknife 완료 ===")
