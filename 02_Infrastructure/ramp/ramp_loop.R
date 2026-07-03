## ramp_loop.R — RAMP 자가발전 루프 헬퍼 (Observe + Document)
## 각 RAMP iteration이 호출: 시작 시 ramp_observe()(failure-ledger 읽어 반복 회피),
##   종료 시 ramp_document()(결과 L-code 적립). lcode_emit/harvester(mode-agnostic)와 정합.
suppressPackageStartupMessages({library(jsonlite)})
.RAMP_QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if(!exists("emit_lcode")) source(file.path(.RAMP_QM,"02_Infrastructure/axiom/lcode_emit.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a

## Observe/Diagnose: 기존 RAMP L-code 읽어 (1) failure-ledger(grade F, 반복금지) (2) 과거 findings 반환
ramp_observe <- function(verbose=TRUE){
  dir <- file.path(.RAMP_QM,"stage_artifacts/l_code/ramp")
  fs <- list.files(dir, pattern="\\.json$", full.names=TRUE)
  if(!length(fs)) { if(verbose) cat("[ramp_observe] L-code 0건 (첫 iteration)\n"); return(invisible(list(fails=data.frame(), findings=data.frame()))) }
  L <- lapply(fs, function(f) tryCatch(fromJSON(f), error=function(e) NULL))
  L <- Filter(Negate(is.null), L)
  tab <- data.frame(l_code=sapply(L,`[[`,"l_code"), grade=sapply(L,function(x)x$grade%||%""),
                    sid=sapply(L,function(x)x$strategy_id%||%""),
                    lesson=sapply(L,function(x)substr(x$lesson_text%||%"",1,70)), stringsAsFactors=FALSE)
  fails <- tab[tab$grade %in% c("F","FAIL"),,drop=FALSE]
  if(verbose){
    cat(sprintf("[ramp_observe] RAMP L-code %d건 적재 (findings %d / failure-ledger %d)\n",
                nrow(tab), sum(!tab$grade%in%c("F","FAIL")), nrow(fails)))
    if(nrow(fails)) for(i in seq_len(nrow(fails))) cat(sprintf("   ⛔ 반복금지[%s]: %s\n", fails$sid[i], fails$lesson[i]))
  }
  invisible(list(fails=fails, findings=tab[!tab$grade%in%c("F","FAIL"),,drop=FALSE], all=tab))
}

## Document: 결과 L-code 적립 (mode=ramp)
ramp_document <- function(strategy_id, grade, lesson_text, metrics=list(),
                          construction_type="chain", mechanism_hypothesis="", core_reference="", dry_run=FALSE){
  emit_lcode(mode="ramp", strategy_id=strategy_id, grade=grade, lesson_text=lesson_text,
             metric_type="backtested", construction_type=construction_type,
             mechanism_hypothesis=mechanism_hypothesis, core_reference=core_reference,
             tags=c("RAMP"), metrics=metrics, dry_run=dry_run)
}
cat("[ramp_loop.R] Loaded — ramp_observe() / ramp_document()\n")
