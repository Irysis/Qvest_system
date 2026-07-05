## _r2_adversarial_check.R — R2 Self-Adversarial Challenge (v8.2, AX-008 Forge source)
## 두 "PASS"(N=15 Consensus 3.18, N=20 stack topNsel 3.54)의 진위 적대검증:
##  A) topNsel 스택 = 선택 연산자(top-4 by same cap-w PORT_t) → in-sample selection bias?
##     → 고정-구성 스택(R1fixed)과 대조 + N-재선정이 N마다 구성 바뀌는지.
##  B) N=15 Consensus 강건성: DSR(sweep n_trials=3×N), oos_retention HARD(>=0.7), calmar HARD(>=0.64) 게이트.
##  C) Consensus sleeve의 N-단조성 (N 작을수록 pt↑ = 소수 고신뢰 종목 집중 효과인가 vs 노이즈).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "outputs/ramp"
SL <- as.data.table(read_parquet(file.path(OUT,"r2_topn_sleeve_gates.parquet")))
ST <- as.data.table(read_parquet(file.path(OUT,"r2_topn_gates.parquet")))

cat("=== A) topNsel 스택 = 선택 연산자 검증 ===\n")
st20 <- ST[top_n==20]
cat(sprintf("  N=20 topNsel  pt=%.2f fams=[%s]\n", st20[model=="stack_EW_topNsel",port_t_capwt], st20[model=="stack_EW_topNsel",stack_fams]))
cat(sprintf("  N=20 R1fixed  pt=%.2f fams=[%s]\n", st20[model=="stack_EW_R1fixed",port_t_capwt], st20[model=="stack_EW_R1fixed",stack_fams]))
cat("  구성 fams가 N마다 바뀌는지(=선택 연산자 증거):\n")
for(N in c(15,20,25)) cat(sprintf("    N=%d topNsel fams=[%s]\n", N, ST[top_n==N & model=="stack_EW_topNsel",stack_fams]))

cat("\n=== B) 두 PASS의 graduation HARD 3종 ===\n")
cons15 <- SL[top_n==15 & model=="sleeve_Consensus"]
st20sel <- ST[top_n==20 & model=="stack_EW_topNsel"]
chk <- function(nm, pt, oos, cal){
  cat(sprintf("  %-22s pt_capwt=%+.2f(%s2.95) | oos_ret=%+.2f(%s0.7) | calmar=%+.2f(%s0.64) => %s\n",
    nm, pt, if(pt>=2.95)">=" else "<", oos, if(oos>=0.7)">=" else "<", cal, if(cal>=0.64)">=" else "<",
    if(pt>=2.95 && oos>=0.7 && cal>=0.64) "GRAD PASS" else "GRAD FAIL"))
}
chk("N15 Consensus sleeve", cons15$port_t_capwt, cons15$oos_retention, cons15$calmar)
chk("N20 stack topNsel",     st20sel$port_t_capwt, st20sel$oos_retention, st20sel$calmar)

cat("\n=== C) Consensus sleeve N-단조성 (pt_capwt) ===\n")
for(N in c(15,20,25)){
  r <- SL[top_n==N & model=="sleeve_Consensus"]
  cat(sprintf("    N=%d pt=%+.2f oos=%+.2f cal=%+.2f post17=%+.2f\n", N, r$port_t_capwt, r$oos_retention, r$calmar, r$post2017_bm_sr))
}

cat("\n=== D) N×구성 스캔 = sweep(선택). DSR 적용경계 판정 ===\n")
cat("  N∈{15,20,25} × {11 sleeve + 2 stack} = 39 trial의 argmax pick = sweep(열거집합 선택).\n")
cat("  measurement-graduation §3: sweep형 selection → DSR>=0.5 HARD + PORT_t 2.95는 문헌-레벨 다중검정.\n")
cat("  best 2건이 39-trial 중 max인지 확인:\n")
allpt <- rbind(SL[,.(model,top_n,port_t_capwt)], ST[,.(model,top_n,port_t_capwt)], fill=TRUE)
setorder(allpt, -port_t_capwt)
print(head(allpt, 6))
cat(sprintf("\n  전체 trial 수 = %d (sleeve %d + stack %d)\n", nrow(allpt), nrow(SL), nrow(ST)))
