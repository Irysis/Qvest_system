## A11 — 자기 적대검증: primary falsification 의 대안 설명 통제
## 제기: β_s 부호 패턴(유틸·통신·건강관리 음 / 철강·화학 양)은 인플레 채널이 아니라
##       **섹터 시장베타의 재진술**일 수 있다. infl 이 경기와 동행하면 저베타 방어섹터는
##       자동으로 β_s<0 이 된다 — 그러면 '채널 확인'은 동어반복이다.
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table) })
say <- function(fmt, ...) cat(sprintf(paste0("[A11] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT,"panels.rds")); L <- readRDS(file.path(OUT,"layers.rds"))
sec <- L$sec; BETA <- L$BETA; INF <- L$INF; PRED <- L$PRED
BEN <- P$fwd$bench_dt[, .(sig_date = Date, bm = BM_Ret)]

## (1) 섹터 시장베타 β^mkt_s,t — 동일 창(60m/최소36m, 실현월만)
M <- merge(sec[, .(sig_date, Sector, r_s)], BEN, by = "sig_date")[order(Sector, sig_date)]
sds <- sort(unique(BETA$sig_date))
rows <- list()
for (s in unique(M$Sector)) {
  ms <- M[Sector == s][order(sig_date)]
  for (t_d in sds) {
    h <- ms[sig_date < t_d]; if (nrow(h) < 36L) next
    hh <- utils::tail(h, 60L); vv <- stats::var(hh$bm)
    if (!is.finite(vv) || vv <= 0) next
    rows[[length(rows)+1L]] <- data.table(sig_date=t_d, Sector=s, bmkt=stats::cov(hh$r_s, hh$bm)/vv)
  }
}
BM <- rbindlist(rows)
X <- merge(BETA[, .(sig_date, Sector, beta)], BM, by = c("sig_date","Sector"))
say("β_s(인플레) vs β^mkt_s(초과수익의 시장베타) 상관: Pearson %+.3f · Spearman %+.3f (n=%d 섹터-월)",
    cor(X$beta, X$bmkt), cor(X$beta, X$bmkt, method="spearman"), nrow(X))
say("  섹터 평균끼리: Pearson %+.3f (n=%d 섹터)",
    { a <- X[, .(b=mean(beta), m=mean(bmkt)), by=Sector]; cor(a$b, a$m) }, uniqueN(X$Sector))

## (2) 대안 예측: 시장베타 부호로 같은 검정을 하면 몇 % 맞추나 (대조군)
XP <- merge(X, PRED, by = "Sector")
XP[, hit_infl := as.integer(sign(beta) == pred)]
XP[, hit_mkt  := as.integer(sign(bmkt) == pred)]
say("")
say("예측 부여 10섹터 일치율 — 인플레 β %.3f vs **시장베타 β^mkt %.3f** (같은 예측표, n=%d)",
    mean(XP$hit_infl), mean(XP$hit_mkt), nrow(XP))
say("  두 검정이 같은 답을 내는 비율(부호 일치) %.3f", mean(sign(XP$beta) == sign(XP$bmkt)))

## (3) 결정적 통제 — 시장베타를 제거한 β_s 로 같은 검정
##     r_s 를 벤치에 회귀해 잔차만 남기고 그 위에서 Δinfl 민감도를 다시 추정
rows2 <- list()
for (s in unique(M$Sector)) {
  ms <- merge(M[Sector == s], INF[, .(sig_date, d_infl)], by="sig_date")[!is.na(d_infl)][order(sig_date)]
  for (t_d in sds) {
    h <- ms[sig_date < t_d]; if (nrow(h) < 36L) next
    hh <- utils::tail(h, 60L)
    fit <- stats::lm(r_s ~ bm, data = hh)          # 시장성분 제거
    resid <- stats::residuals(fit)
    vv <- stats::var(hh$d_infl); if (!is.finite(vv) || vv <= 0) next
    rows2[[length(rows2)+1L]] <- data.table(sig_date=t_d, Sector=s,
                                            beta_orth=stats::cov(resid, hh$d_infl)/vv)
  }
}
BO <- rbindlist(rows2)
XO <- merge(BO, PRED, by = "Sector")
XO[, hit := as.integer(sign(beta_orth) == pred)]
say("")
say("★시장중립화 후 β_s^⊥ 로 재검정: 일치율 %.3f (원판 0.649) · n=%d", mean(XO$hit), nrow(XO))
sd_beta <- sort(unique(BO$sig_date)); stride <- sd_beta[seq(1, length(sd_beta), by=12)]
xs <- XO[sig_date %in% stride]
bt <- stats::binom.test(sum(xs$hit), nrow(xs), p=0.5)
say("  stride-12 일치율 %.3f · 이항 p %.4f (95%%CI %.3f~%.3f)",
    mean(xs$hit), bt$p.value, bt$conf.int[1], bt$conf.int[2])
ps <- XO[, .(hit=mean(hit), n=.N, mb=mean(beta_orth), pred=pred[1]), by=Sector][order(-hit)]
print(ps)
saveRDS(list(cor_beta_bmkt=cor(X$beta,X$bmkt), hit_infl=mean(XP$hit_infl), hit_mkt=mean(XP$hit_mkt),
             hit_orth=mean(XO$hit), hit_orth_stride=mean(xs$hit), binom_p_orth=bt$p.value,
             per_sector_orth=ps), file.path(OUT,"adversarial.rds"))
