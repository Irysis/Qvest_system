## PIT 게이트 정밀화: 의사결정 경로(비중 산출)와 사후 평가기(성과 통계)를 분리 스캔.
## 발췌는 손으로 다시 쓰지 않고 o7_methods.R 원문에서 **행 범위로 잘라낸다**(동일 텍스트 보장).
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
src <- readLines("stage_artifacts/WT_R20260829_005/o7_methods.R")
i0 <- grep("^## ---------- 방법론 ----------", src)
i1 <- grep("^## ---------- 평가", src)
stopifnot(length(i0)==1, length(i1)==1, i0 < i1)
dec <- src[i0:(i1-1)]                       # 의사결정 경로: w_* 5종 + build()
evl <- src[i1:length(src)]                  # 사후 평가기: eval_sched + stats_of
writeLines(c("## DECISION PATH ONLY — o7_methods.R 행 ", paste0("## ", i0, "-", i1-1), dec),
           "stage_artifacts/WT_R20260829_005/o14_decision_path.R")
writeLines(c("## EX-POST EVALUATOR ONLY — o7_methods.R 행 ", paste0("## ", i1, "-", length(src)), evl),
           "stage_artifacts/WT_R20260829_005/o14_expost_evaluator.R")

source("02_Infrastructure/validation/lookahead_detector.R")
for (f in c("stage_artifacts/WT_R20260829_005/o14_decision_path.R",
            "stage_artifacts/WT_R20260829_005/o14_expost_evaluator.R")) {
  cat("\n####", f, "\n"); r <- detect_lookahead(f, verbose = TRUE)
  cat("clean =", r$clean, " n_violations =", r$n_violations, "\n")
}
## 구조적 증명: 평가기가 만든 어떤 객체도 build() 에 들어가지 않는다.
cat("\n=== 구조 증명 ===\n")
cat("build() 본문이 eval_sched/stats_of 를 참조하는가:",
    any(grepl("eval_sched|stats_of", dec)), "\n")
cat("의사결정 경로가 sd(.)*sqrt( 패턴을 쓰는가:", any(grepl("sd\\(.*\\)\\s*\\*\\s*sqrt\\(", dec)), "\n")
cat("의사결정 경로가 미래 수익(RET/Ret_1m@Date>=d)을 참조하는가:",
    any(grepl("rw_dates\\s*>=|rw_dates\\s*>", dec)), " (기지집합은 rw_dates < d 만)\n")
cat(grep("rw_dates", dec, value=TRUE), sep="\n")
