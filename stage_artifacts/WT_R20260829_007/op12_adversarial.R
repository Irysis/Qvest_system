suppressWarnings(suppressMessages({library(data.table)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o6<-readRDS(file.path(OUT,"op6_objects.rds")); SELP<-o6$SELP; m1<-o6$m1; o5<-readRDS(file.path(OUT,"op5_objects.rds"))
sub <- function(p,lab){ p<-copy(p); p[, per := fifelse(signal_date<as.Date("2015-01-01"),"2005-14",
        fifelse(signal_date<as.Date("2020-01-01"),"2015-19","2020-26"))]
  p[, .(months=.N, act_ann=mean(ret_net-bm)*12, net_ir=mean(ret_net-bm)*12/(sd(ret_net-bm)*sqrt(12)),
        to=mean(traded)*12, cost=mean(cost)*12), by=per][, method:=lab][] }
cat("=== 부기간 (SA-5: 회전 제어가 후반부 붕괴를 건드리는가) ===\n")
print(rbind(sub(m1,"M1_EW25_base"), sub(SELP,"M2_EW25_buffer50"))[order(per,method)])
cat("\n=== OOS retention proxy (활성 SR, anchored 55/65/75%) ===\n")
oosr <- function(p){ n<-nrow(p); a<-p$ret_net-p$bm
  sapply(c(.55,.65,.75), function(f){ k<-floor(n*f)
    is<-mean(a[1:k])/sd(a[1:k]); oos<-mean(a[(k+1):n])/sd(a[(k+1):n]); oos/is }) }
cat("M1:",round(oosr(m1),4)," median",round(median(oosr(m1)),4),"\n")
cat("SEL:",round(oosr(SELP),4)," median",round(median(oosr(SELP)),4),"\n")
cat("\n=== RF-O2 점검 (expected_active_return vs 2x cost) ===\n")
cat("실현 순활성", round(mean(SELP$ret_net-SELP$bm)*12,4), " vs 2x비용", round(2*mean(SELP$cost)*12,4),
    " -> ", ifelse(mean(SELP$ret_net-SELP$bm)*12 < 2*mean(SELP$cost)*12,"RF-O2 발화","통과"),"\n")
cat("\n=== 시행수 (DSR 하류 인계용) ===\n")
cat("실제 평가한 구성 수 n_trials_optimizer =", nrow(o5$S), " (M1 · M2×4 · M3 · M4 · M5×4)\n")
cat("사전선언 방법론 계열 수 = 5\n")
cat("\n=== SA-2 두 해석의 결과 병기 ===\n")
print(o5$S[method %in% c("M2_EW25_buffer50","M5_BUF40_MVO_TO","M2_EW25_buffer60"),
           .(method, to_2way=round(to_2way,3), net_ir=round(net_ir,4), active_ann=round(active_ann,4),
             cap_med=round(cap_med/1e8,1), hhi=round(hhi,4))])
