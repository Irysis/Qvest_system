## FQ-182 적대검증 · 렌즈 = mechanical_selection
## STEP 1~7: 재측정 / 표준화 무효성 / 조건부-변동성 표준화 잔차 / 로버스트 왜도 /
##           영향력 분해 / 에피소드 잭나이프 / 경계-심층 분해 / 이탈역학 정량
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "adv_ms_input.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[!is.na(fwd1)]
say("=== 입력 실측 (재확인) === %d행 · %s~%s · 관측단위 daily · fwd1 sd %.5f",
    nrow(D), as.character(min(D$Date)), as.character(max(D$Date)), sd(D$fwd1))

skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
## 로버스트(분위수) 왜도 — 스케일 불변 + 극단치 비민감
bowley <- function(v,p=0.25){q<-quantile(v,c(p,.5,1-p),names=FALSE,na.rm=TRUE);(q[3]+q[1]-2*q[2])/(q[3]-q[1])}

THR <- c(-0.20, -0.30)
res <- list(); add <- function(...) res[[length(res)+1L]] <<- data.table(...)

## ---------- STEP 1. 기준선 재측정 (인용 금지 → 직접 산출) ----------------------
say("")
say("=== STEP 1. 기준선 재측정 (전체 표본) ===")
for (thr in THR) {
  on <- D$dd252 <= thr
  a <- skew1(D$fwd1[on]); b <- skew1(D$fwd1[!on])
  say("  dd252<=%.0f%%: ON n=%d skew %+0.4f | OFF n=%d skew %+0.4f | diff %+0.4f",
      thr*100, sum(on), a, sum(!on), b, a-b)
  add(step="1_baseline", thr=thr*100, variant="raw_full", n_on=sum(on), skew_on=a, skew_off=b, diff=a-b)
}
## 워밍업(1:251, rollmax 참조창이 표본 밖) 제외 — 귀무 시뮬과 정합시키기 위한 창-정합
Dw <- D[252:.N]
say("  [창-정합] 워밍업 251행 제외 후 (n=%d):", nrow(Dw))
for (thr in THR) {
  on <- Dw$dd252 <= thr; a <- skew1(Dw$fwd1[on]); b <- skew1(Dw$fwd1[!on])
  say("    dd252<=%.0f%%: ON n=%d skew %+0.4f | OFF skew %+0.4f | diff %+0.4f", thr*100, sum(on), a, b, a-b)
  add(step="1_baseline", thr=thr*100, variant="raw_warmup_dropped", n_on=sum(on), skew_on=a, skew_off=b, diff=a-b)
}

## ---------- STEP 2. 검사① 자기-sd 표준화 = 수학적 무효(항등) --------------------
say("")
say("=== STEP 2. 검사① '각 부분집합을 자기 sd 로 표준화 후 왜도 재계산' ===")
say("  ★왜도는 위치·척도 불변이므로 이 검사는 **항등변환**이다 — 결론을 바꿀 수 없다. 수치로 실증:")
for (thr in THR) {
  on <- D$dd252 <= thr
  za <- (D$fwd1[on]-mean(D$fwd1[on]))/sd(D$fwd1[on]); zb <- (D$fwd1[!on]-mean(D$fwd1[!on]))/sd(D$fwd1[!on])
  a <- skew1(za); b <- skew1(zb); a0 <- skew1(D$fwd1[on]); b0 <- skew1(D$fwd1[!on])
  say("  dd252<=%.0f%%: |skew(z_on)-skew(raw_on)| = %.3e · diff %+0.4f (원본 %+0.4f)",
      thr*100, abs(a-a0), a-b, a0-b0)
  add(step="2_selfsd", thr=thr*100, variant="self_sd_standardized", n_on=sum(on), skew_on=a, skew_off=b, diff=a-b)
}
say("  ★판정: 검사①은 정보량 0 — '표준화해도 왜도가 살아남았다'는 논증은 **동어반복**이다.")

