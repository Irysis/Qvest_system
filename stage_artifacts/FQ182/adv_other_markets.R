## FQ-182 적대검증 — 렌즈: other_markets
## 질문: "낙폭 조건부 forward 왜도 부호 뒤집힘"이 KR 벤치 고유인가, 일반 현상인가, 절차 인공물인가.
## 절차는 P1 과 동일하게 고정: 신호 dd252[t] -> 대상 fwd1 = r[t+1]. 동시점 미사용.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv] ", fmt, "\n"), ...)); flush.console() }

## ---------------- 통계량: P1 과 **동일 정의** (population skew/kurt) ----------------
skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/n/s^4-3}
stats_of <- function(v) c(mean = mean(v), sd = sd(v), skew = skew1(v), kurt = kurt1(v),
                          p_dn3 = mean(v <= -0.03), p_up3 = mean(v >= 0.03),
                          tail_asym = mean(v >= 0.03) - mean(v <= -0.03))
STATN <- c("mean","sd","skew","kurt","p_dn3","p_up3","tail_asym")

bb <- function(x, on, B = 500L, blk = 60L) {           ## P1 과 동일한 블록부트
  n <- length(x); nb <- ceiling(n/blk); starts <- seq_len(max(1, n-blk+1))
  o <- matrix(NA_real_, B, 7)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) next
    o[b, ] <- stats_of(xb[ob]) - stats_of(xb[!ob])
  }
  o <- o[complete.cases(o), , drop = FALSE]; colnames(o) <- STATN; o
}

## ---------------- 계열 -> (Date, ret) 표준화 ----------------
mk <- function(dates, lvl, label, kind) {
  ok <- is.finite(lvl) & !is.na(dates)
  d <- dates[ok]; l <- lvl[ok]
  o <- order(d); d <- d[o]; l <- l[o]
  r <- c(NA_real_, l[-1]/l[-length(l)] - 1)
  D <- data.table(Date = d, ret = r)[is.finite(ret)]
  D <- D[abs(ret) < 0.5]                                ## 명백 스케일 파손 방어 (일간 ±50% 초과 제거)
  nav <- cumprod(1 + D$ret)
  D[, dd252 := nav / frollapply(nav, 252, max, fill = NA, align = "right") - 1]
  D[, fwd1 := shift(ret, 1L, type = "lead")]
  D <- D[is.finite(dd252) & is.finite(fwd1)]
  attr(D, "label") <- label; attr(D, "kind") <- kind
  D
}

## 병합 에피소드 수(gap 60일) = 상태 조건부 통계의 **실효 독립 표본 수**
n_epi <- function(on, gap = 60L) { i <- which(on); if (!length(i)) return(0L); sum(diff(i) > gap) + 1L }

## ---------------- 한 계열 측정 ----------------
measure <- function(D, label, kind, thrs = c(-0.10,-0.20,-0.30), B = 500L) {
  say("--- [%s] (%s) n=%d · %s ~ %s · ret sd %.5f · 관측단위 daily",
      label, kind, nrow(D), min(D$Date), max(D$Date), sd(D$ret))
  rows <- list()
  for (thr in thrs) {
    on <- D$dd252 <= thr
    ne <- n_epi(on, 60L)
    if (sum(on) < 100) { say("    dd<=%.0f%%: ON %d일 (에피소드 %d) — 100일 미만, 판정 보류", thr*100, sum(on), ne);
      rows[[length(rows)+1L]] <- data.table(series=label, kind=kind, thr=thr*100, stat="skew",
        n_on=sum(on), n_epi=ne, on=NA_real_, off=NA_real_, diff=NA_real_, se=NA_real_, ratio=NA_real_, verdict="INSUFFICIENT")
      next }
    A <- stats_of(D$fwd1[on]); O <- stats_of(D$fwd1[!on]); obs <- A - O
    BB <- bb(D$fwd1, on, B, 60L); se <- apply(BB, 2, sd, na.rm = TRUE)
    say("    dd<=%.0f%%: ON %d일 · 병합에피소드 %d · OFF %d일 · 부트 %d회",
        thr*100, sum(on), ne, sum(!on), nrow(BB))
    for (k in STATN) {
      rt <- abs(obs[[k]])/(2*se[[k]])
      if (k %in% c("skew","tail_asym","sd"))
        say("      %-10s ON %+8.4f  OFF %+8.4f  차이 %+8.4f  se %7.4f  ratio %6.3f", k, A[[k]], O[[k]], obs[[k]], se[[k]], rt)
      rows[[length(rows)+1L]] <- data.table(series=label, kind=kind, thr=thr*100, stat=k,
        n_on=sum(on), n_epi=ne, on=A[[k]], off=O[[k]], diff=obs[[k]], se=se[[k]], ratio=rt,
        verdict = if (k=="skew") { if (A[["skew"]]>0 && O[["skew"]]<0 && rt>=1) "SIGNFLIP_SIG"
                                   else if (A[["skew"]]>0 && O[["skew"]]<0) "SIGNFLIP_WEAK"
                                   else if (obs[["skew"]]>0 && rt>=1) "POSDIFF_NOFLIP"
                                   else "NO" } else NA_character_)
    }
  }
  rbindlist(rows)
}

