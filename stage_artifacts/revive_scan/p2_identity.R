## 되살림 스크린 P2 — ★후보 3건의 **정체 검사** (존재 검사로 대체하지 말 것)
## 혐의: 3건이 전부 동일값 2.879 를 인용한다. 같은 측정의 재인용이거나,
##   '실패 판정' 이 아니라 **성공 라운드의 기준선(base)** 일 수 있다.
##   메모리: "MAX5 선례 실측 = 필터 ΔIR +0.1692 · PORT_t 2.879 -> 3.620 (WT-014)"
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")

for (k in c("FQ-103", "FQ-127", "FQ-161")) {
  i <- which(ids == k); if (!length(i)) { say("%s 부재", k); next }
  e <- Q$entries[[i]]
  b <- paste(unlist(e), collapse = " ")
  say("===== %s | status=%s", k, substr(e$status, 1, 40))
  pos <- gregexpr("2[.]879", b)[[1]]
  if (pos[1] < 0) { say("   2.879 미발견"); next }
  for (p in pos)
    say("   ...%s...", gsub("[\r\n]+", " ", substr(b, max(1, p - 150), min(nchar(b), p + 110))))
}

say("=== 판정 규약 ===")
say("  ★'실패 판정' 이려면 그 값이 **후보의 성과**여야 한다.")
say("    그것이 **기준선(base)** 이거나 **성공 라운드의 출발점**이면 되살림 대상이 아니다.")
say("    메모리 기록: MAX5 필터 라운드는 PORT_t 2.879 -> 3.620 으로 **성공**했다(WT-014).")
