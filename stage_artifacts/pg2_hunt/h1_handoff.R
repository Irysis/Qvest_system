## h1 — 병렬 세션(alpha-hypothesis, WT-D20260809_005/FQ-198) Q-Lead 이관 2건 처리
##  ① FQ-163 verdict 'C15 300개월 실림' 진술 정정
##  ② compute_consensus.R 이 C01/C04 완전 중복(C10/C13)을 factor_db 에 배출 중 — 처분 검토
## ★그들 진술을 그대로 받지 않는다. 내 331 전수 측정과 factor DB 로 **교차 확인**한 뒤 기록한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[h1] ", fmt, "\n"), ...)); flush.console() }

say("=== 1. C 계열 팩터의 실제 배출 상태 (내 331 패널로 확인) ===")
FN <- readLines(file.path(OUT, "factors_eligible.txt"))
cs <- grep("^C0[0-9]|^C1[0-9]", FN, value = TRUE)
say("  331 적격 중 C 계열 %d건: %s", length(cs), paste(cs, collapse=", "))
for (k in c("C01","C04","C10","C13","C15")) {
  hit <- grep(sprintf("^%s_", k), FN, value = TRUE)
  say("  %-4s → %s", k, if (length(hit)) paste(hit, collapse=", ") else "★배출 없음(적격 331 에 부재)")
}

say("=== 2. ★C10 ≡ C01 · C13 ≡ C04 중복 주장 검증 (z 벡터 실측) ===")
A <- readRDS(file.path(OUT, "factor_long.rds"))
pairs <- list(c("C01","C10"), c("C04","C13"))
for (p in pairs) {
  a <- grep(sprintf("^%s_", p[1]), FN, value=TRUE)[1]
  b <- grep(sprintf("^%s_", p[2]), FN, value=TRUE)[1]
  if (is.na(a) || is.na(b)) { say("  %s vs %s — 한쪽 부재(a=%s b=%s)", p[1], p[2], a, b); next }
  W <- dcast(A[Factor_Name %in% c(a,b)], Date + Ticker ~ Factor_Name, value.var="z")
  x <- W[[a]]; y <- W[[b]]
  ok <- is.finite(x) & is.finite(y)
  say("  %-28s vs %-28s 겹침 %d행", a, b, sum(ok))
  say("    Pearson %.6f · Spearman %.6f · 완전동일 %s · 최대절대차 %.3e",
      cor(x[ok], y[ok]), cor(x[ok], y[ok], method="spearman"),
      identical(x[ok], y[ok]), max(abs(x[ok]-y[ok])))
}
say("  ★Pearson 만 보지 않는다 — 오늘 insider 에서 이상치 하나가 Pearson 을 1.0 으로 만든 전례")

say("=== 3. 내 331 측정에서 두 쌍의 성과가 동일한가 (중복의 독립 증거) ===")
TB <- fread(file.path(OUT, "c6_full_table.csv"))
for (p in pairs) {
  a <- grep(sprintf("^%s_", p[1]), TB$factor, value=TRUE)[1]
  b <- grep(sprintf("^%s_", p[2]), TB$factor, value=TRUE)[1]
  if (is.na(a) || is.na(b)) next
  ra <- TB[factor == a]; rb <- TB[factor == b]
  say("  %-26s rho %+.4f · IR %+.4f · ΔIR %+.4f", substr(a,1,26), ra$cor_un, ra$ir_un, ra$d_un)
  say("  %-26s rho %+.4f · IR %+.4f · ΔIR %+.4f", substr(b,1,26), rb$cor_un, rb$ir_un, rb$d_un)
  say("    → 동일 %s", identical(round(c(ra$cor_un, ra$ir_un), 6), round(c(rb$cor_un, rb$ir_un), 6)))
}

say("=== 4. C15 배출 여부 (그들 주장: not_emitted_zero_variance) ===")
c15 <- grep("^C15", FN, value=TRUE)
say("  적격 331 중 C15: %s", if (length(c15)) paste(c15, collapse=", ") else "★없음")
cov <- fread(file.path(OUT, "coverage.csv"))
c15c <- cov[grepl("^C15", Factor_Name)]
if (nrow(c15c)) { say("  coverage.csv 기록:"); print(c15c) } else
  say("  ★coverage.csv 에도 C15 부재 — 팩터 DB 가 이 이름을 배출하지 않는다")
say("  ⇒ 'C15 300개월 실림' 진술은 %s",
    if (!length(c15) && !nrow(c15c)) "**내 실측과 불일치** — 정정 대상 확인" else "재확인 필요")

say("=== 5. compute_consensus.R 배출 지점 ===")
if (file.exists("02_Infrastructure/factor_db/compute_consensus.R")) {
  L <- readLines("02_Infrastructure/factor_db/compute_consensus.R", warn=FALSE, encoding="UTF-8")
  hit <- grep("C01|C04|C10|C13|C15", L)
  say("  compute_consensus.R %d줄 · C 계열 언급 %d곳", length(L), length(hit))
  for (i in head(hit, 12)) say("    %4d: %s", i, substr(trimws(L[i]), 1, 96))
} else say("  ★compute_consensus.R 미발견")
say("=== h1 완료 ===")
