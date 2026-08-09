## 다음 알파 후보 census — 착수 가능(claim_state 기준) × 데이터 게이트 열림 × 비-return 우선
## v8.3 주력 레인 = 비-return 원천(FQ-001~005 계열). 헌법 존재의의 = 알파시킹.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/next_pick")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/claim_state.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue(); E <- Q$entries
say("=== 원장 %d 항목 ===", length(E))

get <- function(e, k) if (is.null(e[[k]])) "" else paste(e[[k]], collapse = " ")
D <- rbindlist(lapply(E, function(e) {
  cs <- claim_state(e)
  data.table(id = get(e,"id"), lane = get(e,"lane"),
             title = substr(gsub("[\r\n]+"," ", get(e,"title")), 1, 60),
             status = substr(get(e,"status"), 1, 32),
             claim = cs$state, src = cs$source, startable = isTRUE(cs$safe_to_start),
             data_gate = substr(gsub("[\r\n]+"," ", get(e,"data_gate")), 1, 70),
             ev = substr(gsub("[\r\n]+"," ", get(e,"ev_rationale")), 1, 200))
}), fill = TRUE)

say("=== 1. 배정 상태 분포 (선언 필드 기준) ===")
print(D[, .N, by = .(claim, src)][order(-N)])
say("  ★착수 가능(startable) = **%d건** / %d", D[startable == TRUE, .N], nrow(D))

say("=== 2. 착수 가능 항목의 lane 분포 ===")
print(D[startable == TRUE, .N, by = lane][order(-N)])

say("=== 3. ★데이터 게이트 열린 착수 가능 항목 ===")
gate_open <- D[startable == TRUE &
  (data_gate == "" | grepl("없음|OPEN|없다", data_gate)) &
  !grepl("closed|불가|미수집|부재", data_gate)]
say("  게이트 열림 %d건 / 착수가능 %d건", nrow(gate_open), D[startable==TRUE, .N])

say("=== 4. ★비-return 원천 우선 (v8.3 주력 레인) ===")
nr <- gate_open[grepl("non_return|비-return|DART|공매도|대차|특허|수급|인사|텍스트|계약|insider|투자자", paste(lane, title, ev))]
if (nrow(nr)) {
  for (i in seq_len(nrow(nr)))
    say("  %-8s | %-26s | %s", nr$id[i], substr(nr$status[i],1,26), nr$title[i])
} else say("  비-return 매칭 0건")

say("=== 5. 전체 착수 가능 목록 (게이트 열림) ===")
for (i in seq_len(nrow(gate_open)))
  say("  %-8s | %-24s | %s", gate_open$id[i], substr(gate_open$status[i],1,24), gate_open$title[i])

fwrite(D, file.path(OUT, "census_all.csv"))
fwrite(gate_open, file.path(OUT, "census_startable.csv"))
say("=== census 완료 → census_startable.csv (%d건) ===", nrow(gate_open))
