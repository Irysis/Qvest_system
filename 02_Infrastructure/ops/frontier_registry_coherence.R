#==============================================================================
# frontier_registry_coherence.R — 원장 3종 정합 스크린
#   alpha_frontier_queue  ×  research_ev_map(dead classes)  ×  distilled_knowledge
#
# 2026-08-02 신설. 근거 = 같은 날 3회 근접 사고(전부 수동 게이트가 잡음):
#   ① FQ-095 : 큐 frontier_open  vs  EV-지도 D2 dead(구조 판정)
#   ② FQ-004 : 큐 next_probe(07-14) vs DIST-AR-018(07-18) 이 그 방향을 닫음
#   ③ FQ-004/002 : EV-지도 R4 가 '세션 임의 착수 금지'로 명시한 lane
#
# ★공통 기전: 큐가 **자기보다 나중에 나온 판정을 반영하지 않는다**.
#   나중 판정이 앞선 등재를 무효화해도 앞선 등재가 그대로 남아, 게이트를 건너뛰면 그대로 밟는다.
#
# ★★이 스크립트는 **스크린이지 판정이 아니다.**
#   셀 매칭은 키워드 기반 휴리스틱이라 위양성이 나온다(오늘 금칙 ⑤ 확장이 로그 문자열 9건을
#   오검출한 것과 같은 부류). 출력은 "게이트 재검토 후보"이며, 실제 차단/해제는 사람이 3단
#   게이트를 돌려 판정한다. 건수를 결함 수로 보고하지 말 것.
#
# Usage: Rscript 02_Infrastructure/ops/frontier_registry_coherence.R [--json]
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.fc_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}

