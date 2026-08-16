# close_round.R — 건설적 라운드 종료 계약 (Continuity Firewall L3)
#
# 도훈 mandate 2026-07-15: "자체적으로 포기하지 않는 자가발전형 아키텍처. 누적 실패 후
#   '끝남 표현들'로 라운드를 마무리하려는 것을 원천차단."
#
# 원리: "make the right thing the only expressible thing." 리서치 라운드를 닫는 유일한
#   깔끔한 경로 = close_round() 호출. next_probe≥2 · 소비면(consumer_surfaces) · frontier ·
#   (negative면) 부활 조건(live_trigger)을 *인자로 강제*해야만 종료 기록이 발행된다.
#   → 계속을 '생산'하지 않으면 함수가 stop()으로 거부(단어만 지우고 멈추기 봉쇄).
#   발행되는 마커(.cache/last_round_closure.json)를 Stop 게이트(continuity_gate.py)가 읽어
#   자동 통과 → 종료가 '계약 충족'과 물리적으로 묶인다. Q-Lead는 이 함수의 반환 요약에서
#   그대로 보고(구조화 필드 = 서술의 원천).
#
# 정합: answer-principles 연속성 3호(next_probe≥2)·4호(소비처 전개)·INV-7(부활 조건).
#   판정 자체는 막지 않는다 — negative·천장·config-scoped는 정당(AX-000). 막는 건 '계속 결측'뿐.

suppressWarnings(suppressMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("close_round: jsonlite 필요")
}))

.cr_root <- function() {
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(v)) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(cand)) return(cand)
  getwd()
}

.CR_VERDICT_TYPES <- c(
  "config_scoped_negative",       # 이 config가 측정틀에서 미달 (재료/구성 등 경로-scoped)
  "ceiling_reached_frontier_open",# 천장 도달, 미검 축/프론티어 열림
  "screen_tier_routed",           # 자본 미달이나 신호 실재 → overlay/feature/RAMP 라우팅
  "revival_conditional",          # 부활 조건 충족 시 재도전 대기
  "incumbent_confirmed",          # 현직 확정 (도전자 미달)
  "capability_established"         # 능력 확립 (positive — 소비면 전개 대상)
)
.CR_NEGATIVE_TYPES <- c("config_scoped_negative", "screen_tier_routed", "revival_conditional")

