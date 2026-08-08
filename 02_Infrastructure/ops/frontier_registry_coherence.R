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
# ★★★플래그 의미 정정 (2026-08-08 실측 — 다음 읽는 사람이 31건을 결함으로 오독하지 않도록):
#   현행 플래그는 "큐 frontier_open + negative 카드 매칭"인데, **INV-7 하에서 그것은
#   정상 상태다.** 인용된 DIST 카드를 전수 확인하니 **8/8(100%) 이 `retry_condition` 을
#   갖고 있다** — negative 카드는 방향을 닫지 않고 *재도전-조건부*로 바꾼다. 따라서
#   frontier_open 항목이 negative 카드를 인용하는 것은 그 자체로 충돌이 아니라
#   **의도된 재도전일 수 있다**.
#   실제 판별에 필요한 질문은 "큐가 시도하려는 접근이 카드가 **이미 측정한 것과 다른가**"이며,
#   이는 키워드·토큰으로 표현되지 않는다. 2026-08-08 에 자동 분류를 3겹 시도했고 전부 실패:
#     ① 도구 원본 키워드 매칭 → 31건(도구 자신이 위양성 경고)
#     ② 일반어 목록 기반 구체성 점수 → 21/21 이 "구체적"으로 나와 변별 실패
#     ③ 카드 retry_condition 과 어휘 겹침 → 중앙값 0.043 으로 변별 실패
#   ⇒ **자동 분류는 수렴하지 않는다**. 31건 중 10건은 자기 status 가 이미 negative 를 표시해
#     중복 경고이고, 나머지 21건은 항목별 사람 판단이 필요하다.
#   ★그 21건 중 5건을 카드 원문(statement_refined·scope_draft)과 직접 대조한 결과 **5/5 위양성**:
#     · FQ-122(vol·quality 를 타이브레이커/제외필터로) ↔ DIST-AR-003/007(scope=KR momentum)
#       → 재료도 소비면(비-slot)도 다름
#     · FQ-123(단기 vol 축 배선 진단) ↔ DIST-AR-009(scope=KR value, packaging 재조합 자본게이트)
#     · FQ-146(지수 FFT 스펙트럼 타이밍) · FQ-151(거래량 CV_Vol 오버레이) ↔ DIST-AR-018
#       (scope=distress_fingerprint_nonreturn) → 재료 무관
#     · FQ-108d(z vs 레벨 표현형태 진단) ↔ DIST-AR-001(defense composite 자본 sleeve)
#     기전 = 매칭 토큰이 **도메인 일반어**(신호·팩터·오버레이·tier·ic)라 범위가 달라도 걸린다.
#     ⇒ 이 스캔의 실효 정밀도는 낮다. **건수를 위험 신호로 읽지 말 것**; 개선하려면 매칭을
#       카드 `scope_draft` 와 큐 lane/재료의 **범위 일치**로 좁혀야 한다(토큰 빈도가 아니라).
#   ※ 부수: DIST 카드 필드명은 `statement_refined`·`retry_condition`·`scope_draft` 등이다
#     (`statement`/`summary`/`scope` 아님 — 이름을 가정하면 본문이 빈 채로 비교된다).
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

  ## ★2026-08-02 수리 — 도메인 공통어가 매칭을 만들던 결함(dead 축 lane 오염과 같은 계통):
  ##   card 매칭 표본에서 FQ-090↔DIST-AR-003 이 [신호, ic, port] 로, FQ-043↔DIST-AR-009 가
  ##   [value, 월말, 동일] 로 걸렸다 — 전부 이 저장소 문서 어디에나 나오는 말이다. 반면
  ##   FQ-004↔DIST-AR-018 은 [감사의견, going, concern] 로 **주제어가 겹친 정탐**이다.
  ##   공통어를 세지 않아야 정탐만 남는다.
  ## 하드코딩 목록 대신 **빈도로 판정**한다(IDF 발상): 카드 절반 이상에 등장하는 토큰은
  ##   변별력이 없다. 목록을 손으로 관리하면 새 공통어가 생길 때마다 오탐이 돌아온다.
  .tk_all <- unlist(lapply(dcards, `[[`, "tk"))
  .df <- table(.tk_all)
  STOPW <- names(.df)[.df >= max(2L, ceiling(length(dcards) * 0.5))]
  ## 안전판: 불용어가 전체 토큰의 다수를 먹으면 카드 축이 사실상 죽는다(오탐 제거 ≠ 검사 사망).
  if (length(STOPW) > length(unique(.tk_all)) * 0.3)
    stop("[coherence] 불용어가 토큰의 30% 초과 — 카드 축 무력화 위험. 임계 재검토 필요.")

  OPEN <- c("frontier_open", "parser_gated", "data_gate_measured")
  ## ★2026-08-02 수리 — 대상 선정이 open 후보의 19% 를 조용히 빼놓던 결함:
  ##   status 는 자유서술이라 'frontier_open' 이 **접미**로 오는 판이 흔하다
  ##   (config_scoped_negative_frontier_open 7건 · precheck_negative_frontier_open 1건 = 8건).
  ##   구판은 startsWith 만 봐서 이 8건을 스캔조차 안 했다. 구판이 변형 하나
  ##   (signal_round_negative_frontier_open)를 **손으로** OPEN 에 넣어둔 것이 "이 부류는 대상"
  ##   이라는 의도의 증거 — 변형이 늘 때마다 손으로 따라가는 구조라 누락이 기본값이었다.
  ##   포함-기반으로 교체(설정-scoped negative 라도 frontier 가 열려 있으면 착수 전 대상).
  ##   settled/done/closed 계열은 이 토큰을 갖지 않아 오편입 없음(실측 122 entries).
  is_open_status <- function(s) any(startsWith(s, OPEN)) || grepl("frontier_open", s, fixed = TRUE)
  rows <- list()
  for (e in Q$entries) {
    st <- g(e, "status")
    if (!is_open_status(st)) next                 # 이미 확정/차단된 항목은 대상 아님
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
      ov <- setdiff(intersect(hay, dc$tk), STOPW)   # 도메인 공통어 제외 (아래 STOPW 주석)
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

#==============================================================================
# frontier_citation_scan — 큐 인용이 원장에서 조회 가능한가 (CIT-1, 2026-08-08 신설)
#
# 왜 있나: 착수 전 사전확인은 큐에 적힌 수치를 원장에서 재확인하는 절차인데,
#   인용 키로 원장을 조회할 수 없으면 **사전확인이 큐 서술을 반복하는 것**이 된다.
#   2026-08-08 FQ-096 이 정확히 그 상태였다("풀 천장 2.937"을 큐 본문에서만 읽음).
#
# ★기전 = 네임스페이스 불일치(인덱싱 누락 아님). 실측:
#   · 큐 인용 고유 44건 중 **짧은 별칭 20건(45%)** 이 `WT-002`·`WT-014` 형태인데
#     원장 strategy_id 에 `WT-[0-9]{3}` 형식은 **0건** — 세션-로컬 번호다.
#   · 원장 ID 체계는 셋이 섞여 있다: `WT-D2026NNNN_NNN`(168) · `WT-P2026*`(5) ·
#     **라운드명**(`R32_FQ048_VALUE_OVERLAY_BOOK_RISKAXIS` — L-code 경로 등재분).
#   · ★별칭은 **전역적으로 모호**하다: 같은 `WT-002` 가 `WT-D20260718_002` 로도
#     `WT-D20260802_002` 로도 대응한다(세션마다 번호 재사용). 전역 사전을 만들면
#     다른 라운드를 가리키게 되므로, 해소는 **같은 FQ 항목 안의 문맥**으로만 안전하다.
#
# ★★위 coherence_scan 과 같이 **스크린이지 판정이 아니다**. 별칭 인용이 곧 결함은 아니며
#   (문맥으로 해소되면 무해), 출력은 "사전확인이 자립하지 못하는 항목" 후보다.
#   차단(게이트)은 행동 변경이라 도훈 승인 사항 — 이 함수는 보고만 한다.
#
# @return list(rows=data.table, n_flag=int, inputs=list)
frontier_citation_scan <- function(root = .fc_root()) {
  qf <- file.path(root, "06_Registry/alpha_frontier_queue.json")
  hf <- file.path(root, "06_Registry/hypothesis_index.json")
  if (!file.exists(qf) || !file.exists(hf))
    return(list(rows = data.table(), n_flag = 0L,
                inputs = list(entries = 0L, ledger = 0L, note = "input missing")))
  Q <- fromJSON(qf, simplifyVector = FALSE)
  H <- fromJSON(hf, simplifyVector = FALSE)
  gg <- function(x, k) { v <- x[[k]]; if (is.null(v)) "" else as.character(v)[1] }
  ids <- vapply(H$entries, function(e) gg(e, "strategy_id"), character(1))
  ids <- ids[nzchar(ids)]

  rows <- list()
  for (e in Q$entries) {
    blob <- paste(unlist(e[c("ev_rationale", "wall_check", "next_action",
                             "hypothesis", "source_refs")]), collapse = " ")
    if (!nzchar(blob)) next
    # 세션-로컬 별칭 vs 원장형 전체 ID
    short <- unique(regmatches(blob, gregexpr("WT-[0-9]{3}\\b", blob, perl = TRUE))[[1]])
    full  <- unique(regmatches(blob,
               gregexpr("WT[-_][DPH]2026[0-9]{4}_[0-9]{3}", blob, perl = TRUE))[[1]])
    if (!length(short) && !length(full)) next
    # 전체형이 원장에 실재하는가
    full_ok <- if (length(full)) vapply(full, function(w) any(grepl(w, ids, fixed = TRUE)),
                                        logical(1)) else logical(0)
    # 별칭이 같은 항목 문맥에서 해소되는가 (끝번호 대응)
    unresolved <- character(0)
    for (s in short) {
      num <- sub("^WT-", "", s)
      if (!any(grepl(paste0("_", num, "$"), full))) unresolved <- c(unresolved, s)
    }
    n_bad <- length(unresolved) + sum(!full_ok)
    if (!n_bad) next
    rows[[length(rows) + 1L]] <- data.table(
      id = gg(e, "id"), status = substr(gg(e, "status"), 1, 30),
      title = substr(gg(e, "title"), 1, 42),
      alias_unresolved = paste(utils::head(unresolved, 3), collapse = " ; "),
      full_missing = paste(utils::head(full[!full_ok], 2), collapse = " ; "),
      n_bad = n_bad)
  }
  R <- if (length(rows)) rbindlist(rows) else data.table()
  list(rows = R, n_flag = nrow(R),
       inputs = list(entries = length(Q$entries), ledger = length(ids)))
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
  # CIT-1 인용 검증 스캔 (보고만 — 차단 아님)
  cres <- frontier_citation_scan()
  if (!("--json" %in% args)) {
    cat(sprintf("\n=== 인용 검증 스캔 (CIT-1, 스크린) ===\n"))
    cat(sprintf("  큐 %d항목 / 원장 strategy_id %d\n", cres$inputs$entries, cres$inputs$ledger))
    cat(sprintf("  ★사전확인이 자립 못 하는 후보: %d건 (별칭 미해소 또는 전체형 원장 부재)\n",
                cres$n_flag))
    if (cres$n_flag) print(utils::head(cres$rows[order(-n_bad)], 15), row.names = FALSE)
    cat("  ※ 별칭 인용 자체는 결함 아님 — 같은 항목 문맥에서 해소되면 무해.\n")
    cat("     별칭은 세션마다 재사용되어 **전역적으로 모호**하므로 전역 사전 금지.\n")
  }
}