#' @param root 프로젝트 루트. 검사기가 픽스처로 호출할 수 있도록 인자화.
#' @return list(rows=data.table, n_flag=int, inputs=list)
frontier_coherence_scan <- function(root = .fc_root()) {
  qp <- file.path(root, "06_Registry/alpha_frontier_queue.json")
  mp <- file.path(root, "06_Registry/research_ev_map.json")
  dp <- file.path(root, "06_Registry/distilled_knowledge.json")
  # ★입력 부재를 '이상 없음'으로 흘리지 않는다 — 미측정과 정상은 다르다.
  miss <- c(qp, mp, dp)[!file.exists(c(qp, mp, dp))]
  if (length(miss)) stop("[coherence] 입력 부재(미측정, PASS 아님): ", paste(basename(miss), collapse = ", "))

  Q <- fromJSON(qp, simplifyVector = FALSE)
  M <- fromJSON(mp, simplifyVector = FALSE)
  D <- tryCatch(fromJSON(dp, simplifyVector = FALSE), error = function(e) NULL)

  g <- function(x, k) { v <- x[[k]]; if (is.null(v)) "" else paste(as.character(unlist(v)), collapse = " ") }
  norm <- function(s) tolower(gsub("[^가-힣a-z0-9]+", " ", tolower(s)))
  # 셀 라벨에서 의미 토큰만 추출(2자 이상). D-코드/숫자는 제외.
  toks <- function(s) {
    t <- unlist(strsplit(norm(s), "\\s+"))
    unique(t[nchar(t) >= 2 & !grepl("^[0-9]+$", t)])
  }

  dead <- lapply(M$dead_classes, function(x) list(class = g(x, "class"),
                                                  verdict = g(x, "verdict"), tk = toks(g(x, "class"))))
  # distilled 카드 — 실제 스키마 (2026-08-02 실측):
  #   entries[] 각각이 dist_id / polarity(negative|conditional|mixed|positive|unknown)
  #   / status(distilled|pending_5axis|expired|quarantined_evidence) / statement_refined / expiry.
  #   ★`verdict` 필드는 **없다**. 초판이 verdict~"NEG" 로 걸러 0건을 반환했고,
  #    그 0 이 '충돌 없음'으로 읽혀 카드 축이 통째로 죽어 있었다(이 저장소 반복 결함의 자기 재현).
  #   차단 자격 = polarity negative ∧ status distilled ∧ 미만료. expired 카드는 게이트하지 않는다.
  today <- Sys.Date()
  dcards <- list()
  if (!is.null(D) && length(D$entries)) {
    for (x in D$entries) {
      if (!is.list(x)) next
      if (!identical(g(x, "polarity"), "negative")) next
      if (!identical(g(x, "status"), "distilled")) next
      ex <- suppressWarnings(as.Date(g(x, "expiry")))
      if (!is.na(ex) && ex < today) next
      txt <- paste(g(x, "statement_refined"), g(x, "family"))
      dcards[[length(dcards) + 1L]] <- list(id = g(x, "dist_id"),
                                            title = substr(txt, 1, 80), tk = toks(txt))
    }
  }
  # ★양성 대조: 카드가 0건이면 그것은 '충돌 없음'이 아니라 **파싱 실패 의심**이다.
  #   distilled_knowledge 에 negative 카드가 하나도 없는 상태는 실무상 있을 수 없다.
  if (!length(dcards))
    stop("[coherence] DISTILLED_NEG 카드 0건 — 스키마 불일치로 카드 축이 죽었을 가능성. ",
         "0 을 '충돌 없음'으로 보고하지 않는다. distilled_knowledge.json 필드명 확인 필요.")

  OPEN <- c("frontier_open", "parser_gated", "data_gate_measured", "signal_round_negative_frontier_open")
  rows <- list()
  for (e in Q$entries) {
    st <- g(e, "status")
    if (!any(startsWith(st, OPEN))) next          # 이미 확정/차단된 항목은 대상 아님
    ## ★2026-08-02 수리 — 부정 선언이 긍정 매칭으로 뒤집히던 결함:
    ##   구판은 hay 에 lane 을 넣었다. norm() 이 "_" 를 공백으로 바꾸므로
    ##   lane="non_return" → 토큰 {non, return} 이 되고, 그 "return" 이 D1(횡단 return-파생)
    ##   dead 의 "return" 과 매칭됐다. 결과: **비-return 이라고 선언한 FQ 가 바로 그 선언 때문에
    ##   return-파생 dead 로 경고**받는다(실측 6건 중 5건이 이 오탐 — FQ-002/076/077/083/089).
    ##   v8.3 주력 lane 이 비-return 원천이라, 이 오탐은 검사기가 전략 방향을 정확히 거꾸로
    ##   유도한다. 수리 = ① lane 을 hay 에서 제외(lane 은 내용이 아니라 분류 라벨이다)
    ##   ② lane/본문이 비-return 을 선언하면 return-파생 dead 는 구조적으로 부적용.
    lane_raw <- g(e, "lane")
    body_raw <- paste(g(e, "title"), g(e, "hypothesis"))
    declares_non_return <- grepl("non[_ -]?return", lane_raw, ignore.case = TRUE) ||
                           grepl("non[_ -]?return|비[- ]?return|비-?수익|비수익", body_raw, ignore.case = TRUE)
    hay <- toks(body_raw)                       # lane 제외 (오염원)
    if (!length(hay)) next

    hit_dead <- character(0)
    for (dc in dead) {
      # 비-return 선언 FQ 에 return-파생 dead 를 씌우지 않는다(모순 배제).
      if (declares_non_return && grepl("return", dc$class, ignore.case = TRUE)) next
      ov <- intersect(hay, dc$tk)
      if (length(ov) >= 2L) hit_dead <- c(hit_dead, sprintf("%s [%s]", substr(dc$class, 1, 40),
                                                            paste(ov, collapse = ",")))
    }
    hit_card <- character(0)
    for (dc in dcards) {
      ov <- intersect(hay, dc$tk)
      if (length(ov) >= 3L) hit_card <- c(hit_card, sprintf("%s [%s]", dc$id, paste(ov, collapse = ",")))
    }
    ## lane 은 판정에서 뺐지만 보고에는 남긴다 — 사람이 오탐을 눈으로 거를 축이 필요하다.
    if (!length(hit_dead) && !length(hit_card)) next
    rows[[length(rows) + 1L]] <- data.table(
      id = g(e, "id"), status = st, lane = g(e, "lane"),
      title = substr(g(e, "title"), 1, 46),
      dead_hit = paste(utils::head(hit_dead, 2), collapse = " ; "),
      card_hit = paste(utils::head(hit_card, 2), collapse = " ; "))
  }
  R <- if (length(rows)) rbindlist(rows) else data.table()
  list(rows = R, n_flag = nrow(R),
       inputs = list(entries = length(Q$entries), dead = length(dead), neg_cards = length(dcards)))
}

# main-guard: Rscript 로 이 파일을 직접 실행한 경우에만 CLI 를 돈다.
#  `identical(environment(), globalenv())` 는 source() 에서도 참이라 모듈 로드 시 스캔이
#  덩달아 실행됐다(검사기에서 실측). --file 인자로 자기 자신을 확인한다.
.fc_invoked_directly <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  length(f) > 0L && grepl("frontier_registry_coherence\\.R$", f[1])
}
if (.fc_invoked_directly()) {
  args <- commandArgs(trailingOnly = TRUE)
  res <- frontier_coherence_scan()
  if ("--json" %in% args) {
    cat(toJSON(list(n_flag = res$n_flag, inputs = res$inputs,
                    rows = res$rows), auto_unbox = TRUE, pretty = TRUE), "\n")
  } else {
    cat(sprintf("=== frontier registry coherence (스크린) ===\n"))
    cat(sprintf("  큐 %d항목 / dead 계급 %d / DISTILLED_NEG 카드 %d\n",
                res$inputs$entries, res$inputs$dead, res$inputs$neg_cards))
    cat(sprintf("  ★게이트 재검토 후보: %d건 (판정 아님 — 3단 게이트로 사람이 확정)\n", res$n_flag))
    if (res$n_flag) print(res$rows, row.names = FALSE)
  }
}
