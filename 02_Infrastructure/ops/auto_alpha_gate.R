#!/usr/bin/env Rscript
# auto_alpha_gate.R — 자동 alpha-search 산출물 검증 게이트 (도훈 mandate 2026-06-18)
# 무인 AUTORUN 전용. 5층 검증 verdict를 받아 ADOPT(권위 L-code 적립) / QUARANTINE(검수 대기) 결정.
# 결정은 *결정적*(코드)으로 — LLM이 임의로 ADOPT 못 하게 한다. fail-closed(불명확→QUARANTINE).
#
# 규칙: PIT는 hard(단독 FAIL→QUARANTINE). 무인이므로 contract·robustness·fidelity 전부 PASS여야 ADOPT
#       (4/4 — AX-008 2/3보다 보수적, 사람 검수자 부재 보정).
# 입력: auto_verify_<id>.json {paper_id, pit_pass, contract_pass, robustness_pass, fidelity_pass, oos_retention, port_t, notes}
# 출력: 같은 JSON에 gate_decision/gate_failed_layers/gate_rule 기록 + stdout "ADOPT"/"QUARANTINE: ...". exit 0=ADOPT,1=QUARANTINE,2=error.
suppressMessages(library(jsonlite))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) { cat("QUARANTINE: no verification json arg\n"); quit(status = 2) }
vf <- args[1]
if (!file.exists(vf)) { cat("QUARANTINE: verification json missing\n"); quit(status = 2) }
v <- tryCatch(fromJSON(vf, simplifyVector = TRUE), error = function(e) NULL)
if (is.null(v) || !is.list(v)) { cat("QUARANTINE: unreadable verification json\n"); quit(status = 2) }

tb <- function(x) {
  if (is.null(x) || length(x) == 0) return(FALSE)
  isTRUE(x) || tolower(as.character(x)[1]) %in% c("true", "pass", "1", "yes")
}
layers <- c(
  pit        = tb(v$pit_pass),
  contract   = tb(v$contract_pass),
  robustness = tb(v$robustness_pass),
  fidelity   = tb(v$fidelity_pass)
)
failed <- names(layers)[!layers]
adopt <- isTRUE(layers[["pit"]]) && all(layers[c("contract", "robustness", "fidelity")])
decision <- if (adopt) "ADOPT" else "QUARANTINE"

v$gate_decision <- decision
v$gate_failed_layers <- if (length(failed)) paste(failed, collapse = ",") else ""
v$gate_rule <- "PIT hard + contract&robustness&fidelity all PASS (unattended 4/4, fail-closed)"
v$gate_checked_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
tryCatch(write(toJSON(v, pretty = TRUE, auto_unbox = TRUE, na = "null"), vf),
         error = function(e) NULL)

cat(sprintf("%s%s\n", decision,
            if (length(failed)) sprintf(": failed=%s", paste(failed, collapse = ",")) else ""))
quit(status = if (adopt) 0L else 1L)
