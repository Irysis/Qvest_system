## FQ-182 적대검증 P2 — LOO 가 통과했으므로 **더 날카로운 축**으로 공격한다.
## P1(LOO) 결과: 부호반전 0 · ratio<0.5 0 · 양왜도 다수결 통과 -> 사전기준 미충족.
## 그러나 P1 이 드러낸 취약 신호 2개를 P2 가 정면으로 시험한다:
##   A) 영향력이 **최근 live 에피소드(2026-07~08, 20일)** 에 극단 집중 (효과의 31~43%)
##   B) 적률 왜도는 3제곱 -> 극단 관측 소수에 지배될 수 있다 (강건 왜도로 재확인)
## 추가 축:
##   C) 혼합(mixture) 인공물 — 에피소드 내 표준화 후에도 왜도 반전이 남는가
##   D) 시점-절단 안정성 — 2019년/2007년에 측정했어도 같은 결론이 나왔는가
##   E) 단일-일(delete-1) 최대 영향력
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[!is.na(fwd1) & !is.na(dd252)]
say("=== 입력 실측 === %d일 · %s ~ %s · fwd1 sd %.5f", nrow(D),
    as.character(min(D$Date)), as.character(max(D$Date)), sd(D$fwd1))

skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
## 강건 왜도 2종 (극단 3제곱 의존 제거)
bowley <- function(v){q<-quantile(v,c(.25,.5,.75),names=FALSE);if(q[3]-q[1]<=0)return(NA_real_);(q[3]+q[1]-2*q[2])/(q[3]-q[1])}
qskew  <- function(v,p=.05){q<-quantile(v,c(p,.5,1-p),names=FALSE);if(q[3]-q[1]<=0)return(NA_real_);(q[3]+q[1]-2*q[2])/(q[3]-q[1])}
make_episodes <- function(on, gap = 60L) { i<-which(on); if(!length(i)) return(NULL)
  data.table(row=i, ep=cumsum(c(TRUE, diff(i)>gap))) }

