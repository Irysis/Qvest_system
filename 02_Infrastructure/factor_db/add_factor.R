#==============================================================================
# add_factor.R — 선언형 팩터 온보딩 헬퍼 (2026-07-01)
#
# "적재 = 선언". custom_factors.json(compute spec) + factor_registry.json(metadata)를
#   한 번에 안전하게 기록. compute_custom_factors.R이 spec을 계산 → 빌더가 parquet에 반영.
#   복잡한(포뮬러 불가) 팩터는 여전히 전용 compute_*.R + registry 수동.
#
# 사용:
#   source("02_Infrastructure/factor_db/add_factor.R")
#   add_factor(id="M99_Mom_250_20", name="Momentum 250-20", category="momentum",
#              direction="higher_better", template="momentum", params=list(window=250, skip=20))
#   list_custom_factors(); remove_custom_factor("M99_Mom_250_20")
# 이후: build_factor_db(sig)로 검증 → backfill_custom_factor(id)로 이력 → discovery_explore --validate
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
.af_root <- function() Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
.af_spec  <- function() file.path(.af_root(), "02_Infrastructure", "factor_db", "custom_factors.json")
.af_regs  <- function() {  # 존재하는 모든 registry 경로 (canonical + .cache)
  c(file.path(.af_root(), "02_Infrastructure", "factor_db", "factor_registry.json"),
    file.path(.af_root(), ".cache", "factor_db", "factor_registry.json"))
}
.TEMPLATE_PARAMS <- list(
  momentum=c("window","skip"), reversal=c("window"), volatility=c("window"),
  mean_reversion=c("window"), trailing_agg=c("col","window","agg"),
  ratio=c("num","den"), gap_freq=c("window"))

.af_validate <- function(id, category, direction, template, params) {
  if (!grepl("^[A-Za-z0-9_]+$", id)) stop("id는 영숫자·_만: ", id)
  if (!template %in% names(.TEMPLATE_PARAMS)) stop("미지원 template: ", template, " (지원: ", paste(names(.TEMPLATE_PARAMS),collapse=", "), ")")
  if (!direction %in% c("higher_better","lower_better")) stop("direction=higher_better|lower_better")
  req <- setdiff(.TEMPLATE_PARAMS[[template]], if (template=="trailing_agg") "agg" else character(0))
  miss <- setdiff(req, names(params)); if (length(miss)) stop("template '",template,"' 필수 params 누락: ", paste(miss,collapse=", "))
  # 중복 체크 (custom + registry)
  spec <- .af_read_spec(); if (any(sapply(spec, function(s) identical(s$id, id)))) stop("이미 custom에 존재: ", id)
  for (rp in .af_regs()) if (file.exists(rp)) { r<-fromJSON(rp, simplifyVector=FALSE); if (id %in% names(r)) stop("이미 registry에 존재: ", id) }
  invisible(TRUE)
}
.af_read_spec <- function() { p<-.af_spec(); if (!file.exists(p)) return(list()); x<-fromJSON(p, simplifyVector=FALSE); if (is.null(x)) list() else x }

# ── registry 타겟 편집 (전체 reformat 없이 최소 diff; backup+validate+실패시 원복) ──
# registry는 373+ 엔트리 대형 파일. 전체 round-trip은 13k줄 reformat → diff·동시성 치명.
# 라인 기반: 루트 '}' 앞에 새 엔트리 append / 특정 id 블록만 삭제.
.reg_append_entry <- function(rp, id, entry) {
  bak <- paste0(rp, ".bak_af"); file.copy(rp, bak, overwrite=TRUE)
  ok <- tryCatch({
    lines <- readLines(rp, encoding="UTF-8", warn=FALSE)
    while (length(lines) && !nzchar(trimws(lines[length(lines)]))) lines <- lines[-length(lines)]
    if (trimws(lines[length(lines)]) != "}") stop("root close '}' not found")
    lf <- length(lines) - 1L                    # 마지막 팩터 close "  }"
    if (lf < 1L) stop("registry too small")
    lines[lf] <- paste0(sub("[[:space:]]+$", "", lines[lf]), ",")
    ej <- jsonlite::toJSON(entry, auto_unbox=TRUE, pretty=TRUE, null="null")
    ejl <- paste0("  ", strsplit(ej, "\n")[[1]])
    ejl[1] <- sub("^  \\{", paste0("  \"", id, "\": {"), ejl[1])
    con <- file(rp, open="wb"); writeLines(c(lines[1:lf], ejl, "}"), con, useBytes=TRUE); close(con)
    chk <- jsonlite::fromJSON(rp, simplifyVector=FALSE); !is.null(chk[[id]])
  }, error=function(e){ cat("  [reg_append ERR]", conditionMessage(e), "\n"); FALSE })
  if (!isTRUE(ok) && file.exists(bak)) file.copy(bak, rp, overwrite=TRUE)
  if (file.exists(bak)) file.remove(bak)
  isTRUE(ok)
}
.reg_remove_entry <- function(rp, id) {
  bak <- paste0(rp, ".bak_af"); file.copy(rp, bak, overwrite=TRUE)
  ok <- tryCatch({
    lines <- readLines(rp, encoding="UTF-8", warn=FALSE)
    st <- which(grepl(paste0("^  \"", id, "\": \\{"), lines))
    if (!length(st)) { TRUE } else {
      st <- st[1]; en <- NA_integer_
      for (k in (st+1L):length(lines)) if (grepl("^  \\},?$", lines[k])) { en <- k; break }
      if (is.na(en)) stop("entry close not found")
      was_last <- grepl("^  \\}$", lines[en])
      lines <- lines[-(st:en)]
      if (was_last && st-1L >= 1L) lines[st-1L] <- sub("\\},[[:space:]]*$", "}", lines[st-1L])
      con <- file(rp, open="wb"); writeLines(lines, con, useBytes=TRUE); close(con)
      chk <- jsonlite::fromJSON(rp, simplifyVector=FALSE); is.null(chk[[id]])
    }
  }, error=function(e){ cat("  [reg_remove ERR]", conditionMessage(e), "\n"); FALSE })
  if (!isTRUE(ok) && file.exists(bak)) file.copy(bak, rp, overwrite=TRUE)
  if (file.exists(bak)) file.remove(bak)
  isTRUE(ok)
}