set.seed(20260809)

## ================= (A) KR 벤치 기준선 — ★직접 재측정 (인용 금지) =================
say("=== (A) KR 벤치 기준선 재측정 ===")
BD <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/alloc_daily/p0.rds"))$BD)[order(Date)]
say("  원천 stage_artifacts/alloc_daily/p0.rds$BD — 행 %d · 열 %s", nrow(BD), paste(names(BD), collapse=","))
KR <- mk(BD$Date, cumprod(1 + ifelse(is.na(BD$BM_Ret), 0, BD$BM_Ret)), "KR_BM(baseline)", "KR-bench")
res <- list(measure(KR, "KR_BM(baseline)", "KR-bench"))

## ================= (B) 저장소 내 다른 수익 계열 =================
say("=== (B) 저장소 내 타 계열 ===")
IDX <- as.data.table(read_parquet(".cache/indices.parquet"))[order(Date)]
FRW <- as.data.table(read_parquet(".cache/fred_macro_wide.parquet"))[order(Date)]

SER <- list(
  list(dt="IDX", col="kosdaq",       lab="KOSDAQ",        kind="KR-other-exchange"),
  list(dt="IDX", col="kospi",        lab="KOSPI(broad)",  kind="KR-broad"),
  list(dt="IDX", col="kospi_small",  lab="KOSPI_small",   kind="KR-captier"),
  list(dt="IDX", col="kosdaq_small", lab="KOSDAQ_small",  kind="KR-captier"),
  list(dt="IDX", col="kospi200_ew",  lab="KOSPI200_EW",   kind="KR-weighting"),
  list(dt="FRW", col="SP500",        lab="SP500(US)",     kind="US-equity"),
  list(dt="FRW", col="KRW_USD",      lab="KRW_USD(FX)",   kind="FX")
)
for (s in SER) {
  src <- get(s$dt)
  D <- mk(src$Date, src[[s$col]], s$lab, s$kind)
  if (nrow(D) < 400) { say("--- [%s] 유효 %d일 — 400일 미만, 스킵", s$lab, nrow(D)); next }
  res[[length(res)+1L]] <- measure(D, s$lab, s$kind)
}

R <- rbindlist(res, fill = TRUE)
fwrite(R, file.path(OUT, "adv_other_markets.csv"))

## ================= (C) 판정 요약 =================
say("=== (C) skew 재현 요약 (dd<=-20%%) ===")
S20 <- R[stat == "skew" & thr == -20]
print(S20[, .(series, kind, n_on, n_epi, on=round(on,4), off=round(off,4), diff=round(diff,4),
              se=round(se,4), ratio=round(ratio,3), verdict)])
say("=== skew 재현 요약 (dd<=-30%%) ===")
S30 <- R[stat == "skew" & thr == -30]
print(S30[, .(series, kind, n_on, n_epi, on=round(on,4), off=round(off,4), diff=round(diff,4),
              se=round(se,4), ratio=round(ratio,3), verdict)])
say("=== 저장: adv_other_markets.csv (%d행) ===", nrow(R))
