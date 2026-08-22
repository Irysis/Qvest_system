suppressPackageStartupMessages(library(jsonlite))
source("02_Infrastructure/config.R")
MB <- "qepm/mailbox/worktask/WT-D20260822_004"
f <- file.path(MB,"alpha_package.json"); d <- fromJSON(f, simplifyVector=FALSE)
## ast_verify 는 SPECIAL_OP 계약 키를 **노드 수준**에서 읽는다 (FQ-237 산출물 형상 승계).
fix <- function(nd) {
  if (!is.list(nd)) return(nd)
  if (!is.null(nd$leaf) && identical(nd$leaf, "SPECIAL_OP") && !is.null(nd$escape_contract)) {
    ec <- nd$escape_contract
    nd$op_code_path <- ec$op_code_path; nd$walk_forward <- ec$walk_forward
    nd$statistic <- ec$statistic; nd$window_rule <- ec$window_rule
    return(nd)
  }
  if (!is.null(nd$args)) nd$args <- lapply(nd$args, fix)
  nd
}
d$factors <- lapply(d$factors, function(fc) { fc$ast <- fix(fc$ast); fc })
write_json(d, f, pretty=TRUE, auto_unbox=TRUE, digits=8, na="null"); cat("[patched ast]\n")
