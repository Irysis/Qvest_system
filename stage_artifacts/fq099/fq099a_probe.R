suppressPackageStartupMessages({ library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099a] ",fmt,"\n"),...))
flow <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")
say("유량의존 팩터 %d건", length(flow))
srcs <- c("base_recompute"="stage_artifacts/WT_D20260425_010/_recompute_alpha_asof.R",
          "m4_factor_engine"="qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R")
for (nm in names(srcs)) {
  p <- srcs[[nm]]
  if (!file.exists(p)) { say("%s : 파일 부재 %s", nm, p); next }
  txt <- paste(readLines(p, warn=FALSE), collapse="\n")
  ## ★fixed=TRUE 필수 — \b 는 한글 섞이면 조용히 FALSE (오늘 실측)
  hit <- flow[sapply(flow, function(k) grepl(k, txt, fixed=TRUE))]
  say("%-18s (%d줄) → 유량의존 팩터 %d건%s", nm, length(strsplit(txt,"\n")[[1]]), length(hit),
      if (length(hit)) paste0(": ", paste(hit, collapse=" ")) else "")
  ## 양성 대조: 이 파일이 팩터코드를 언급하기는 하는가 (0건이 '팩터 안 씀'인지 '스캐너 사망'인지 구별)
  anyfac <- sum(sapply(c("V01","V02","Q07","M08","D25","INV01"), function(k) grepl(k, txt, fixed=TRUE)))
  say("   └ 양성 대조: 알려진 팩터코드 6종 중 %d종 등장 (0 이면 이 파일은 팩터코드를 안 쓴다)", anyfac)
}
