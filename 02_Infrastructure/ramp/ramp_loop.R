## ramp_loop.R — RAMP 자가발전 루프 헬퍼 (Observe + Document)
## 각 RAMP iteration이 호출: 시작 시 ramp_observe()(failure-ledger 읽어 반복 회피),
##   종료 시 ramp_document()(결과 L-code 적립). lcode_emit/harvester(mode-agnostic)와 정합.
## [2026-07-04 G-mode-wiring] emit v2 정비:
##   - ramp_document: default construction_type="chain" 제거 → 필수 인자화.
##     ('chain'은 selection_type의 값이지 construction(Independence 축) 값이 아님 —
##      기존 default가 r7 Independence 축 입력을 오염시키던 결함 교정. 호출부가 실값 전달 의무.)
##   - selection_type 별도 인자 신설 (measurement-graduation §3 sweep/chain 라벨 — DSR 게이트 경계).
##     emit v2(lcode_emit.R)가 selection_type 정식 인자를 갖추면 explicit 전달,
##     v1이면 metrics 경유 top-level 필드로 전달 (formals 감지 브리지 — lcode_emit.R 수정 금지 원칙).
##   - ramp_observe: xmode_keywords 인자 신설 — 06_Registry/hypothesis_index.json에서
##     타 모드(AS/QEPM/FR) verdict∈{FAIL,KILL} 교차조회 병합. 인자 미지정 시 현행 동일(순수 추가).
suppressPackageStartupMessages({library(jsonlite)})
.RAMP_QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if(!exists("emit_lcode")) source(file.path(.RAMP_QM,"02_Infrastructure/axiom/lcode_emit.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a

## Observe/Diagnose: 기존 RAMP L-code 읽어 (1) failure-ledger(grade F, 반복금지) (2) 과거 findings 반환
##   xmode_keywords: NULL(기본)=현행 동일. 문자 벡터 지정 시 hypothesis_index.json에서
##   타 모드 FAIL/KILL 실험을 AND-키워드 조회해 $xmode_fails로 병합 (INV-7 재도전 판단 입력).
ramp_observe <- function(verbose=TRUE, xmode_keywords=NULL){
  dir <- file.path(.RAMP_QM,"stage_artifacts/l_code/ramp")
  fs <- list.files(dir, pattern="\\.json$", full.names=TRUE)
  tab <- data.frame(); fails <- data.frame()
  if(length(fs)){
    L <- lapply(fs, function(f) tryCatch(fromJSON(f), error=function(e) NULL))
    L <- Filter(Negate(is.null), L)
    tab <- data.frame(l_code=sapply(L,`[[`,"l_code"), grade=sapply(L,function(x)x$grade%||%""),
                      sid=sapply(L,function(x)x$strategy_id%||%""),
                      lesson=sapply(L,function(x)substr(x$lesson_text%||%"",1,70)), stringsAsFactors=FALSE)
    fails <- tab[tab$grade %in% c("F","FAIL"),,drop=FALSE]
  } else if(verbose) cat("[ramp_observe] L-code 0건 (첫 iteration)\n")
  if(verbose && nrow(tab)){
    cat(sprintf("[ramp_observe] RAMP L-code %d건 적재 (findings %d / failure-ledger %d)\n",
                nrow(tab), sum(!tab$grade%in%c("F","FAIL")), nrow(fails)))
    if(nrow(fails)) for(i in seq_len(nrow(fails))) cat(sprintf("   ⛔ 반복금지[%s]: %s\n", fails$sid[i], fails$lesson[i]))
  }
  ## ── 타 모드 교차조회 (순수 추가 — xmode_keywords 미지정 시 no-op) ──
  xmode_fails <- data.frame()
  if(length(xmode_keywords)){
    xmode_fails <- tryCatch({
      hi_src <- file.path(.RAMP_QM,"02_Infrastructure/tools/hypothesis_index.R")
      if(!exists("lookup_hypothesis", mode="function") && file.exists(hi_src))
        source(hi_src, local=FALSE)   # lookup_hypothesis 재사용 (중복 구현 금지)
      hits <- lookup_hypothesis(xmode_keywords)
      if(is.data.frame(hits) && nrow(hits))
        hits[toupper(hits$verdict) %in% c("FAIL","KILL"),,drop=FALSE] else data.frame()
    }, error=function(e){
      if(verbose) cat(sprintf("[ramp_observe][WARN] xmode 교차조회 실패: %s (계속)\n", conditionMessage(e)))
      data.frame()
    })
    if(verbose && nrow(xmode_fails)){
      cat(sprintf("[ramp_observe] 타 모드 FAIL/KILL %d건 (hypothesis_index, kw=%s) — 차별점 없인 동일 재실험 금지(INV-7 재도전 사유 기록):\n",
                  nrow(xmode_fails), paste(xmode_keywords, collapse=" ")))
      for(i in seq_len(min(nrow(xmode_fails),10)))
        cat(sprintf("   ⛔ [%s|%s] %s\n", xmode_fails$verdict[i], xmode_fails$strategy_id[i], xmode_fails$title[i]))
    } else if(verbose) cat(sprintf("[ramp_observe] 타 모드 FAIL/KILL 히트 0건 (kw=%s)\n", paste(xmode_keywords, collapse=" ")))
  }
  invisible(list(fails=fails, findings=if(nrow(tab)) tab[!tab$grade%in%c("F","FAIL"),,drop=FALSE] else tab,
                 all=tab, xmode_fails=xmode_fails))
}

## Document: 결과 L-code 적립 (mode=ramp) — emit v2 필수필드 정비 (2026-07-04)
##   construction_type: 필수 (r7 Independence 축 — 예: "regime_ic_weighted_composite". 'chain' 금지: selection_type 값).
##   selection_type   : 필수 ("sweep"|"chain" — measurement-graduation §3 selection operator 라벨).
ramp_document <- function(strategy_id, grade, lesson_text, construction_type, selection_type,
                          metrics=list(), mechanism_hypothesis="", core_reference="", dry_run=FALSE, ...){
  if(missing(construction_type) || !nzchar(construction_type %||% ""))
    stop("[ramp_document] construction_type 필수 인자 (emit v2 — default 'chain' 제거. r7 Independence 축 실값 전달, LCODE_VALID_CONSTRUCTION_TYPES 참조)")
  if(missing(selection_type) || !(selection_type %in% c("sweep","chain","single")))
    stop("[ramp_document] selection_type 필수 인자 ('sweep'/'chain'/'single' — measurement-graduation §3 + lcode_schema LCODE_VALID_SELECTION_TYPES)")
  if(construction_type %in% c("chain","sweep","single"))
    stop("[ramp_document] construction_type='",construction_type,"'은 selection_type 값 — construction(구성 방식) 실값을 전달")
  # emit v2 시그니처 브리지: lcode_emit.R v2는 selection_type 1급 인자 — explicit 전달.
  # (혹시 v1 환경이면 metrics 경유 top-level 필드로 폴백 — emit_lcode는 metrics를 lcode 최상위에 병합.)
  args <- c(list(mode="ramp", strategy_id=strategy_id, grade=grade, lesson_text=lesson_text,
                 metric_type="backtested", construction_type=construction_type,
                 mechanism_hypothesis=mechanism_hypothesis, core_reference=core_reference,
                 tags=c("RAMP"), dry_run=dry_run), list(...))   # v2 1급 인자(falsification_attempts/oos_retention/portfolio_alpha_t 등) 그대로 통과
  if("selection_type" %in% names(formals(emit_lcode))){
    args$selection_type <- selection_type
    args$metrics <- metrics
  } else {
    args$metrics <- c(metrics, list(selection_type=selection_type))
  }
  do.call(emit_lcode, args)
}
cat("[ramp_loop.R] Loaded — ramp_observe(xmode_keywords=) / ramp_document(construction_type·selection_type 필수)\n")