res <- list()
for (thr in c(-0.20, -0.30)) {
  on <- D$dd252 <= thr; x <- D$fwd1
  E  <- make_episodes(on); ne <- max(E$ep)
  base <- skew1(x[on]) - skew1(x[!on])
  say(""); say("=========== dd252 <= %.0f%% (ON %d일 · %d에피소드) ===========", thr*100, sum(on), ne)
  say(" 기준 적률왜도 diff %+.4f", base)

  ## ---- A) 영향력 집중도 ----------------------------------------------------
  infl <- rbindlist(lapply(seq_len(ne), function(e){
    r <- E[ep==e, row]; keep <- rep(TRUE, nrow(D)); keep[r] <- FALSE
    d <- skew1(x[on & keep]) - skew1(x[!on & keep])
    data.table(ep=e, n=length(r), day_share=length(r)/sum(on),
               start=as.character(D$Date[min(r)]), end=as.character(D$Date[max(r)]),
               d_drop=d, infl=base-d, infl_share=(base-d)/base)}))
  setorder(infl, -infl)
  say(" --- A) 영향력 상위 4 (효과 기여 / 일수 비중) ---")
  for (k in 1:4) say("   ep%02d %s~%s n=%4d 일수%5.1f%% -> 효과기여 %+6.1f%% (배율 %5.1fx)",
      infl$ep[k], infl$start[k], infl$end[k], infl$n[k], 100*infl$day_share[k],
      100*infl$infl_share[k], infl$infl_share[k]/infl$day_share[k])
  say("   ★상위1 기여 %.1f%% · 상위2 누적 %.1f%% (일수 비중 %.1f%%)",
      100*infl$infl_share[1], 100*sum(infl$infl_share[1:2]), 100*sum(infl$day_share[1:2]))

  ## ---- A2) live(미완결) 에피소드 제거 = 2026-06 이전으로 절단 ----------------
  cut_live <- as.Date("2026-06-30")
  Dl <- D[Date <= cut_live]; onl <- Dl$dd252 <= thr
  d_live <- skew1(Dl$fwd1[onl]) - skew1(Dl$fwd1[!onl])
  say(" ★A2) live 에피소드 제외(<=2026-06-30, ON %d일): diff %+.4f (기준 %+.4f, %+.1f%%)",
      sum(onl), d_live, base, 100*(d_live/base-1))

  ## ---- B) 강건 왜도 ---------------------------------------------------------
  bw <- bowley(x[on]) - bowley(x[!on]); qs <- qskew(x[on]) - qskew(x[!on])
  say(" --- B) 강건 왜도 (극단 3제곱 비의존) ---")
  say("   Bowley  ON %+.4f OFF %+.4f diff %+.4f", bowley(x[on]), bowley(x[!on]), bw)
  say("   Q5/95   ON %+.4f OFF %+.4f diff %+.4f", qskew(x[on]), qskew(x[!on]), qs)
  ## 윈저라이즈 1% 후 적률왜도
  w <- function(v,p=.01){q<-quantile(v,c(p,1-p),names=FALSE);pmin(pmax(v,q[1]),q[2])}
  wm <- skew1(w(x[on])) - skew1(w(x[!on]))
  say("   윈저1%% 적률왜도 diff %+.4f (기준 %+.4f, 잔존 %.0f%%)", wm, base, 100*wm/base)

  ## ---- C) 혼합 인공물 검정: 그룹 내 표준화 후 왜도 ---------------------------
  ## ON = 에피소드 단위, OFF = 에피소드 사이 구간 단위. n>=30 그룹만 (양측 동일 규칙).
  offrun <- rle(!on); offid <- rep(seq_along(offrun$lengths), offrun$lengths)
  zpool <- function(idx, gid) {
    dt <- data.table(v = x[idx], g = gid)
    dt[, n := .N, by = g][n >= 30]
    dt[, z := (v - mean(v))/sd(v), by = g]
    list(z = dt$z, ng = uniqueN(dt$g), n = nrow(dt))
  }
  zon  <- zpool(E$row, E$ep)
  offi <- which(!on); zoff <- zpool(offi, offid[offi])
  say(" --- C) 그룹 내 표준화 후 왜도 (혼합 인공물 제거) ---")
  say("   ON  표준화 왜도 %+.4f (그룹 %d · n %d)", skew1(zon$z), zon$ng, zon$n)
  say("   OFF 표준화 왜도 %+.4f (그룹 %d · n %d)", skew1(zoff$z), zoff$ng, zoff$n)
  say("   ★표준화 diff %+.4f (기준 %+.4f, 잔존 %.0f%%)",
      skew1(zon$z)-skew1(zoff$z), base, 100*(skew1(zon$z)-skew1(zoff$z))/base)

  ## ---- D) 시점-절단 안정성 ---------------------------------------------------
  say(" --- D) 시점-절단 (그 시점에 측정했다면) ---")
  cuts <- as.Date(c("1999-12-31","2003-12-31","2007-12-31","2011-12-31","2015-12-31",
                    "2019-12-31","2023-12-31","2025-12-31","2026-08-07"))
  Drows <- rbindlist(lapply(cuts, function(cu){
    Dc <- D[Date <= cu]; oc <- Dc$dd252 <= thr
    if (sum(oc) < 100 || sum(!oc) < 100) return(data.table(cut=as.character(cu), n_on=sum(oc),
      skew_on=NA_real_, skew_off=NA_real_, diff=NA_real_))
    data.table(cut=as.character(cu), n_on=sum(oc), skew_on=skew1(Dc$fwd1[oc]),
               skew_off=skew1(Dc$fwd1[!oc]), diff=skew1(Dc$fwd1[oc])-skew1(Dc$fwd1[!oc]))}))
  print(Drows[, .(cut, n_on, skew_on=round(skew_on,4), skew_off=round(skew_off,4), diff=round(diff,4))])
  ## 전후반 분할
  mid <- D$Date[floor(nrow(D)/2)]
  for (half in 1:2) {
    Dh <- if (half==1) D[Date <= mid] else D[Date > mid]
    oh <- Dh$dd252 <= thr
    say("   전/후반%d (%s~%s) ON %d: diff %s", half, as.character(min(Dh$Date)), as.character(max(Dh$Date)),
        sum(oh), if (sum(oh)>=50 && sum(!oh)>=50) sprintf("%+.4f", skew1(Dh$fwd1[oh])-skew1(Dh$fwd1[!oh])) else "n부족")
  }

  ## ---- E) 단일-일 delete-1 최대 영향력 ---------------------------------------
  ion <- which(on)
  d1 <- vapply(ion, function(i){ k<-rep(TRUE,nrow(D)); k[i]<-FALSE
                                 skew1(x[on&k]) - skew1(x[!on]) }, numeric(1))
  ord <- order(d1)[1:3]
  say(" --- E) 단일-일 delete-1 (최대 하방 영향 3일) ---")
  for (k in ord) say("   %s fwd1 %+.4f -> diff %+.4f (Δ %+.4f)",
                     as.character(D$Date[ion[k]]), x[ion[k]], d1[k], d1[k]-base)
  say("   ★1일 제거 최대 효과감소 %.1f%% · 5일(최악) 누적 %s",
      100*(base-min(d1))/base,
      { kk<-order(d1)[1:5]; kp<-rep(TRUE,nrow(D)); kp[ion[kk]]<-FALSE
        sprintf("%+.4f (잔존 %.0f%%)", skew1(x[on&kp])-skew1(x[!on]),
                100*(skew1(x[on&kp])-skew1(x[!on]))/base) })

  res[[length(res)+1L]] <- data.table(
    thr=thr*100, base_moment_diff=base,
    top1_infl_share=infl$infl_share[1], top1_day_share=infl$day_share[1],
    top2_infl_share=sum(infl$infl_share[1:2]),
    diff_excl_live=d_live, diff_bowley=bw, diff_q595=qs, diff_winsor1=wm,
    diff_within_std=skew1(zon$z)-skew1(zoff$z),
    diff_cut2019=Drows[cut=="2019-12-31", diff], diff_cut2007=Drows[cut=="2007-12-31", diff],
    diff_cut2025=Drows[cut=="2025-12-31", diff],
    del1_max_drop_pct=100*(base-min(d1))/base)
}
R <- rbindlist(res)
fwrite(R, file.path(OUT, "adv_episode_jackknife_p2.csv"))
say(""); say("=========== P2 요약 ==========="); print(t(R))
say("=== P2 완료 ===")
