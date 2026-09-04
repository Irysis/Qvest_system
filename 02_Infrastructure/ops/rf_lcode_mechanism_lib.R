#!/usr/bin/env Rscript
#==============================================================================
# rf_lcode_mechanism_lib.R — 블록 L-code 에 **기전 서술**을 얹는다 (도훈 지시 2026-09-04)
#
# 왜: 강화 레인의 L-code 는 전부 규칙 조립이다(측정표 -> sprintf). 규칙은 **무엇이
#   일어났는지**는 정확히 적지만 **왜**는 못 적는다. 실측 예 — 2026-09-04 B1 14칸에서
#   규칙이 낸 문장은 "최고 B1_4 t 1.454 · A0/B0/C10/F4" 였고, 정작 읽을 값은
#   "방어 계열 셋(vol_low·crisis_beta·beta_relevel)이 나란히 F 인데 같은 위험 축이라도
#   오버레이의 종목별 arm 은 통했다 — 소비 지점이 다르다" 쪽이었다.
#   lean-loop 는 "기전이 특정되는 실패만 적립" 이라 쓰는데 무인 레인엔 특정할 수단이 없어
#   전부 적립하고 있었다(73건).
#
# 경계 (구조로 강제):
#   ① LLM 은 **서술만** 쓴다. 수치·등급·next_probe 는 규칙이 이미 쓴 것을 건드리지 않는다.
#      병합은 R 이 한다 — 에이전트는 L-code 파일에 접근하지 않는다.
#   ② 이 블록 셀 코드를 최소 1개 인용해야 한다 — 일반론은 기전이 아니다.
#   ③ 등급·수치 주장 금지(정규식 차단). 진술이 계약과 충돌하면 그건 서술이 아니라 위조다.
#   ④ 실패는 조용하지 않다 — 기전 없이도 L-code 는 그대로 남는다(규칙 척추는 불변).
#
# 사용:
#   Rscript rf_lcode_mechanism_lib.R materials <base_id> <block_id> <out.txt>
#   Rscript rf_lcode_mechanism_lib.R merge     <base_id> <block_id> <mech.json>
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
setwd(ROOT)
.LOGP <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
dir.create(dirname(.LOGP), recursive = TRUE, showWarnings = FALSE)
.mx_log <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "lcode_mechanism"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = .LOGP, append = TRUE)
  cat(sprintf("[lcode_mech] %s\n", event))
}
.lc_path <- function(base_id, block_id)
  file.path(ROOT, "stage_artifacts/l_code/reinforcement",
            sprintf("l_code_%s_%s.json", base_id, block_id))

# ── materials — 이 블록의 표 + **이 entry 에 쌓인 앞선 교훈** ────────────────
#   도훈 지시: "이번 배치에서 쌓인 교훈들 참고해서 L-code 내용 작성".
#   앞 블록의 lesson_text·next_probes 를 같이 준다 — 기전은 블록 하나가 아니라
#   블록 사이에서 드러나는 일이 많다(오늘 B1 방어계열 F 와 B5 종목별 성공이 그랬다).
lcm_materials <- function(base_id, block_id, out_p) {
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"), local = TRUE))
  S <- rf_notify_table(base_id)
  if (is.null(S) || !nrow(S$tab)) stop("[lcode_mech] 측정표 없음: ", base_id)
  tab <- S$tab
  blk <- tab[grepl(paste0("^", block_id, "_"), code)]
  if (!nrow(blk)) stop("[lcode_mech] 블록 칸 없음: ", block_id)
  E <- S$entry
  dsc <- tryCatch(rf_cell_desc(base_id), error = function(e) list())
  ide <- setNames(vapply(E$attempts %||% list(),
                         function(a) as.character(a$idea %||% "")[1], character(1)),
                  vapply(E$attempts %||% list(),
                         function(a) as.character(a$cell_code %||% (a$essence$cell_code %||% ""))[1], character(1)))
  L <- c(sprintf("## 블록 %s — 측정 %d칸 (수치는 계약 산출물)", block_id, nrow(blk)),
         "code | grade | PORT_t | CAGR | Calmar | MDD | 처치")
  for (i in seq_len(nrow(blk))) {
    cd <- blk$code[i]
    tr <- as.character(dsc[[cd]] %||% ide[[cd]] %||% "")
    L <- c(L, sprintf("%s | %s | %.3f | %.3f | %.3f | %.3f | %s",
                      cd, blk$grade[i], blk$port_t[i], blk$cagr[i], blk$calmar[i], blk$mdd[i],
                      substr(gsub("\\s+", " ", tr), 1, 110)))
  }
  L <- c(L, "",
         sprintf("## 기저 — %s · 등급 %s", as.character(E$paper_key %||% base_id),
                 as.character(E$base_grade %||% "?")))
  # 이 entry 에 이미 쌓인 블록 L-code (누적 교훈)
  pri <- list()
  for (f in list.files(file.path(ROOT, "stage_artifacts/l_code/reinforcement"),
                       pattern = sprintf("^l_code_%s_B[0-9]+\\.json$", base_id), full.names = TRUE)) {
    b <- sub("^.*_(B[0-9]+)\\.json$", "\\1", basename(f))
    if (identical(b, block_id)) next
    d <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
    if (!is.null(d)) pri[[b]] <- d
  }
  if (length(pri)) {
    L <- c(L, "", sprintf("## 이 전략에 이미 쌓인 교훈 (%d블록) — 기전은 블록 사이에서 드러난다", length(pri)))
    for (b in names(pri)) {
      L <- c(L, sprintf("### %s", b),
             sprintf("- 규칙 요약: %s", substr(as.character(pri[[b]]$lesson_text %||% ""), 1, 300)))
      if (nzchar(as.character(pri[[b]]$mechanism %||% "")))
        L <- c(L, sprintf("- 기전(앞서 적힌 것): %s", substr(as.character(pri[[b]]$mechanism), 1, 300)))
      np <- pri[[b]]$next_probes %||% character(0)
      if (length(np)) L <- c(L, sprintf("- 다음 탐침: %s", paste(as.character(np), collapse = " / ")))
    }
  } else L <- c(L, "", "## 이 전략에 쌓인 앞선 블록 교훈: 없음(첫 블록)")
  writeLines(L, out_p, useBytes = TRUE)
  .mx_log("materials_written", base_id = base_id, block = block_id,
          cells = nrow(blk), prior_blocks = length(pri))
  invisible(out_p)
}