#' close_round — 리서치 라운드를 계약에 맞게 닫고 종료 마커를 발행한다.
#'
#' @param round_id      라운드 식별자 (예 "R31" / "FQ-047" / "WT-D...").
#' @param verdict_type  .CR_VERDICT_TYPES 중 하나. '완결/종결/소진 판정' 같은 종결어휘 금지 —
#'                      구조화 enum으로만 판정을 표현.
#' @param mechanism_diagnosis  왜 이 결과인지 기전 1줄 (≥20자, 연속성 3호).
#' @param next_probes   다음 가설/프로브 문자열 벡터 (≥2, 연속성 3호). 저순위 운영태스크로
#'                      접기 금지 — 실제 다음 탐색 축.
#' @param consumer_surfaces  소비면 라우팅 (팩터랭킹/유니버스/오버레이/위험/monitoring/선별라벨/
#'                      타모드) 문자열 벡터 (연속성 4호).
#' @param frontier_update  frontier 큐 갱신 서술 (FQ-id + status) 또는 NULL.
#' @param live_trigger  부활 조건 (negative 판정 시 필수, INV-7). 경로-scoped 재도전 신호.
#' @param layer         병목 계층 태그 (①재료~⑨자본 중) — layer_bottleneck_map 갱신 대상.
#' @param evidence_refs L-code/보고서 경로 벡터.
#' @return (invisibly) 종료 기록 list. 콘솔에 사람용 요약 출력.
close_round <- function(round_id,
                        verdict_type,
                        mechanism_diagnosis,
                        next_probes,
                        consumer_surfaces = character(0),
                        frontier_update = NULL,
                        live_trigger = NULL,
                        layer = NULL,
                        evidence_refs = character(0),
                        baseline = NULL,
                        write_marker = TRUE) {
  # ── 계약 검증 (미충족 = stop, 종료 거부) ──────────────────────────────────
  if (missing(round_id) || !nzchar(paste(round_id, collapse = "")))
    stop("close_round: round_id 필수.")
  if (missing(verdict_type) || !(verdict_type %in% .CR_VERDICT_TYPES))
    stop(sprintf("close_round: verdict_type은 다음 중 하나 — %s. (종결어휘 '완결/종결/소진 판정' 대신 구조화 enum)",
                 paste(.CR_VERDICT_TYPES, collapse = ", ")))
  if (missing(mechanism_diagnosis) || nchar(gsub("\\s", "", paste(mechanism_diagnosis, collapse = ""))) < 20)
    stop("close_round: mechanism_diagnosis ≥20자 필수 — 왜 이 결과인지 기전 진단 (연속성 3호).")
  np <- Filter(nzchar, as.character(next_probes))
  if (length(np) < 2)
    stop("close_round: next_probes ≥2 필수 — 기전 진단에서 다음 가설 2개 이상 도출 (연속성 3호). ",
         "이것이 원천차단의 핵심: negative 보고는 next_probe 없이는 완성되지 않는다.")
  cs <- Filter(nzchar, as.character(consumer_surfaces))
  has_frontier <- !is.null(frontier_update) && nzchar(paste(frontier_update, collapse = ""))
  if (length(cs) == 0 && !has_frontier)
    stop("close_round: consumer_surfaces 또는 frontier_update 최소 1 필수 — 소비처 전개/frontier 등재 (연속성 4호). ",
         "라운드가 능력을 확립하면 소비면 7종을 순회하라: 팩터랭킹/유니버스/오버레이/위험/monitoring/선별라벨/타모드.")
  lt <- if (is.null(live_trigger)) character(0) else Filter(nzchar, as.character(live_trigger))
  if (verdict_type %in% .CR_NEGATIVE_TYPES && length(lt) == 0)
    stop("close_round: negative 판정(", verdict_type, ")은 live_trigger(부활 조건) 필수 — ",
         "negative는 영구 판결이 아니다 (INV-7). 경로-scoped 재도전 신호를 명시하라 ",
         "(예: 스프레드 재확대 / 레짐 반전 / 비-return 데이터원 등재).")

  # ── 제약 방화벽 재사용 (있으면) — 제약 귀속/완화-레버 색출 ───────────────
  fw_note <- NULL
  fw_path <- file.path(.cr_root(), "02_Infrastructure", "axiom", "constraint_firewall.R")
  if (file.exists(fw_path)) {
    fw_note <- tryCatch({
      # 가벼운 backstop 힌트만 — semantic 판정은 호출 LLM(Q-Lead)이 이미 수행
      blob <- paste(c(mechanism_diagnosis, np, lt), collapse = " ")
      if (grepl("종목수.*(때문|탓)|공매도.*(허용|되면)|유동성.*(낮추|완화)|>\\s*25종|short 허용",
                blob))
        "⚠ 방화벽 경고: 서술에 제약-귀속/완화-레버 의심 표현 — envelope-상대로 재확인 (INV-7 firewall)."
      else NULL
    }, error = function(e) NULL)
  }

  # ── baseline 선언 (2026-08-10 신설, FQ-127 F1) ────────────────────────────
  #  왜: 비교·개선 주장("+0.85 개선", "ΔIR +0.17")은 **base 를 명시하지 않으면 해석 불가**다.
  #      2026-08-09 FQ-170 이 순열 통제 4/4 로 확립: **Δ 의 부호 자체가 base 에 조건부**이며,
  #      같은 규칙이 base 에 따라 +0.845 / +0.264 / **-0.293** 로 갈린다.
  #  ★설계: **탐지하지 않고 선언받는다.** 본문에서 '개선 주장' 을 정규식으로 찾는 방식은
  #      2026-08-10 FQ-127 C1 에서 실패했다 — 표본 5/5 오분류(어휘가 한/영 혼재:
  #      인컴번트·book IR·plain·EW→ERC / 반대로 `+5.22` 는 개선 패턴에 안 걸림 = 양방향 오류).
  #      ⇒ 사후 텍스트 마이닝은 원리적으로 못 고친다. **발행 시점에 필드로 받는다.**
  #  ★비파괴: 인자는 선택이고 미지정 시 stop 하지 않는다(기존 호출부 전부 그대로 동작).
  #      대신 `baseline_declared = FALSE` 를 기록해 **감사가 구조적 질문이 되게** 한다
  #      ("본문에 base 가 적혔나"(불가) → "필드가 선언됐나"(가능)).
  bl <- if (is.null(baseline)) character(0) else Filter(nzchar, as.character(baseline))
  bl_declared <- length(bl) > 0L
  if (!bl_declared)
    message("[close_round] baseline 미선언 — 비교·개선 주장을 포함한 라운드면 ",
            "`baseline=` 로 기준선을 밝힐 것(예: \"PG2 score_eff\", \"무밴드 top-25\"). ",
            "Δ 의 부호는 base 에 조건부다(FQ-170 순열 통제 4/4).")

  # ── frontier_update 선언↔실기록 대조 (2026-08-16 P0#3, L1 — FQ-167/168 계보) ──
  #   왜: frontier_update 는 서술 문자열일 뿐 이 함수는 큐를 쓰지 않는다 — 병렬 세션
  #   충돌로 등재가 조용히 생략되면 close_round 서술이 거짓이 된다(2026-08-09 실사고,
  #   큐 consume_rule ③ "선언에서 파생 금지"의 근원). 발행 시점에 서술이 언급한 FQ-id 의
  #   큐 실재를 대조해 구조 필드로 기록한다. 경고 레벨 — 비차단(판정 자체는 막지 않는다).
  fq_ids <- character(0); fq_missing <- character(0); fq_verified <- NA
  if (has_frontier) {
    blob <- paste(frontier_update, collapse = " ")
    # perl=TRUE — TRE 색인 위 regmatches 금칙(r-portability ⑥) 회피
    m <- gregexpr("FQ-[0-9]{1,4}", blob, perl = TRUE)
    fq_ids <- unique(unlist(regmatches(blob, m)))
    fq_ids <- fq_ids[nzchar(fq_ids)]
    if (length(fq_ids)) {
      qp <- file.path(.cr_root(), "06_Registry", "alpha_frontier_queue.json")
      if (file.exists(qp)) {
        qtxt <- paste(readLines(qp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        pres <- vapply(fq_ids, function(id)
          grepl(paste0("\"", id, "\""), qtxt, fixed = TRUE), logical(1))
        fq_missing <- fq_ids[!pres]
        fq_verified <- length(fq_missing) == 0L
        if (!fq_verified)
          message("[close_round] ⚠ frontier 선언↔실기록 불일치 — 큐에 없는 FQ-id: ",
                  paste(fq_missing, collapse = ", "),
                  " (FQ-167/168 계보: frontier_update 는 실제 기록 결과에서 파생시킬 것. ",
                  "큐 기록 후 재확인 — 비차단 경고)")
      } else {
        message("[close_round] frontier 대조 불가 — alpha_frontier_queue.json 부재")
      }
    }
    # FQ-id 미언급 서술(예: '항목 status 갱신')은 대조 불가(NA) — 억지 판정 금지
  }

  # ── 종료 기록 발행 ────────────────────────────────────────────────────────
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  rec <- list(
    schema = "round_closure_v1",
    round_id = round_id,
    verdict_type = verdict_type,
    mechanism_diagnosis = mechanism_diagnosis,
    next_probes = np,
    consumer_surfaces = cs,
    frontier_update = if (has_frontier) frontier_update else NULL,
    # P0#3 (2026-08-16): 선언↔실기록 대조 결과 — TRUE=전 id 큐 실재 / FALSE=부재 id 있음 /
    #   NA=대조 불가(FQ-id 미언급 또는 큐 파일 부재). 감사가 구조적 질문이 되게 한다.
    frontier_ids = if (length(fq_ids)) fq_ids else NULL,
    frontier_update_verified = fq_verified,
    frontier_ids_missing = if (length(fq_missing)) fq_missing else NULL,
    live_trigger = lt,
    layer = layer,
    evidence_refs = as.character(evidence_refs),
    baseline = bl,                    # 선언된 기준선 (없으면 길이 0)
    baseline_declared = bl_declared,  # ★감사용 구조 필드 — 텍스트 판독 불요
    firewall_note = fw_note,
    closed_at = now
  )

  if (isTRUE(write_marker)) {
    cache_dir <- file.path(.cr_root(), ".cache")
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    marker <- file.path(cache_dir, "last_round_closure.json")
    writeLines(jsonlite::toJSON(rec, auto_unbox = TRUE, pretty = TRUE), marker, useBytes = TRUE)
    # 감사 원장 append (jsonl) — 종료 이력 정직 전수
    ledger <- file.path(cache_dir, "round_closures.jsonl")
    cat(jsonlite::toJSON(rec, auto_unbox = TRUE), "\n", file = ledger, append = TRUE, sep = "")
  }

  # ── 사람용 요약 (Q-Lead가 이걸로 보고 — 구조화 필드 = 서술의 원천) ────────
  probe_lines <- sprintf("  %s %s", intToUtf8(9312 + seq_along(np) - 1, multiple = TRUE), np)
  cons_line <- if (length(cs)) paste(cs, collapse = " · ") else "(frontier only)"
  lt_line <- if (length(lt)) paste(lt, collapse = " · ") else "(positive — 부활조건 불요)"
  summary <- paste0(
    sprintf("── 라운드 종료: %s [%s] ──\n", round_id, verdict_type),
    sprintf("기전: %s\n", mechanism_diagnosis),
    "next_probe:\n", paste(probe_lines, collapse = "\n"), "\n",
    sprintf("소비면: %s\n", cons_line),
    if (has_frontier) sprintf("frontier: %s\n", frontier_update) else "",
    if (has_frontier && length(fq_ids)) sprintf("frontier 대조: %s\n",
      if (isTRUE(fq_verified)) sprintf("큐 실재 확인 (%s)", paste(fq_ids, collapse = ", "))
      else if (identical(fq_verified, FALSE))
        sprintf("★불일치 — 큐 부재 id: %s (선언≠실기록, 비차단 경고)",
                paste(fq_missing, collapse = ", "))
      else "대조 불가 (큐 파일 부재)") else "",
    sprintf("부활 조건: %s\n", lt_line),
    if (!is.null(layer)) sprintf("병목 계층: %s\n", layer) else "",
    if (!is.null(fw_note)) paste0(fw_note, "\n") else "",
    ## ★2026-08-10 정정: 이 줄은 `write_marker` 와 **무관하게** 항상 "마커 발행" 을 주장했다.
    ##   `write_marker=FALSE`(검사·드라이런)에서도 "Stop 게이트 자동 통과" 로 찍혀,
    ##   **일어나지 않은 일을 사실로 보고**했다 — 오늘 반복된 '빈 결과 = 합격' 계통.
    ##   (FQ-127 F1 검사를 쓰다가 그 출력에서 발견.)
    if (isTRUE(write_marker))
      sprintf("마커 발행 → Stop 게이트 자동 통과 (%s)\n", now)
    else
      sprintf("★마커 **미발행**(write_marker=FALSE) — Stop 게이트 통과 아님 (%s)\n", now),
    if (!bl_declared) "★baseline 미선언 — 비교·개선 주장이 있으면 `baseline=` 을 채울 것\n" else
      sprintf("기준선: %s\n", paste(bl, collapse = " · "))
  )
  cat(summary)
  invisible(rec)
}

# 자기 검증(직접 실행 시): source 후 sys.frame 없으면 데모 실행 안 함.
if (identical(environment(), globalenv()) && !interactive() &&
    nzchar(Sys.getenv("CLOSE_ROUND_SELFTEST", ""))) {
  cat("[close_round selftest]\n")
  ok <- tryCatch({
    close_round(
      round_id = "SELFTEST_R0",
      verdict_type = "config_scoped_negative",
      mechanism_diagnosis = "셀프테스트 — cap-w 전이 벽으로 이 config 미달(기전 진단 데모).",
      next_probes = c("비-return 원천에 동일 선별 적용", "EW-basis cap-tier 재분류"),
      consumer_surfaces = c("OVERLAY_CANDIDATE feature 보존"),
      live_trigger = c("비-return 방어 데이터원 등재 시"),
      layer = "①재료"
    )
    TRUE
  }, error = function(e) { cat("FAIL:", conditionMessage(e), "\n"); FALSE })
  # 계약 위반 케이스: next_probes 1개 → stop 기대
  viol <- tryCatch({
    close_round("SELFTEST_R1", "config_scoped_negative",
                "기전 진단 20자 이상 채운 데모 문장입니다.",
                next_probes = c("하나뿐"), consumer_surfaces = "x",
                live_trigger = "y", write_marker = FALSE)
    FALSE  # stop 안 나면 실패
  }, error = function(e) TRUE)
  cat(sprintf("[selftest] valid_close=%s  contract_reject=%s\n", ok, viol))
}
