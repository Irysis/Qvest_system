# distill_stats.R — weekly/monthly distill 공용 통계 소스 (2026-07-25 신규)
#
# 배경: weekly_distill/monthly_distill의 두 스텝이 죽은 소스를 참조하고 있었음.
#   ① `qepm/registry/experiments.json` — 파일 자체가 부재 → 주간 실험 요약이 항상 0건
#   ② `update_memory_summary()` — methodology_active.md 등 구 경로 부재(v2 Ledger 이관)로
#      "No methodology file found" no-op. 게다가 MEMORY.md를 정규식으로 덮어쓰는 함수라
#      무인 루틴이 호출할 대상이 아님(사용자 메모리 인덱스 훼손 위험) → 호출 제거.
# 현행 권위 소스:
#   - `06_Registry/hypothesis_index.json` — 가설/검증 Ledger(entries[].date/verdict/grade)
#   - `06_Registry/knowledge_index.json`  — counts{active_law, active_distilled, lcode_corpus, archived}
# 둘 다 weekly_cleaner_sweep(inv_hypothesis_index / knowledge_index 스텝)이 주간 재생성.
# 2026-08-24 배선: 주간 재생성만으로는 **부팅 없는 세션의 L-code 적립**이 인덱스에 안 닿는다
#   (실사고: index 530 / corpus 543, 8h45m 낙후). qv_ledger_stats() 가 소비 직전 신선도를
#   검사하고 STALE 이면 1회 복구한다 — 상세·근거는 .qv_heal_knowledge_index() 주석 참조.

suppressWarnings(suppressMessages(library(jsonlite)))

.qv_root <- function() {
  r <- Sys.getenv("QM_ROOT", unset = Sys.getenv("CLAUDE_PROJECT_DIR", ""))
  if (nzchar(r) && dir.exists(r)) return(r)
  if (exists("PROJECT_ROOT", inherits = TRUE) &&
      dir.exists(file.path(get("PROJECT_ROOT", inherits = TRUE), "06_Registry"))) {
    return(get("PROJECT_ROOT", inherits = TRUE))
  }
  getwd()
}

# ── knowledge_index 소비면 자가치유 (2026-08-24 배선) ────────────────────────
# 배경: 검사기 `check_knowledge_index_freshness()` 와 복구기 `repair_knowledge_index()` 는
#   2026-08-20 에 둘 다 구현되고 검출력 17/17 로 실증됐는데 **생산 호출자가 0** 이었다
#   (유일한 호출자 memory_knowledge_health.R:928 은 경보만 내고 끝난다).
#   실사고 2026-08-24: knowledge_index 가 원천 .cache/lcode_corpus.json 보다 8h45m 뒤처져
#   L-code 13건 결손(index 530 / corpus 543)인 채로 소비됐다 — 주간·월간 증류와 세션
#   브리핑이 그 결손 수치를 그대로 "지식 Ledger" 로 보고한다.
#
# ★자리 선택 근거 (knowledge_index_freshness.R:264-280 저자 검토 기록을 뒤집지 않는다):
#   재빌드를 *검사기* 에 붙이면 (a) build_knowledge_index() 가 정본 06_Registry/
#   knowledge_index.{json,md} 를 재작성하므로 dry-run 라벨이 부작용을 위장하고(WCS-06),
#   (b) 계기가 자기가 신고할 증거를 지운다(낙후가 corpus 손상에서 왔을 때 원인을 덮어씀).
#   그래서 자가치유는 **소비면 진입점**에 둔다 — hypothesis_index 가 자가치유를
#   lookup_hypothesis()(consumer 진입점)에 두고 health check 에는 두지 않은 것과 같은 자리다.
#   qv_ledger_stats() 는 이 저장소에서 knowledge_index 를 읽는 **유일한 R 소비 함수**라
#   (weekly_distill.R:36 · monthly_distill.R:58 · loop_integrator.R:92 · daily_refresh.sh:618
#    이 전부 여기를 지난다) 진입점 1곳 배선으로 R 소비면 전부가 덮인다. 소비면마다 검사를
#   중복 부착하면 같은 실행에서 검사가 N회 돌 뿐 도달 범위는 같다.
#
# 계약: 검사 → STALE 이면 복구 **1회** → 소비. **재시도 루프 없음.**
#   실패는 경보 후 기존 인덱스로 진행한다(fail-open) — 증류가 인덱스 낙후로 멈추면 안 된다.
#   SKIP(입력 부재·파싱 실패·스키마 이탈)은 복구하지 않는다 = 검사기의 폴백 의미론 그대로.
#   반환값은 "복구가 실제로 일어났는가"(TRUE/FALSE)이며 소비 경로의 판정에는 쓰이지 않는다.
.qv_heal_knowledge_index <- function(root, verbose = TRUE) {
  kif <- file.path(root, "02_Infrastructure", "ops", "knowledge_index_freshness.R")
  if (!file.exists(kif)) return(invisible(FALSE))
  out <- tryCatch({
    # ★source(local = TRUE) 격리 (memory_knowledge_health.R:928 과 같은 idiom):
    #   검사기는 자기 `%||%` 를 무조건 정의한다(knowledge_index_freshness.R:44). 전역으로
    #   새면 호출자 판본의 의미론을 갈아치운다 — 그 반대 방향 오염이 2026-08-20 에 이
    #   검사기를 status=SKIP("length = 4" 강제변환 오류)으로 조용히 무력화시킨 기전이다.
    #   local=TRUE 는 정의를 이 프레임에 가두므로 qv_ledger_stats() 의 `%||%` 는 무사하다.
    source(kif, local = TRUE)
    r <- check_knowledge_index_freshness(root = root)
    if (!identical(r$status, "STALE")) {
      FALSE
    } else {
      if (verbose) message(sprintf("[ledger] knowledge_index 낙후 감지(%s) → 소비 전 인라인 복구 1회",
                                   r$reason))
      res <- repair_knowledge_index(root = root, verbose = FALSE)
      done <- isTRUE(res$rebuilt) && identical(res$after$status, "OK")
      if (verbose) {
        if (done) message(sprintf("[ledger] 복구 완료 — corpus %d / index %d 일치",
                                  res$after$n_corpus, res$after$n_index))
        else message(sprintf("[ledger][경고] 복구 미해소(rebuilt=%s status=%s) — 기존 인덱스로 진행",
                             res$rebuilt, res$after$status))
      }
      done
    }
  }, error = function(e) {
    # fail-open: 복구가 죽어도 소비는 계속된다.
    message("[ledger][경고] knowledge_index 자가치유 실패 — 기존 인덱스로 진행: ",
            conditionMessage(e))
    FALSE
  })
  invisible(isTRUE(out))
}

