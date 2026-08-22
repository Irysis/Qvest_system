suppressPackageStartupMessages({library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB <- "qepm/mailbox/worktask/WT-D20260822_006"
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
pkg$diagnostics$alpha_inheritance_note <- paste(
  "실측 0.9282 (rank 0.9323) — wt_type=discovery role card 문턱(< 0.95) 충족.",
  "다만 값이 문턱에 근접한 것은 설계상 필연이다: 전 처치 arm 이 u=0 에서 C0 로 정확히 환원되도록 만들어",
  "수준 틸트를 0 으로 두고 순수 상태-조절 성분만 차이가 나게 했기 때문이다(그래야 paired 차가 상태 효과와 동일).",
  "즉 본 라운드의 산출은 신규 알파 원천이 아니라 기존 결합 마디의 조절이며, 그 사실을 redundancy_cluster_id 로도 신고했다.",
  "판정이 powered null 이라 admission 경로 미진입 — certificate 미발급이 정상 동작.")
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[fixed]\n")
