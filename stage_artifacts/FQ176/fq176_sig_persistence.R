## 신호 지속성 — 시차 스캔이 평평한 이유 정량화
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
SIG <- fread("stage_artifacts/FQ176/signals.csv"); SIG[, Date := as.Date(Date)]
for (s in c("S1","S2","S3")) set(SIG, j=s, value=as.logical(SIG[[s]]))
say <- function(fmt,...) cat(sprintf(paste0("[persist] ",fmt,"\n"),...))
mo <- SIG$Date
for (s in c("S1","S2","S3")) {
  v <- SIG[[s]]; r <- rle(v); on_runs <- r$lengths[r$values]
  i_on <- which(v)
  # h=+1 타겟집합 vs h=-1 타겟집합 겹침 (인덱스 기준)
  t_p1 <- i_on+1; t_m1 <- i_on-1
  t_p1 <- t_p1[t_p1<=length(mo)]; t_m1 <- t_m1[t_m1>=1]
  ov <- length(intersect(t_p1,t_m1))
  say("%s: ON %d개월 · 연속구간 %d개 (길이 median %.0f, max %d) · h+1/h-1 타겟월 겹침 %d/%d (%.0f%%)",
      s, sum(v), length(on_runs), median(on_runs), max(on_runs), ov, length(t_p1),
      100*ov/length(t_p1))
  say("   ON 연도 분포: %s", paste(sprintf("%s:%d", names(table(format(mo[v],"%Y"))),
      as.integer(table(format(mo[v],"%Y")))), collapse=" "))
}