add_factor <- function(id, name, category, template, params = list(),
                       direction = "higher_better", source = "rawdata",
                       evidence_tier = "D", definition = NULL, note = "",
                       sync_registry = TRUE) {
  .af_validate(id, category, direction, template, params)
  today <- as.character(Sys.Date())
  def <- definition %||% sprintf("custom(%s): %s", template, jsonlite::toJSON(params, auto_unbox=TRUE))

  # 1) custom_factors.json (compute spec + 메타)
  spec <- .af_read_spec()
  spec[[length(spec)+1L]] <- list(id=id, name=name, category=category, direction=direction,
    source=source, template=template, params=params, evidence_tier=evidence_tier,
    added_date=today, status="active", note=note, disabled=FALSE)
  write_json(spec, .af_spec(), auto_unbox=TRUE, pretty=TRUE, null="null")
  cat(sprintf("[add_factor] custom_factors.json 기록: %s (%s)\n", id, template))

  # 2) registry 동기화 (backup + round-trip + validate; 실패 시 복원)
  if (isTRUE(sync_registry)) {
    entry <- list(name=name, category=category, definition=def, direction=direction,
      data_source=source, lag_rule="Factor_Date <= sig_d", update_freq="monthly",
      labels=list(economic_family=category, construction="custom_template", neutrality="raw",
                  horizon="monthly", evidence_tier=evidence_tier, template=template),
      lifecycle=list(status="active", research_stage="S0", mutation_count=0, added_date=today,
                     origin="add_factor_custom"))
    for (rp in .af_regs()) {
      if (!file.exists(rp)) next
      if (.reg_append_entry(rp, id, entry)) cat(sprintf("  registry 동기화(append, 최소diff): %s\n", basename(rp)))
      else cat("  registry 동기화 실패 → 원복:", basename(rp), "\n")
    }
  }
  cat("\n다음 단계:\n")
  cat("  1) 검증(1개월): Rscript -e 'source(\"02_Infrastructure/factor_db/factor_db_builder.R\"); build_factor_db(\"2026-05-31\")' → parquet에", id, "확인\n")
  cat("  2) 백필(이력): source(\"02_Infrastructure/factor_db/add_factor.R\"); backfill_custom_factor(\"", id, "\")  # 또는 build_factor_db_monthly(force=TRUE)\n", sep="")
  cat("  3) 활용검증(패널증강+proxy/canonical): validate_new_factor(\"", id, "\")  # R 훅, discovery_explore 경유\n", sep="")
  invisible(id)
}

list_custom_factors <- function() {
  spec <- .af_read_spec()
  if (!length(spec)) { cat("(custom factor 없음)\n"); return(invisible(NULL)) }
  for (s in spec) cat(sprintf("  %-28s %-12s %-14s %s%s\n", s$id, s$category, s$template,
    jsonlite::toJSON(s$params, auto_unbox=TRUE), if (isTRUE(s$disabled)) "  [disabled]" else ""))
  invisible(spec)
}
remove_custom_factor <- function(id, from_registry = FALSE) {
  spec <- .af_read_spec(); n0<-length(spec); spec <- Filter(function(s) !identical(s$id, id), spec)
  write_json(spec, .af_spec(), auto_unbox=TRUE, pretty=TRUE, null="null")
  cat(sprintf("[remove] custom_factors.json: %s (%d→%d)\n", id, n0, length(spec)))
  if (isTRUE(from_registry)) for (rp in .af_regs()) if (file.exists(rp)) {
    if (.reg_remove_entry(rp, id)) cat("  registry 제거(최소diff):", basename(rp), "\n") }
  invisible(NULL)
}
# ── W3: 온보딩 검증 훅 — discovery_explore로 "이 팩터가 score_eff 대비 뭘 더하나" 실측 ──
# backfill_custom_factor 이후 호출. refresh=TRUE면 explore_panel에 팩터 컬럼 증강 후 validate.
# venv python.exe로 discovery_explore.py 직접 호출(Rscript 아님). proxy + canonical(contract) 둘 다 보고.
validate_new_factor <- function(id, refresh = TRUE) {
  root   <- .af_root()
  py     <- file.path(root, ".venv_qvest_ml", "Scripts", "python.exe")
  script <- file.path(root, "02_Infrastructure", "discovery", "discovery_explore.py")
  if (!file.exists(py))     stop("venv python 없음: ", py)
  if (!file.exists(script)) stop("discovery_explore.py 없음: ", script)
  old <- Sys.getenv("QM_ROOT", unset = NA); Sys.setenv(QM_ROOT = root)
  on.exit(if (is.na(old)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old))
  args <- character(0)
  if (isTRUE(refresh)) args <- c(args, "--refresh-factor", id)   # 패널 증강(신규 팩터 컬럼)
  args <- c(args, "--validate", id)
  cat(sprintf("[validate_new_factor] %s %s\n", basename(py), paste(c("discovery_explore.py", args), collapse = " ")))
  out <- system2(py, args = c(shQuote(script), args), stdout = TRUE, stderr = TRUE)
  cat(out, sep = "\n"); invisible(out)
}
cat("[add_factor] Loaded — add_factor() / list_custom_factors() / remove_custom_factor() / validate_new_factor()\n")
