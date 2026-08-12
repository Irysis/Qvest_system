## FQ-127 H2 — 원장만으로 **특정 날짜의 incumbent 를 확정**할 수 있는가 (V1 의 실질 검증)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  G1 은 **구조 판정**이었다(필드가 있다). 실질은 "실제로 재구성되는가" 이며, 그 시험 대상은
##  08-03 사고다: **같은 필터가 재구성 base +0.169 vs production base -0.149**(부호 반전).
##  ⇒ 질문: `book_state.json` 만 보고 **2026-08-03 시점의 incumbent(구성·IR·컨벤션)** 를 말할 수 있는가.
##  방법: 이벤트 타임스탬프를 뽑아 정렬하고, 대상일 **이전 최신 상태**를 재구성한다.
##  판정:
##   W1_RECONSTRUCTED : 대상일 이전 이벤트가 존재하고 그 시점의 admitted_ids·IR·convention 이 특정됨
##   W2_PARTIAL       : 시점은 잡히나 3요소 중 일부 결측
##   W3_FAILED        : 대상일 이전 상태를 특정 불가 → V1 은 형식뿐, 스키마 보강 필요
##  ★read-only. 05_Production 미접근.
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- ".claude/worktrees/jovial-mcnulty-f7d018/stage_artifacts/fq127_base_dependency_20260810"
TARGET <- as.POSIXct("2026-08-03 00:00:00", tz = "Asia/Seoul")
P <- "qepm/mailbox/governor/book_state.json"
stopifnot(file.exists(P))
J <- fromJSON(P, simplifyVector = FALSE)

## 1) 타임스탬프를 담은 필드 전수 수집 (최상위 + 1단 중첩)
grab_ts <- function(x, prefix = "") {
  out <- list()
  if (!is.list(x)) return(out)
  for (k in names(x)) {
    v <- x[[k]]
    if (is.character(v) && length(v) == 1L && grepl("^20[0-9]{2}-[01][0-9]-[0-3][0-9]", v)) {
      out[[length(out)+1L]] <- data.table(field = paste0(prefix, k), ts = substr(v, 1, 19))
    } else if (is.list(v)) {
      out <- c(out, grab_ts(v, paste0(prefix, k, ".")))
    }
  }
  out
}
TS <- rbindlist(grab_ts(J), fill = TRUE)
TS[, t := as.POSIXct(gsub("T", " ", ts), tz = "Asia/Seoul")]
TS <- TS[!is.na(t)][order(t)]
cat(sprintf("[타임스탬프] %d개 · 범위 %s ~ %s\n", nrow(TS),
            format(min(TS$t), "%Y-%m-%d"), format(max(TS$t), "%Y-%m-%d")))
cat("\n=== 대상일(2026-08-03) 전후 이벤트 ===\n")
before <- TS[t <= TARGET]; after <- TS[t > TARGET]
cat(sprintf("  이전 %d개 · 이후 %d개\n", nrow(before), nrow(after)))
if (nrow(before)) print(tail(before[, .(field, ts)], 5))
cat("  --- 대상일 2026-08-03 ---\n")
if (nrow(after)) print(head(after[, .(field, ts)], 3))

## 2) 대상일 시점의 3요소 특정
last_ev <- if (nrow(before)) tail(before, 1) else NULL
cat(sprintf("\n★대상일 직전 최신 이벤트: %s (%s)\n",
            if (!is.null(last_ev)) last_ev$field else "(없음)",
            if (!is.null(last_ev)) last_ev$ts else "-"))
gv <- function(k) if (k %in% names(J)) paste(as.character(unlist(J[[k]])), collapse = " · ") else NA_character_
ids  <- gv("admitted_ids"); wts <- gv("book_weights")
ir   <- gv("incumbent_book_ir"); conv <- gv("ir_convention")
name <- gv("current_pg2_official_name")
cat(sprintf("  admitted_ids  : %s\n", substr(ids, 1, 78)))
cat(sprintf("  book_weights  : %s\n", substr(wts, 1, 40)))
cat(sprintf("  incumbent_ir  : %s\n", substr(ir, 1, 40)))
cat(sprintf("  ir_convention : %s\n", substr(conv, 1, 60)))
cat(sprintf("  pg2 official  : %s\n", substr(name, 1, 70)))
## 08-03 이후 변경이 있었다면 현재값 != 당시값일 수 있다 — 그 여부를 명시
changed_after <- nrow(after) > 0L
cat(sprintf("\n대상일 이후 이벤트 존재: %s%s\n", changed_after,
            if (changed_after) " ⇒ **현재값을 당시값으로 읽으면 안 된다**. 직전 상태 필드로 되돌려야 함" else ""))
prior_fields <- names(J)[grepl("_prior_|_prev|_before", names(J))]
cat(sprintf("직전 상태 보존 필드 %d개: %s\n", length(prior_fields),
            substr(paste(prior_fields, collapse = " · "), 1, 150)))

have3 <- all(!is.na(c(ids, ir))) && !is.na(conv)
verdict <- if (!is.null(last_ev) && have3) "W1_RECONSTRUCTED" else
           if (!is.null(last_ev)) "W2_PARTIAL" else "W3_FAILED"
cat(sprintf("\n판정: %s\n", verdict))
cat("⚠한정: 대상일 이후 이벤트가 있으면 **현재 필드가 아니라 `*_prior_*` 를 읽어야** 당시 상태다.\n")
write_json(list(verdict = verdict, target = format(TARGET), n_ts = nrow(TS),
                n_before = nrow(before), n_after = nrow(after),
                last_event = if (!is.null(last_ev)) last_ev$field else NA,
                last_event_ts = if (!is.null(last_ev)) last_ev$ts else NA,
                prior_fields = prior_fields,
                current = list(admitted_ids = ids, ir = ir, convention = conv, pg2_name = name)),
           file.path(OUT, "h2_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
