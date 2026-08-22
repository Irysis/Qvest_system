suppressPackageStartupMessages(library(jsonlite))
source("02_Infrastructure/config.R")
MB <- "qepm/mailbox/worktask/WT-D20260822_004"
f <- file.path(MB,"alpha_package.json"); d <- fromJSON(f, simplifyVector=FALSE)
## ast_verify 는 args 원소를 전부 노드(dict)로 요구한다 — 스칼라 경계는 args 가 아니라
## 노드 속성으로 옮긴다. 연산 의미 불변(CLIP(x,-2,2) == CS_WINSORIZE(x, limit=2.0)).
i <- which(vapply(d$factors, function(x) identical(x$factor_id,"FQ244_C2_winsor_z_ew"), TRUE))
child <- d$factors[[i]]$ast$args[[1]]$args[[1]]
d$factors[[i]]$ast <- list(op="CS_ZSCORE", args=list(list(
  op="CS_WINSORIZE", args=list(child), limit=2.0, limit_units="cross_sectional_z",
  limit_note="c=2.0 단일 사전고정(grid 아님). CLIP(x,-2,2) 와 동치이며 스칼라 경계를 args 가 아닌 노드 속성으로 둔다 — ast_verify 는 args 원소를 노드로 요구한다.")))
write_json(d, f, pretty=TRUE, auto_unbox=TRUE, digits=8, na="null"); cat("[patched clip]\n")
