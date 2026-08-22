suppressPackageStartupMessages({library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB <- "qepm/mailbox/worktask/WT-D20260822_006"
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
pkg$factor_specs[[1]]$economic_rationale <- "behavioral"
pkg$factor_specs[[1]]$economic_rationale_detail <- "오류 생성률(수익 횡단면 분산으로 관측) x 슬롯 배분 왜곡 규모(팩터 간 순위 불일치로 관측)의 곱 구조 — 개인·레버리지 주체의 오류 생성 + top-25 슬롯 희소성이 만드는 구성 규칙 왜곡."
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[fixed]\n")