## ---------- STEP 3. 검사② 조건부-변동성(EWMA/GARCH) 표준화 잔차 -----------------
say("")
say("=== STEP 3. 검사② 시변 변동성으로 표준화한 잔차의 왜도 ===")
say("  ★이것이 실질 검사다: 왜도가 '변동성 국면 혼합'의 산물이면 잔차에서 사라진다.")
r <- D$BM_Ret; n <- length(r); mu <- mean(r)
ewma_sig <- function(x, lam) {  # t 시점 종가까지의 정보만 사용 → sigma_{t+1} 예측
  v <- numeric(length(x)); v[1] <- var(x)
  for (i in 2:length(x)) v[i] <- lam*v[i-1] + (1-lam)*(x[i-1]-mean(x))^2
  sqrt(v)
}
for (lam in c(0.94, 0.97)) {
  sg <- ewma_sig(r, lam)                      # sg[i] = i 일 수익의 조건부 sd (i-1 까지 정보)
  sg_f <- shift(sg, 1L, type = "lead")        # fwd1 = r[t+1] 에 대응하는 조건부 sd
  z <- D$fwd1 / sg_f
  for (thr in THR) {
    on <- D$dd252 <= thr & is.finite(z)
    off<- D$dd252 >  thr & is.finite(z)
    a <- skew1(z[on]); b <- skew1(z[off])
    say("  EWMA(lam=%.2f) dd252<=%.0f%%: 잔차 skew ON %+0.4f | OFF %+0.4f | diff %+0.4f",
        lam, thr*100, a, b, a-b)
    add(step="3_ewma", thr=thr*100, variant=sprintf("ewma_lam%.2f_resid", lam), n_on=sum(on), skew_on=a, skew_off=b, diff=a-b)
  }
}
## GARCH(1,1)-std t (대칭) 조건부 sd
ok_rug <- requireNamespace("rugarch", quietly = TRUE)
if (ok_rug) {
  suppressPackageStartupMessages(library(rugarch))
  spec <- ugarchspec(variance.model = list(model="sGARCH", garchOrder=c(1,1)),
                     mean.model = list(armaOrder=c(0,0), include.mean=TRUE),
                     distribution.model = "std")
  fit <- ugarchfit(spec, r, solver = "hybrid")
  cf <- coef(fit); say("  GARCH(1,1)-t 적합: %s", paste(sprintf("%s=%.6g", names(cf), cf), collapse=" · "))
  sg <- as.numeric(sigma(fit))                 # sigma[i] = i 일 조건부 sd (i-1 까지 정보)
  sg_f <- shift(sg, 1L, type = "lead")
  z <- (D$fwd1 - cf[["mu"]]) / sg_f
  say("  표준화 잔차 z: sd %.4f · skew %+0.4f · 초과첨도 %+0.3f",
      sd(z,na.rm=TRUE), skew1(z), mean((z-mean(z,na.rm=TRUE))^4,na.rm=TRUE)/sd(z,na.rm=TRUE)^4-3)
  for (thr in THR) {
    on <- D$dd252 <= thr & is.finite(z); off <- D$dd252 > thr & is.finite(z)
    a <- skew1(z[on]); b <- skew1(z[off])
    say("  GARCH dd252<=%.0f%%: 잔차 skew ON %+0.4f | OFF %+0.4f | diff %+0.4f", thr*100, a, b, a-b)
    add(step="3_garch", thr=thr*100, variant="garch11_t_resid", n_on=sum(on), skew_on=a, skew_off=b, diff=a-b)
  }
  saveRDS(list(coef=cf, sigma=sg, z=as.numeric((r-cf[["mu"]])/sg)), file.path(OUT,"adv_ms_garchfit.rds"))
} else say("  ★rugarch 없음 — GARCH 표준화 생략")

