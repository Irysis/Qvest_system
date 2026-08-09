ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/contracts/required_effect_size.R")
say <- function(fmt,...) cat(sprintf(paste0("[C] ",fmt,"\n"),...))
# 1) 필요효과 재계산
for (nm in list(c("D03",0.02560,9.56), c("Q01",0.01727,3.89))) {
  r <- required_effect(n=295, t_threshold=2.0, sd_monthly=as.numeric(nm[2]), design="full")
  say("%s: sd=%.5f n=295 → 필요 월 %.5f / 연 %.2f%%  (보고치 대조)", nm[1], as.numeric(nm[2]),
      r$required_monthly, 100*r$required_annual)
  r270 <- required_effect(n=270, t_threshold=2.0, sd_monthly=as.numeric(nm[2]), design="full")
  say("   n=270(production arm) → 연 %.2f%%", 100*r270$required_annual)
}
# 2) prior 공식 재현
say("prior D03 = (9.56/25)*2.07 = %.3f%% ; Q01 = (3.89/25)*5.21 = %.3f%%", (9.56/25)*2.07, (3.89/25)*5.21)
# 3) 8셀 실측 효과 대비 판정
cells <- data.frame(
  cell=c("W1_D03","W2_D03","W3_D03","W4_D03","W1_Q01","W2_Q01","W3_Q01","W4_Q01"),
  d=c(-3.138,-3.046,-3.698,-3.288, 1.356,1.369,2.102,-1.536),
  t=c(-1.417,-1.164,-1.512,-1.434, 0.915,0.972,1.315,-1.107),
  req=c(4.47,4.47,4.47,4.47, 3.02,3.02,3.02,3.02))
cells$ratio <- abs(cells$d)/cells$req
cells$verdict <- ifelse(abs(cells$d)<cells$req, "INCONCLUSIVE_UNDERPOWERED","NEGATIVE_POWERED")
print(cells)
# 4) 민감도 셀 q=0.30 D03
say("민감도 D03 q0.30: |d|=4.719 vs req 4.47 → %s (t=-1.89)",
    ifelse(4.719<4.47,"INCONCLUSIVE","NEGATIVE_POWERED(문턱 초과)"))
# 5) P1 주판정 셀은 다른 sd — CI 로 역산
p1 <- data.frame(nm=c("P1_D03_25","P1_Q01_25","P1_D03_50","P1_Q01_50"),
                 d=c(-3.443,3.771,-2.276,0.835), lo=c(-9.62,-0.83,-6.99,-2.52), hi=c(2.73,8.37,2.44,4.19))
p1$se <- (p1$hi-p1$lo)/2/qt(0.975, 294)
p1$req_t2 <- 2*p1$se
p1$ratio <- abs(p1$d)/p1$req_t2
print(p1)
