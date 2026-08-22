suppressPackageStartupMessages({library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB <- "qepm/mailbox/worktask/WT-D20260822_006"
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
## ast_verify.py 는 escape 계약을 **리프 노드 평면 키**에서 읽는다(ALB-001 방언 수용).
## 스키마는 escape_contract 하위를 요구한다. 두 계층을 동시에 만족시키려면 평면 미러가 필요.
n1 <- pkg$factors[[1]]$ast$args[[1]]
n1$op_code_path <- n1$escape_contract$op_code_path
n1$walk_forward <- TRUE
pkg$factors[[1]]$ast$args[[1]] <- n1
n2 <- pkg$factors[[2]]$ast
n2$provenance <- n2$escape_contract$provenance
n2$production_parity_verified <- FALSE
pkg$factors[[2]]$ast <- n2
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[flat mirror added]\n")