## ---------- STEP 4. 로버스트(분위수) 왜도 ---------------------------------------
say("")
say("=== STEP 4. 극단치-비민감 왜도 (Bowley, 스케일 불변) ===")
say("  ★모멘트 왜도는 세제곱이라 소수 관측이 지배할 수 있다. 로버스트 판본이 같은 부호 반전을 보이는가?")
for (thr in THR) for (p in c(0.25, 0.10, 0.05)) {
  on <- D$dd252 <= thr
  a <- bowley(D$fwd1[on], p); b <- bowley(D$fwd1[!on], p)
  say("  dd252<=%.0f%% Bowley(p=%.2f): ON %+0.4f | OFF %+0.4f | diff %+0.4f", thr*100, p, a, b, a-b)
  add(step="4_robust", thr=thr*100, variant=sprintf("bowley_p%.2f",p), n_on=sum(on), skew_on=a, skew_off=b, diff=a-b)
}

## ---------- STEP 5. 영향력 분해 -------------------------------------------------
say("")
say("=== STEP 5. 3차모멘트 영향력 분해 (몇 개 관측이 왜도를 만드는가) ===")
for (thr in THR) {
  on <- D$dd252 <= thr; v <- D$fwd1[on]; m <- mean(v); s <- sd(v); nn <- length(v)
  contrib <- (v-m)^3 / (nn*s^3); o <- order(contrib, decreasing = TRUE)
  say("  dd252<=%.0f%% (n=%d, skew %+0.4f)", thr*100, nn, skew1(v))
  say("    상위5 양(+)기여 = %s (합 %+0.4f = 왜도의 %.0f%%)",
      paste(sprintf("%+0.4f", contrib[o[1:5]]), collapse=" "), sum(contrib[o[1:5]]),
      100*sum(contrib[o[1:5]])/skew1(v))
  say("    해당일 수익 = %s / 날짜 = %s",
      paste(sprintf("%+0.3f", v[o[1:5]]), collapse=" "),
      paste(as.character(D$Date[on][o[1:5]]), collapse=" "))
  for (k in c(1,3,5,10)) {
    vv <- v[-o[1:k]]; a <- skew1(vv); b <- skew1(D$fwd1[!on])
    say("    상위 %2d개 양기여 제거 후: ON skew %+0.4f · diff %+0.4f %s",
        k, a, a-b, if (sign(a-b) != sign(skew1(v)-b)) "★부호반전" else "")
    add(step="5_influence", thr=thr*100, variant=sprintf("drop_top%d_pos",k), n_on=length(vv), skew_on=a, skew_off=b, diff=a-b)
  }
  ## 양·음 대칭 절사 (꼬리 정보를 대칭으로 깎음 — 왜도를 인위로 죽이지 않는 통제)
  for (q in c(0.005, 0.01)) {
    lo <- quantile(v, q, names=FALSE); hi <- quantile(v, 1-q, names=FALSE)
    vv <- v[v>lo & v<hi]
    vo <- D$fwd1[!on]; lo2 <- quantile(vo,q,names=FALSE); hi2 <- quantile(vo,1-q,names=FALSE)
    vvo<- vo[vo>lo2 & vo<hi2]
    a <- skew1(vv); b <- skew1(vvo)
    say("    양측 %.1f%% 대칭절사: ON %+0.4f | OFF %+0.4f | diff %+0.4f", q*100, a, b, a-b)
    add(step="5_influence", thr=thr*100, variant=sprintf("sym_trim_%.3f",q), n_on=length(vv), skew_on=a, skew_off=b, diff=a-b)
  }
}