#' 지식 Ledger 카운트 (knowledge_index.json)
#' @param auto_repair 소비 직전 신선도 검사 + STALE 1회 복구 (기본 TRUE).
#'   FALSE 면 종전대로 파일을 그대로 읽는다(검사기·감사기가 낙후 상태 자체를 재야 할 때).
#' @return list(law, distilled, lcode, archived, generated_at) — 파일 부재 시 NA + source="missing"
qv_ledger_stats <- function(root = .qv_root(), auto_repair = TRUE) {
  # ★소비 직전 자가치유 — 아래 fromJSON 이 이 함수의 소비 지점이다.
  if (isTRUE(auto_repair)) .qv_heal_knowledge_index(root)
  p <- file.path(root, "06_Registry", "knowledge_index.json")
  if (!file.exists(p)) return(list(law = NA_integer_, distilled = NA_integer_,
                                   lcode = NA_integer_, archived = NA_integer_,
                                   generated_at = NA_character_, source = "missing"))
  j <- fromJSON(p, simplifyVector = FALSE)
  c0 <- j$counts %||% list()
  list(law          = as.integer(c0$active_law       %||% NA),
       distilled    = as.integer(c0$active_distilled %||% NA),
       lcode        = as.integer(c0$lcode_corpus     %||% NA),
       archived     = as.integer(c0$archived         %||% NA),
       generated_at = as.character(j$generated_at    %||% NA),
       source       = "knowledge_index.json")
}

#' 최근 N일 리서치 판정 요약 (hypothesis_index.json)
#' @param days 조회 창(일). 기본 7 = 주간.
#' @return list(n, verdicts(정렬 table), since, generated_at, source)
qv_recent_research <- function(days = 7L, root = .qv_root()) {
  p <- file.path(root, "06_Registry", "hypothesis_index.json")
  since <- format(Sys.Date() - days, "%Y-%m-%d")
  if (!file.exists(p)) return(list(n = 0L, verdicts = integer(0), since = since,
                                   generated_at = NA_character_, source = "missing"))
  j <- fromJSON(p, simplifyVector = FALSE)
  e <- j$entries %||% list()
  d <- vapply(e, function(x) as.character(x$date    %||% ""),   character(1))
  v <- vapply(e, function(x) as.character(x$verdict %||% "NA"), character(1))
  sel <- nzchar(d) & d >= since
  list(n = sum(sel),
       verdicts = sort(table(v[sel]), decreasing = TRUE),
       since = since,
       generated_at = as.character(j$generated_at %||% NA),
       source = "hypothesis_index.json")
}

#' 콘솔 한 줄 요약 (verdict 상위 k종)
qv_verdict_line <- function(rr, k = 4L) {
  if (!length(rr$verdicts)) return("(판정 기록 없음)")
  tv <- head(rr$verdicts, k)
  paste(names(tv), as.integer(tv), sep = ":", collapse = " ")
}