# ── merge — 검증 후 R 이 병합한다 (에이전트는 L-code 에 접근하지 않는다) ────
LCM_BANNED <- "(Grade\\s*[ABCF]\\b|등급\\s*[ABCF]\\b|합격|졸업|BOOK\\s*등재)"
lcm_merge <- function(base_id, block_id, mech_p) {
  bad <- function(why) { .mx_log("mechanism_rejected", base_id = base_id, block = block_id, why = why)
                         unlink(mech_p, force = TRUE); return(FALSE) }
  if (!file.exists(mech_p) || file.size(mech_p) == 0L) return(bad("기전 파일 부재"))
  M <- tryCatch(fromJSON(mech_p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(M)) return(bad("JSON 파싱 실패"))
  mech <- as.character(M$mechanism %||% "")[1]
  if (is.na(mech) || !nzchar(trimws(mech))) return(bad("mechanism 비어 있음"))
  if (nchar(mech) > 1200L) return(bad(sprintf("mechanism %d자 — 서술이 아니라 보고서", nchar(mech))))
  if (nchar(mech) < 40L) return(bad("mechanism 40자 미만 — 기전이 아니라 감상"))
  # ★이 블록 셀을 최소 1개 인용해야 한다 — 일반론은 기전이 아니다
  lp <- .lc_path(base_id, block_id)
  if (!file.exists(lp)) return(bad("L-code 파일 부재 — 규칙 척추가 먼저다"))
  if (!grepl(sprintf("%s_[0-9]+", block_id), mech)) return(bad("이 블록 셀 코드 인용 0건 — 일반론"))
  # ★등급·합격 주장 금지 — 판정은 계약이 한다(AX-008)
  if (grepl(LCM_BANNED, mech)) return(bad("등급·합격 주장 포함 — 판정은 계약 소관"))
  D <- tryCatch(fromJSON(lp, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(D)) return(bad("L-code 파싱 실패"))
  D$mechanism        <- mech
  D$mechanism_by     <- "llm:block_end"
  D$mechanism_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  D$prior_lessons_used <- as.character(unlist(M$prior_lessons_used %||% list()))
  D$mechanism_confidence <- as.character(M$confidence %||% "")
  write(toJSON(D, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), lp)
  .mx_log("mechanism_merged", base_id = base_id, block = block_id, chars = nchar(mech),
          prior = length(D$prior_lessons_used))
  TRUE
}

if (!interactive()) {
  a <- commandArgs(TRUE)
  if (length(a) >= 4L && identical(a[1], "materials")) lcm_materials(a[2], a[3], a[4])
  else if (length(a) >= 4L && identical(a[1], "merge"))
    quit(status = if (isTRUE(lcm_merge(a[2], a[3], a[4]))) 0L else 1L)
}