## ---------- STEP 6. 에피소드 잭나이프 -------------------------------------------
say("")
say("=== STEP 6. 낙폭 에피소드 잭나이프 (ON 은 소수 에피소드의 반복 표본) ===")
for (thr in THR) {
  on <- D$dd252 <= thr
  rl <- rle(on); ends <- cumsum(rl$lengths); starts <- ends - rl$lengths + 1
  ep <- which(rl$values); base <- skew1(D$fwd1[on]) - skew1(D$fwd1[!on])
  say("  dd252<=%.0f%%: ON 에피소드 %d개 · 총 %d일 · 최장 %d일 · 전체 diff %+0.4f",
      thr*100, length(ep), sum(on), max(rl$lengths[ep]), base)
  jk <- numeric(0)
  for (e in ep) {
    keep <- rep(TRUE, nrow(D)); keep[starts[e]:ends[e]] <- FALSE
    on2 <- on & keep
    if (sum(on2) < 100) next
    d2 <- skew1(D$fwd1[on2]) - skew1(D$fwd1[!on & keep])
    jk <- c(jk, d2)
    if (rl$lengths[e] >= 60)
      say("    에피소드 %s~%s (%d일) 제거 → diff %+0.4f %s",
          as.character(D$Date[starts[e]]), as.character(D$Date[ends[e]]), rl$lengths[e], d2,
          if (sign(d2)!=sign(base)) "★부호반전" else "")
  }
  say("    잭나이프 diff 범위 [%+0.4f, %+0.4f] · 부호반전 %d/%d",
      min(jk), max(jk), sum(sign(jk)!=sign(base)), length(jk))
  add(step="6_jackknife", thr=thr*100, variant="episode_jk_min", n_on=sum(on), skew_on=NA, skew_off=NA, diff=min(jk))
  add(step="6_jackknife", thr=thr*100, variant="episode_jk_max", n_on=sum(on), skew_on=NA, skew_off=NA, diff=max(jk))
}

## ---------- STEP 7. 혐의(a) 이탈역학: ON 이탈에 큰 양수가 구조적으로 필요한가 -----
say("")
say("=== STEP 7. 혐의(a) 정량: '이탈하려면 큰 양수 수익이 필요' 가 사실인가 ===")
for (thr in THR) {
  on <- D$dd252 <= thr; dd <- D$dd252[on]
  need <- (1+thr)/(1+dd) - 1     # 1일 만에 ON 이탈에 필요한 수익률
  say("  dd252<=%.0f%%: 1일 이탈 필요수익 median %+0.3f · 90분위 %+0.3f · 표본 최대 일수익 %+0.3f",
      thr*100, median(need), quantile(need,.9,names=FALSE), max(D$BM_Ret))
  say("    1일 내 이탈이 물리적으로 가능한 ON일 비중 = %.1f%% (필요수익 <= 관측 최대일수익)",
      100*mean(need <= max(D$BM_Ret)))
  ## 경계 vs 심층 분해
  bnd <- on & D$dd252 >  thr - 0.10
  dpp <- on & D$dd252 <= thr - 0.10
  a1 <- skew1(D$fwd1[bnd]); a2 <- if (sum(dpp)>50) skew1(D$fwd1[dpp]) else NA_real_
  b <- skew1(D$fwd1[!on])
  say("    경계층(%.0f%%<dd<=%.0f%%) n=%d skew %+0.4f | 심층(dd<=%.0f%%) n=%d skew %+0.4f | OFF %+0.4f",
      (thr-0.10)*100, thr*100, sum(bnd), a1, (thr-0.10)*100, sum(dpp), a2, b)
  add(step="7_exit", thr=thr*100, variant="boundary_layer", n_on=sum(bnd), skew_on=a1, skew_off=b, diff=a1-b)
  add(step="7_exit", thr=thr*100, variant="deep_layer",     n_on=sum(dpp), skew_on=a2, skew_off=b, diff=a2-b)
}

R <- rbindlist(res, fill = TRUE)
fwrite(R, file.path(OUT, "adv_mechanical_selection_diag.csv"))
say("")
say("=== STEP 1~7 완료 → adv_mechanical_selection_diag.csv (%d행) ===", nrow(R))
