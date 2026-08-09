## FQ-182 적대검증 STEP 2 — h=1 왜도 반전이 무엇으로 만들어지는가
## adv_01 결과: 문턱(-5~-40%) 에는 강건 / h=5,20,60 에서 소멸·역전 / Bowley(분위수) 왜도는 ~0
## ⇒ 혐의 = 3차 모멘트가 **소수 극단 관측**에 지배됨 + 시대(가격제한폭 체제) 교락 + OFF 군의 기계적 음왜도
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv2] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)][, .(Date, BM_Ret, dd252)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[is.finite(fwd1)]
D[, yr := year(Date)]
say("=== 입력 실측 === %d일 · %s ~ %s · fwd1 sd %.6f",
    nrow(D), as.character(min(D$Date)), as.character(max(D$Date)), sd(D$fwd1))

skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
sdiff <- function(x, on) skew1(x[on]) - skew1(x[!on])
THRS  <- c(-0.10, -0.20, -0.30)
rows  <- list()
add   <- function(...) rows[[length(rows)+1L]] <<- data.table(...)

## ---- (a) 극단 관측 레버리지: ON 군 상위 k개 양수 제거 / 공통분위 winsorize --------
say("")
say("=== (a) 레버리지 — 3차 모멘트는 소수 관측에 지배되는가 ===")
say("  ★scale 불변(왜도)은 '변동성 확대' 반론만 막는다. 남은 반론 = **소수 관측 레버리지**.")
say("  문턱  기저diff  ON최대1개제거  상위3제거  상위5제거  |  win0.5%%  win1%%  win2.5%%")
for (thr in THRS) {
  on <- D$dd252 <= thr; x <- D$fwd1
  base <- sdiff(x, on)
  dropk <- function(k) { xo <- x[on]; keep <- rank(-xo, ties.method = "first") > k
    skew1(xo[keep]) - skew1(x[!on]) }
  winz <- function(p) { q <- quantile(x, c(p, 1-p), names = FALSE); xw <- pmin(pmax(x, q[1]), q[2]); sdiff(xw, on) }
  v <- c(base, dropk(1), dropk(3), dropk(5), winz(0.005), winz(0.01), winz(0.025))
  say("  %4.0f%% %+8.4f %+13.4f %+10.4f %+10.4f | %+8.4f %+7.4f %+8.4f",
      thr*100, v[1], v[2], v[3], v[4], v[5], v[6], v[7])
  nm <- c("base","drop_top1","drop_top3","drop_top5","winsor_0.5pct","winsor_1pct","winsor_2.5pct")
  for (i in seq_along(v)) add(test = "leverage", thr = thr*100, variant = nm[i], value = v[i],
                              n_on = sum(on), n_off = sum(!on))
}
say("  ★해석: ON 상위 몇 개 제거만으로 부호/크기가 무너지면 '분포 형태 변화' 가 아니라 '몇 개 사건'.")

## ---- (b) 시대 교락: 가격제한폭 체제 + 위기 에피소드 -------------------------------
say("")
say("=== (b) 시대 분할 — KR 가격제한폭 체제 변경(1998·2015)·위기 편중 교락 ===")
ERAS <- list(c(1991, 1999), c(2000, 2007), c(2008, 2014), c(2015, 2026))
say("  문턱   시대        ON일수 OFF일수  skewON   skewOFF   diff")
for (thr in THRS) for (e in ERAS) {
  S <- D[yr >= e[1] & yr <= e[2]]; on <- S$dd252 <= thr
  if (sum(on) < 50 || sum(!on) < 50) { say("  %4.0f%%  %4d-%4d      %5d %7d   (표본부족)", thr*100, e[1], e[2], sum(on), sum(!on))
    add(test="era", thr=thr*100, variant=sprintf("%d-%d",e[1],e[2]), value=NA_real_, n_on=sum(on), n_off=sum(!on)); next }
  a <- skew1(S$fwd1[on]); o <- skew1(S$fwd1[!on])
  say("  %4.0f%%  %4d-%4d      %5d %7d  %+7.4f %+8.4f %+8.4f", thr*100, e[1], e[2], sum(on), sum(!on), a, o, a-o)
  add(test="era", thr=thr*100, variant=sprintf("%d-%d",e[1],e[2]), value=a-o, n_on=sum(on), n_off=sum(!on))
}
say("  ★부호 반전(ON>0 ∧ OFF<0)이 성립하는 시대 = 몇 개인가가 판정 핵심")

## ---- (c) 위기 에피소드 leave-one-out --------------------------------------------
say("")
say("=== (c) 위기 에피소드 leave-one-out (독립 표본단위 = 에피소드) ===")
for (thr in THRS) {
  on0 <- D$dd252 <= thr
  ## 에피소드 = ON 연속구간(간격 60거래일 이하면 병합)
  idx <- which(on0); grp <- cumsum(c(1, diff(idx) > 60))
  neps <- max(grp)
  base <- sdiff(D$fwd1, on0)
  lo <- vapply(seq_len(neps), function(g) {
    drop_rows <- idx[grp == g]
    S <- D[-drop_rows]; sdiff(S$fwd1, S$dd252 <= thr) }, 0)
  epy <- vapply(seq_len(neps), function(g) paste0(range(D$yr[idx[grp==g]]), collapse="-"), "")
  ord <- order(lo)
  say("  %4.0f%%: 에피소드 %d개 · 기저 diff %+.4f · LOO 범위 [%+.4f, %+.4f] · 부호유지 %d/%d",
      thr*100, neps, base, min(lo), max(lo), sum(lo > 0), neps)
  say("        최대 영향 3개: %s", paste(sprintf("%s(%+.4f)", epy[ord][1:min(3,neps)], lo[ord][1:min(3,neps)]), collapse=" · "))
  for (g in seq_len(neps)) add(test="episode_loo", thr=thr*100, variant=epy[g], value=lo[g], n_on=sum(grp==g), n_off=NA_integer_)
}

## ---- (d) 기전 진단: OFF 군 음왜도는 '낙폭 진입일' 때문인가 -------------------------
say("")
say("=== (d) 기전 진단 — OFF 군 음왜도의 출처 (★미래 상태 사용, 매매용 아님·진단 전용) ===")
say("  논리: 낙폭은 반드시 **비-낙폭 상태에서 시작**한다 ⇒ 폭락 시작일은 정의상 OFF 에 속한다.")
say("        따라서 OFF 의 음왜도는 상태 라벨의 기계적 부산물일 수 있다.")
say("  문턱   OFF전체skew  OFF중 20일내 낙폭진입 제외 후 skew   제외일수   ONskew")
for (thr in THRS) {
  on <- D$dd252 <= thr
  ## 향후 20거래일 내에 ON 으로 전이하는 OFF 일 = '낙폭 진입 경로'
  fut_on <- frollapply(as.numeric(on), 20, max, align = "left")
  enter <- (!on) & is.finite(fut_on) & fut_on == 1
  offs  <- (!on) & !enter
  say("  %4.0f%%  %+10.4f  %+28.4f  %9d %+9.4f",
      thr*100, skew1(D$fwd1[!on]), skew1(D$fwd1[offs]), sum(enter), skew1(D$fwd1[on]))
  add(test="off_decomp", thr=thr*100, variant="off_all", value=skew1(D$fwd1[!on]), n_on=sum(on), n_off=sum(!on))
  add(test="off_decomp", thr=thr*100, variant="off_excl_entry", value=skew1(D$fwd1[offs]), n_on=sum(on), n_off=sum(offs))
  add(test="off_decomp", thr=thr*100, variant="off_entry_only", value=skew1(D$fwd1[enter]), n_on=sum(on), n_off=sum(enter))
}

R2 <- rbindlist(rows)
fwrite(R2, file.path(OUT, "adv_leverage_era_mechanism.csv"))
say("=== adv_02 완료 → adv_leverage_era_mechanism.csv ===")
