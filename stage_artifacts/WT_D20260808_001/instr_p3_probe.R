## INSTR-P3 — 주요 러너가 '도구 실패'와 '대상 실패'를 구별하는가 (실측 후 판단)
## 방법: 각 러너를 **의도적으로 길을 잃게** 만들고(위반 주입) 출력이 어느 쪽으로 읽히는지 본다.
## ★규약을 먼저 만들지 않는다 — 구별이 실제로 무너지는지 재고 나서 결정한다.
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[p3] ",fmt,"\n"),...))

runners <- list(
  list(nm="contract_regression (수리됨)", cmd="Rscript -e 'source(\"08_Tests/contract_regression/run_contract_regression.R\")'", dir="08_Tests/contract_regression"),
  list(nm="regime run_all",              cmd="Rscript -e 'source(\"run_all.R\")'",                                              dir="08_Tests/regime"),
  list(nm="hooks run_all",               cmd="bash run_all_hooks.sh",                                                            dir="08_Tests/hooks")
)

say("=== 정상 실행 시 최종 줄 (기준선) ===")
for (r in runners) {
  out <- tryCatch(system(sprintf("cd \"%s\" && %s 2>&1 | tail -3", r$dir, r$cmd), intern=TRUE),
                  error=function(e) "(<실행 실패>)")
  last <- paste(tail(out, 2), collapse=" | ")
  say("%-30s %s", r$nm, substr(gsub("[[:space:]]+"," ", last), 1, 110))
}

say("")
say("=== 판단 재료: 각 러너가 '수집 실패'를 별도 표기하는가 (코드 스캔) ===")
files <- c("08_Tests/contract_regression/run_contract_regression.R",
           "08_Tests/regime/run_all.R",
           "08_Tests/hooks/run_all_hooks.sh",
           "02_Infrastructure/ops/suite_totals_watch.sh")
for (f in files) {
  if (!file.exists(f)) { say("%-52s (부재)", f); next }
  ln <- readLines(f, warn=FALSE)
  ## '도구 실패' 를 대상 실패와 구별해 말하는 표지가 있는가
  mark <- sum(grepl("도구 경로 실패|수집 실패|계약 실패가 아", ln, fixed=FALSE)) +
          sum(grepl("null 로 남긴", ln, fixed=TRUE))
  say("%-52s 구별 표지 %d건", f, mark)
}
