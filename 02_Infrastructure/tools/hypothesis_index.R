# =====================================================================
# hypothesis_index.R — 가설 중복실험 방지 인덱스 (빌더 + 조회)
# =====================================================================
# 감사 AS-03 대응: 687회+ 실험의 "이미 시도됨" 판정이 LLM 메모리에 의존하던
# 구조를 파일 인덱스로 대체. alpha-search Step 0 이전 조회 의무
# (.claude/skills/alpha-search/SKILL.md 참조).
#
# 원천 5계층 (2026-07-04 엔진 재설계 — distilled 추가 / 2026-07-10 M6 — in-flight WT 추가):
#   (a) stage_artifacts/alpha_search/*/strategy_manifest.json  (완주 run)
#       + strategy_manifest 부재 시 hurdle_result.json fallback (초기 run)
#       + 둘 다 없는 빈 디렉터리는 중단 run으로 스킵 (사유 기록)
#   (b) .cache/lcode_corpus.json                               (L-code 594건+)
#       + 보충 스캔 (2026-07-13 task#54): corpus mtime보다 새
#         stage_artifacts/l_code/*/l_code_*.json (+ flat l_code_*.json)을 직접 파싱해
#         보충. dedup 키 = l_code (corpus 항목 우선). 파싱 실패 파일은 skip+카운트.
#         배경: corpus 정체 시 중복방지 게이트가 실명하던 07-13 실사고(이틀) 재발 방지 —
#         harvester 미가동/우회 상태에서도 인덱스가 원본 계층에서 자립.
#   (c) 06_Registry/module_catalog.json                        (등록 모듈 265건+)
#   (d) 06_Registry/distilled_knowledge.json                   (②Distilled 클러스터 통합 지식)
#       verdict = DISTILLED_NEG / DISTILLED_COND / DISTILLED_POS.
#       negative는 lookup 결과에 retry_policy를 지도-프레임(탐색됨 → 프론티어(미탐색) →
#       부활 트리거 → 봉투 안 차별점 명시 시 진행 가능; INV-7 provisional = 불변 기각 아님)으로
#       표출. frontier/live_trigger 필드 있으면 표출, 없으면 retry_condition/expiry 폴백.
#       반복기록 N건보다 대표 1건 + 회차 이력이 가설 시점 pull 대조에 정밀.
#   (e) qepm/mailbox/worktask/*/  진행중(in-flight) WT             (2026-07-10 M6, F6 수리)
#       request.json(hypothesis_title/theme) + status.json(current_phase) 소비.
#       terminal phase(TERMINAT/ABORT/ARCHIV/REJECT/KILL/FAIL/NEGATIVE/DEFERRED/
#       ADMIT/GOVERNOR_DONE/^COMPLETED$)는 스킵 — 완주분은 (a)~(d)가 커버.
#       verdict = IN_PROGRESS (마지막 파일활동 <= HI_INFLIGHT_FRESH_DAYS=14일)
#               / INFLIGHT_STALE (non-terminal이나 14일+ 무활동 — 중단 추정, 재개 전 mailbox 확인).
#       중복 키 규칙: strategy_id = WT task_id. 원천 (e)는 마지막에 합류하므로 동일 id가
#       (a)~(d)에 이미 있으면 그쪽이 base — .hi_merge가 IN_PROGRESS로 기존 verdict를
#       덮지 않음(완주 산출물 우선). 완주 후 재빌드 시 (e) 엔트리는 terminal 스킵으로 자연 소멸.
#
# 산출: 06_Registry/hypothesis_index.json
#
# ---------------------------------------------------------------------
# hypothesis_signature 정규화 규칙 (문서화 — 변경 시 이 헤더 갱신):
#   signature = "<family>|<signal_group>|<universe>|<structure>"  (전부 소문자)
#
#   family:
#     - lcode 원천은 corpus의 family 필드를 그대로 사용 (authoritative).
#     - manifest/hurdle/module 원천은 title+idea 텍스트에 대해
#       FAMILY_PATTERNS를 "우선순위 순서대로" 매칭, 첫 매치 = family.
#       무매치 = "other".
#   signal_group:
#     - title+idea 텍스트에 SIGNAL_PATTERNS를 우선순위 순서로 매칭,
#       매치된 토큰 최대 3개를 "+"로 연결 (예: "residual_momentum+lowvol").
#     - 무매치 = title의 slug (소문자, 비영숫자→"_", 40자 절단).
#   universe:
#     - manifest: execution$universe 소문자 (예: "all", "k200_kq150").
#     - 그 외 원천: "unknown" (원천에 유니버스 필드 부재).
#   structure:
#     - manifest: paste0(weight_method, n_holdings) (예: "equal20", "ivol25").
#     - hurdle fallback: "unknown".
#     - lcode: construction_type 필드 (예: "single_factor_long_only", "chain").
#     - module: origin_mode (예: "alpha_search", "ml", "dpl").
#
#   ※ signature는 결정적(deterministic)이며 동일 입력에 항상 동일 값.
#   ※ 동일 strategy_id가 복수 원천에 등장하면 1개 엔트리로 병합
#     (우선순위 manifest > hurdle > lcode > module; source_paths 누적,
#      결측 필드만 후순위 원천으로 보충).
#
# verdict 정규화:
#   SCREEN_TIER  : manifest verdict$screening$screen_pass == TRUE
#   PASS         : grade A/B 또는 hurdle_pass TRUE
#   FAIL         : grade F 또는 hard_fail TRUE
#   KILL         : lcode tags에 VALIDATED_HARD_FAIL 포함
#   MARGINAL     : grade C
#   REGISTERED   : module_catalog 단독 (성과판정 필드 부재)
#   IN_PROGRESS  : in-flight WT (원천 e, 14일 내 활동) — 병렬 세션 중복실행 방지 마커
#   INFLIGHT_STALE: in-flight WT non-terminal + 14일+ 무활동 (중단 추정)
#   <원문 grade> : 위 어디에도 안 걸리는 비표준 grade는 원문 보존
#
# ---------------------------------------------------------------------
# CLI 사용례:
#   cd /c/Users/99922/OneDrive/Quant_Module_Moltbot
#   Rscript 02_Infrastructure/tools/hypothesis_index.R build
#   Rscript 02_Infrastructure/tools/hypothesis_index.R lookup residual momentum
#   Rscript 02_Infrastructure/tools/hypothesis_index.R lookup shareholder
#
# R 세션 사용례:
#   source("02_Infrastructure/tools/hypothesis_index.R")
#   idx <- build_hypothesis_index()                 # 재빌드 + 저장
#   hits <- lookup_hypothesis("residual momentum")  # 부분매치 조회
#   hits <- lookup_hypothesis(c("value", "k200"))   # AND 다중 키워드
# =====================================================================

suppressPackageStartupMessages(library(jsonlite))

QM_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
HI_INDEX_PATH <- file.path(QM_ROOT, "06_Registry/hypothesis_index.json")

# --------------------------------------------------------------------
# 정규화 사전 (우선순위 = 리스트 순서. 첫 매치 승리)
# --------------------------------------------------------------------
SIGNAL_PATTERNS <- list(
  residual_momentum = "residual mom|잔차 ?모멘텀|특이 ?모멘텀|residmom",
  earnings_revision = "revision|리비전|추정치 변화|esbr|escr",
  sue               = "\\bsue\\b|earnings surprise|어닝 ?서프라이즈|이익 ?서프라이즈",
  accruals          = "accrual|발생액",
  fscore            = "f[- ]?score|piotroski",
  qmj               = "\\bqmj\\b|quality minus junk",
  shareholder_yield = "shareholder yield|주주환원|자사주|buyback",
  dividend          = "dividend|배당",
  momentum          = "momentum|모멘텀|\\b12-1\\b|mom ?_?[0-9]|\\bmom\\b|\\btrend\\b|추세",
  reversal          = "reversal|리버설|반전|contrarian|역추세|loser",
  lottery           = "lottery|복권|\\bmax\\b effect|skewness",
  low_volatility    = "low[- ]?vol|저변동|min[- ]?vol|minimum variance|저베타",
  beta              = "\\bbab\\b|betting against beta|\\bbeta\\b|베타",
  volatility        = "volatility|변동성|\\bvol\\b",
  profitability     = "profitab|\\broe\\b|\\broa\\b|gross profit|수익성|마진",
  value             = "\\bvalue\\b|밸류|\\bpbr\\b|\\bper\\b|\\bep\\b|book[- ]?to[- ]?market|\\bbm\\b|저평가|가치",
  size              = "\\bsize\\b|소형주|small[- ]?cap",
  liquidity         = "liquidity|유동성|amihud|illiquid",
  flow              = "\\bflow\\b|수급|외국인|기관 ?매수|short interest|공매도|insider|내부자",
  consensus         = "consensus|컨센서스|analyst|애널리스트|target price|목표주가",
  crash_protection  = "crash|크래시|drawdown|낙폭|\\bdd[- ]?brake\\b|tail",
  regime_overlay    = "regime|국면|overlay|오버레이|timing|타이밍|vol[- ]?target|절대모멘텀",
  ml                = "\\bml\\b|machine learning|머신러닝|딥러닝|xgboost|lightgbm|\\bhgb\\b|neural|autoencoder|ipca|\\bsdf\\b|random forest|ensemble|앙상블|강화학습",
  seasonality       = "seasonal|계절성|january|월별 효과",
  quality           = "quality|퀄리티|품질"
)

FAMILY_PATTERNS <- list(
  ml_complexity         = "\\bml\\b|machine learning|머신러닝|딥러닝|xgboost|lightgbm|\\bhgb\\b|neural|autoencoder|ipca|\\bsdf\\b|random forest|ensemble|앙상블|강화학습|\\bdpl\\b",
  quality_earnings      = "\\bsue\\b|earnings|어닝|이익|실적|revision|리비전|accrual|발생액|f[- ]?score|piotroski",
  quality_profitability = "profitab|\\broe\\b|\\broa\\b|gross profit|수익성|\\bqmj\\b|quality|퀄리티",
  momentum              = "momentum|모멘텀|\\b12-1\\b|mom ?_?[0-9]|\\bmom\\b|\\btrend\\b|추세",
  behavioral            = "reversal|리버설|반전|contrarian|역추세|lottery|복권|loser|sentiment|심리",
  defense               = "low[- ]?vol|저변동|min[- ]?vol|\\bbab\\b|저베타|defensive|방어|downside|crash|크래시",
  value                 = "\\bvalue\\b|밸류|\\bpbr\\b|\\bper\\b|\\bep\\b|book[- ]?to[- ]?market|\\bbm\\b|저평가|가치|배당|dividend|주주환원|shareholder yield",
  consensus             = "consensus|컨센서스|analyst|애널리스트|목표주가",
  flow                  = "\\bflow\\b|수급|외국인|기관 ?매수|공매도|short interest|insider|내부자",
  overlay               = "regime|국면|overlay|오버레이|vol[- ]?target|절대모멘텀|timing|타이밍",
  size                  = "\\bsize\\b|소형주|small[- ]?cap",
  liquidity             = "liquidity|유동성|amihud"
)

# --------------------------------------------------------------------
# 정규화 헬퍼
# --------------------------------------------------------------------
.hi_lc <- function(x) tolower(paste(x, collapse = " "))

# ★P0#1 배열-안전 문자열화: JSON 필드가 list / character(N) / NULL 어느 형태든
#   단일 문자열로 정규화. 빈 요소·NA 제거 후 "; "로 결합. 빈/NULL → "".
#   이 함수를 거치면 후속 nzchar()가 항상 length-1 논리값을 반환 → if() 안전.
.hi_join <- function(x, sep = "; ") {
  if (is.null(x)) return("")
  v <- unlist(x, use.names = FALSE)
  if (length(v) == 0) return("")
  v <- as.character(v)
  v <- v[!is.na(v) & nzchar(trimws(v))]
  if (length(v) == 0) return("")
  paste(v, collapse = sep)
}

.hi_slug <- function(x) {
  s <- tolower(gsub("[^A-Za-z0-9가-힣]+", "_", x))
  s <- gsub("^_+|_+$", "", s)
  substr(s, 1, 40)
}

.hi_match_first <- function(text, patterns) {
  for (nm in names(patterns)) {
    if (grepl(patterns[[nm]], text, ignore.case = TRUE, perl = TRUE)) return(nm)
  }
  NA_character_
}

.hi_match_multi <- function(text, patterns, max_n = 3L) {
  hits <- character(0)
  for (nm in names(patterns)) {
    if (grepl(patterns[[nm]], text, ignore.case = TRUE, perl = TRUE)) hits <- c(hits, nm)
    if (length(hits) >= max_n) break
  }
  hits
}

.hi_infer_family <- function(text) {
  fam <- .hi_match_first(text, FAMILY_PATTERNS)
  if (is.na(fam)) "other" else fam
}

.hi_infer_signal_group <- function(text, title) {
  hits <- .hi_match_multi(text, SIGNAL_PATTERNS)
  if (length(hits) > 0) paste(hits, collapse = "+") else .hi_slug(title)
}

.hi_signature <- function(family, signal_group, universe, structure) {
  norm <- function(x) {
    x <- tolower(trimws(as.character(x %||% "unknown")))
    if (!nzchar(x)) "unknown" else x
  }
  paste(norm(family), norm(signal_group), norm(universe), norm(structure), sep = "|")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.hi_num <- function(x) {
  v <- suppressWarnings(as.numeric(x %||% NA_real_))
  if (length(v) != 1 || is.na(v)) NULL else v
}

# verdict 정규화 (헤더 규칙 참조)
.hi_verdict <- function(grade = NULL, hurdle_pass = NULL, hard_fail = NULL,
                        screen_pass = NULL, tags = NULL) {
  tags_txt <- .hi_lc(unlist(tags))
  if (grepl("validated_hard_fail", tags_txt)) return("KILL")
  if (isTRUE(screen_pass)) return("SCREEN_TIER")
  g <- toupper(trimws(as.character(grade %||% "")))
  if (g %in% c("A", "B", "A_DEF", "A_CONDITIONAL", "A_CONDITIONAL_REAFFIRMED")) return("PASS")
  if (isTRUE(hurdle_pass)) return("PASS")
  if (g %in% c("F", "REJECT") || isTRUE(hard_fail)) return("FAIL")
  if (g == "C") return("MARGINAL")
  if (nzchar(g)) return(g)   # 비표준 grade 원문 보존
  "UNKNOWN"
}

# --------------------------------------------------------------------
# 원천별 파서 → 공통 엔트리 list(
#   strategy_id, hypothesis_signature, title, verdict, grade,
#   key_metrics(named list, 있는 것만), source_paths(chr vec),
#   source_types(chr vec), date)
# --------------------------------------------------------------------
.hi_parse_manifest <- function(path) {
  m <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(m)) return(NULL)
  title <- m$strategy_name %||% basename(dirname(path))
  text  <- .hi_lc(c(title, m$strategy_idea %||% ""))
  ex    <- m$execution %||% list()
  v     <- m$verdict %||% list()
  scr   <- v$screening %||% list()
  met   <- m$metrics %||% list()
  km <- list()
  km$sharpe <- .hi_num(met$Sharpe); km$cagr <- .hi_num(met$CAGR)
  km$mdd <- .hi_num(met$MDD); km$ir <- .hi_num(met$IR)
  km$calmar <- .hi_num(met$Calmar); km$score <- .hi_num(v$score)
  km <- km[!vapply(km, is.null, logical(1))]
  structure_tag <- paste0(ex$weight_method %||% "unknown", ex$n_holdings %||% "")
  list(
    strategy_id = m$strategy_id %||% paste0("AS_DIR_", basename(dirname(path))),
    hypothesis_signature = .hi_signature(
      .hi_infer_family(text), .hi_infer_signal_group(text, title),
      ex$universe %||% "unknown", structure_tag),
    title = title,
    verdict = .hi_verdict(v$grade, v$hurdle_pass, v$hard_fail, scr$screen_pass),
    grade = as.character(v$grade %||% NA_character_),
    key_metrics = km,
    source_paths = sub(paste0("^", QM_ROOT, "/"), "", gsub("\\\\", "/", path)),
    source_types = "alpha_search_manifest",
    date = substr(as.character(m$created_at %||% ""), 1, 10)
  )
}

.hi_parse_hurdle <- function(path) {
  h <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(h)) return(NULL)
  title <- h$strategy %||% basename(dirname(path))
  text  <- .hi_lc(title)
  km <- list()
  sb <- h$score_breakdown %||% list()
  km$sharpe <- .hi_num(sb$sharpe$value); km$cagr <- .hi_num(sb$cagr$value)
  km$mdd <- .hi_num(sb$mdd$value); km$ir <- .hi_num(sb$ir$value)
  km$calmar <- .hi_num(sb$calmar$value); km$score <- .hi_num(h$total_score)
  km <- km[!vapply(km, is.null, logical(1))]
  # hurdle_result.json은 strategy_id 필드 부재 → run_alpha_search 관례
  # (strategy_id = "STR_AS_" + 디렉터리명)로 복원해 module_catalog의 동일
  # 실험 엔트리와 병합되게 한다 (인덱스 키 용도 — 실제 등록 여부와 무관).
  list(
    strategy_id = paste0("STR_AS_", basename(dirname(path))),
    hypothesis_signature = .hi_signature(
      .hi_infer_family(text), .hi_infer_signal_group(text, title),
      "unknown", "unknown"),
    title = title,
    verdict = .hi_verdict(h$grade, h$pass, h$hard_fail),
    grade = as.character(h$grade %||% NA_character_),
    key_metrics = km,
    source_paths = sub(paste0("^", QM_ROOT, "/"), "", gsub("\\\\", "/", path)),
    source_types = "alpha_search_hurdle",
    date = substr(as.character(h$timestamp %||% ""), 1, 10)
  )
}

.hi_parse_lcode <- function(e) {
  title <- e$strategy_id %||% e$l_code
  text  <- .hi_lc(c(title, substr(e$lesson_text %||% "", 1, 400)))
  km <- list()
  km$portfolio_alpha_t <- .hi_num(e$portfolio_alpha_t)
  km$oos_retention <- .hi_num(e$oos_retention)
  km <- km[!vapply(km, is.null, logical(1))]
  fam <- e$family %||% NA_character_
  if (is.null(fam) || is.na(fam) || fam %in% c("unknown", "")) fam <- .hi_infer_family(text)
  list(
    strategy_id = e$strategy_id %||% e$l_code,
    hypothesis_signature = .hi_signature(
      fam, .hi_infer_signal_group(text, title),
      "unknown", e$construction_type %||% "unknown"),
    title = paste0(e$l_code %||% "", ": ", title),
    verdict = .hi_verdict(e$grade, tags = e$tags),
    grade = as.character(e$grade %||% NA_character_),
    key_metrics = km,
    source_paths = as.character(e$source_file %||% ".cache/lcode_corpus.json"),
    source_types = "lcode_corpus",
    date = substr(as.character(e$mtime %||% ""), 1, 10)
  )
}

# (task#54-1 2026-07-13) 원본 L-code json → corpus-호환 엔트리 어댑터 (보충 스캔 전용).
#   harvester가 corpus에 넣어주는 파생필드 중 .hi_parse_lcode가 소비하는 것만 보충:
#   source_file(상대경로) + mtime(파일 mtime). family는 원본에 없으면 .hi_parse_lcode의
#   .hi_infer_family 폴백이 처리(기존 경로 재사용 — 별도 추론 로직 중복 구현 금지).
.hi_raw_lcode_entry <- function(path, root = QM_ROOT) {
  d <- fromJSON(path, simplifyVector = FALSE)   # 실패 시 호출측 tryCatch가 skip+카운트
  lcode <- .hi_join(d$l_code)
  if (!nzchar(lcode)) {
    # harvester와 동일 관례: 파일명에서 L-\d+ 복원 시도
    m <- regmatches(basename(path), regexpr("L-[0-9]+", basename(path)))
    lcode <- if (length(m)) m else ""
  }
  if (!nzchar(lcode)) stop("l_code 필드 부재 + 파일명 복원 실패: ", basename(path))
  d$l_code <- lcode
  d$source_file <- sub(paste0("^", root, "/"), "", gsub("\\\\", "/", path))
  d$mtime <- format(file.info(path)$mtime, "%Y-%m-%dT%H:%M:%S")
  d
}

.hi_parse_distilled <- function(e) {
  stmt  <- e$statement_refined %||% e$statement_draft %||% ""
  refined <- !is.null(e$statement_refined) && nzchar(e$statement_refined %||% "")
  title <- paste0(e$dist_id %||% "", ": ", if (refined) stmt else paste0("[초안] ", stmt))
  text  <- .hi_lc(c(e$family %||% "", stmt, paste(unlist(e$supporting_l_codes), collapse = " ")))
  pol   <- e$polarity %||% "unknown"
  verdict <- switch(pol, negative = "DISTILLED_NEG", conditional = "DISTILLED_COND",
                    positive = "DISTILLED_POS", "DISTILLED")
  # (E+F 2026-07-04 실패지식 프레이밍 전환) negative lookup 반환을 "재시도 금지"가 아닌
  #   지도-프레임(탐색됨 → 프론티어 → 부활 트리거)으로 전환. DISTILLED_NEG verdict는 유지하되
  #   문안은 "봉투 안 차별점 명시 시 진행 가능"을 명시 (INV-7 provisional = 불변 기각 아님).
  #   frontier/live_trigger 필드가 인덱스에 있으면 표출, 없으면 retry_condition을 프론티어로 폴백.
  #
  # ★P0#1 배열-안전 (2026-07-04 감사): frontier/live_trigger는 JSON 배열(list/character N)일
  #   수 있다. 구코드 `e$frontier %||% ...` + `if(nzchar(frontier))`는 배열 유입 시
  #   nzchar()가 길이-N 논리벡터를 반환 → if()가 "condition has length > 1"로 예외 →
  #   상위 tryCatch가 silent drop → 성실히 채운(frontier 배열이 긴) 엔트리일수록 드롭되는
  #   역설. 해결: unlist+collapse로 스칼라 문자열화한 뒤 nzchar()로 판정. if()에 벡터 유입 차단.
  #   `.hi_join()`은 length 0/1/N 모두 단일 문자열로 정규화(빈/NULL → "").
  retry <- if (identical(pol, "negative")) {
    fr_str   <- .hi_join(e$frontier);     if (!nzchar(fr_str))   fr_str   <- .hi_join(e$retry_condition)
    trig_str <- .hi_join(e$live_trigger); if (!nzchar(trig_str)) trig_str <- .hi_join(e$expiry)
    parts <- "탐색됨(경로 F 기록)."
    if (nzchar(fr_str))   parts <- paste0(parts, sprintf(" 프론티어(미탐색): %s", fr_str))
    if (nzchar(trig_str)) parts <- paste0(parts, sprintf(" 부활 트리거: %s", trig_str))
    paste0(parts, " 봉투 안 차별점 명시 시 진행 가능(INV-7 provisional — 불변 기각 아님).")
  } else NULL
  fam <- e$family %||% NA_character_
  if (is.null(fam) || is.na(fam) || fam %in% c("unknown", "")) fam <- .hi_infer_family(text)
  list(
    strategy_id = e$dist_id %||% paste0("DIST_", substr(stmt, 1, 20)),
    hypothesis_signature = .hi_signature(
      fam, .hi_infer_signal_group(text, stmt), "unknown", "distilled"),
    title = title,
    verdict = verdict,
    grade = NA_character_,
    key_metrics = list(),
    retry_policy = retry,
    distilled_status = e$status %||% "pending_5axis",
    source_paths = "06_Registry/distilled_knowledge.json",
    source_types = "distilled_knowledge",
    date = substr(as.character(e$refined_at %||% e$created_at %||% ""), 1, 10)
  )
}

# ★최소필드 폴백 엔트리 (P0#1 silent-drop 방지): .hi_parse_distilled가 예외로 실패해도
#   완전 드롭하지 않고 최소한의 식별 정보로 인덱스에 남긴다. verdict는 polarity 기반 보존,
#   retry_policy에 파싱실패 사유를 명시해 consumer가 원본 재확인하도록 유도.
.hi_min_distilled_entry <- function(e, err_msg = "") {
  pol <- e$polarity %||% "unknown"
  verdict <- switch(pol, negative = "DISTILLED_NEG", conditional = "DISTILLED_COND",
                    positive = "DISTILLED_POS", "DISTILLED")
  stmt <- .hi_join(e$statement_refined) ; if (!nzchar(stmt)) stmt <- .hi_join(e$statement_draft)
  did  <- e$dist_id %||% paste0("DIST_", substr(stmt, 1, 20))
  fam  <- e$family %||% "other"
  if (is.null(fam) || is.na(fam) || fam %in% c("unknown", "")) fam <- "other"
  list(
    strategy_id = did,
    hypothesis_signature = .hi_signature(fam, .hi_slug(stmt), "unknown", "distilled"),
    title = paste0(did, ": ", substr(stmt, 1, 60)),
    verdict = verdict,
    grade = NA_character_,
    key_metrics = list(),
    retry_policy = paste0("[파싱실패 — 원본 distilled_knowledge.json 확인 요망] ", err_msg),
    distilled_status = e$status %||% "pending_5axis",
    source_paths = "06_Registry/distilled_knowledge.json",
    source_types = "distilled_knowledge",
    date = substr(as.character(e$refined_at %||% e$created_at %||% ""), 1, 10)
  )
}

.hi_parse_module <- function(e) {
  meta  <- e$meta %||% list()
  idea  <- meta$strategy_idea %||% ""
  title <- if (nzchar(idea)) idea else e$strategy_id
  text  <- .hi_lc(c(e$strategy_id, idea))
  km <- list(); km$score <- .hi_num(meta$score)
  km <- km[!vapply(km, is.null, logical(1))]
  list(
    strategy_id = e$strategy_id,
    hypothesis_signature = .hi_signature(
      .hi_infer_family(text), .hi_infer_signal_group(text, title),
      "unknown", e$origin_mode %||% "unknown"),
    title = title,
    verdict = "REGISTERED",
    grade = as.character(e$grade %||% NA_character_),
    key_metrics = km,
    source_paths = "06_Registry/module_catalog.json",
    source_types = "module_catalog",
    date = substr(as.character(e$registered_at %||% ""), 1, 10)
  )
}

# --------------------------------------------------------------------
# (f) 논문 레인 파서 (2026-08-13 신설, 도훈 지시)
#
# ★경계: 논문 라우팅은 **가능성을 보는 단계**다. 각 에이전트가 후속 연구를 스스로 끌고 가는
#   단계가 아니라, 1차 리서치까지 하고 **여기 인덱스에 남겨** 각 리서치 모드(QEPM/alpha-search/
#   factor-rotation/RAMP)가 소비할 수 있게 올려두는 것이 종착이다.
#   그 전까지 method_registry 는 인덱스의 원천 6종 어디에도 없었다 — 등재된 어댑터가
#   **모드에게 보이지 않았다**. 큐를 아무리 드레인해도 소비면이 닫혀 있던 셈이다.
#
# 측정치는 **A/B 결과표와 자동 조인**한다(손으로 넣으면 다음 논문부터 또 수기가 된다).
#   scenario 열의 값 == method_id 규약을 이용한다.
# --------------------------------------------------------------------
HI_PAPER_AB_SOURCES <- c("06_Registry/book_carrier/h2_regime_overlay_ab.csv",
                         "06_Registry/book_carrier/h1b_sigma_ab_overlay.csv")

#' A/B 표들을 훑어 scenario→key_metrics 사전을 만든다. 없으면 빈 list.
.hi_paper_lane_measurements <- function(root) {
  out <- list()
  for (rel in HI_PAPER_AB_SOURCES) {
    p <- file.path(root, rel); if (!file.exists(p)) next
    t <- tryCatch(utils::read.csv(p, stringsAsFactors = FALSE), error = function(z) NULL)
    if (is.null(t) || !("scenario" %in% names(t)) || !("IR" %in% names(t))) next
    b <- suppressWarnings(as.numeric(t$IR[t$scenario %in% c("book_L5", "book", "baseline")]))
    base <- if (length(b) && is.finite(b[1])) b[1] else NA_real_
    for (i in seq_len(nrow(t))) {
      km <- list()
      ir <- suppressWarnings(as.numeric(t$IR[i]))
      if (is.finite(ir)) km$ir <- ir
      if (is.finite(ir) && is.finite(base)) km$delta_ir <- ir - base
      for (cn in c("avg_exposure", "abs_MDD", "abs_SR")) {
        if (cn %in% names(t)) { v <- suppressWarnings(as.numeric(t[[cn]][i])); if (is.finite(v)) km[[cn]] <- v }
      }
      km$ab_source <- basename(rel)
      # ★교란 경고를 수치와 **같은 자리에** 붙인다 — 따로 조회해야 알면 dead 배관이다.
      #   2026-08-13 실측: regime overlay A/B 21 시나리오에서 cor(avg_exposure, ΔIR)=0.926,
      #   R² 0.858. 즉 ΔIR 의 86%가 '얼마나 태웠나'로 설명된다 — 타이밍 실력 지표가 아니다.
      #   노출-정합 비교(잔차) 없이 ΔIR 순위를 실력으로 읽지 말 것.
      if (grepl("regime_overlay", rel, fixed = TRUE))
        km$delta_ir_caveat <- "exposure_confounded_R2_0.858_use_exposure_matched_residual"
      out[[as.character(t$scenario[i])]] <- km
    }
  }
  out
}

.hi_parse_paper_lane <- function(e, meas = list()) {
  mid <- e$method_id %||% NA_character_
  if (is.na(mid) || !nzchar(mid)) return(NULL)
  kind <- e$adapter_kind %||% "unknown"
  ttl  <- e$paper_title %||% mid
  text <- .hi_lc(c(mid, ttl, e$mechanism %||% "", e$kr_mapping %||% ""))
  km <- meas[[mid]] %||% list()
  km$adapter_kind <- kind
  km$selection_type <- e$selection_type %||% "unknown"
  # verdict — 자본 판정이 아니라 **소비 가능성** 상태다(이 레인의 역할 자체가 가능성 판별).
  verdict <- if (identical(e$verdict %||% "", "registration_failed")) "FAIL"
             else if (length(meas[[mid]] %||% list())) "PAPER_LANE_MEASURED"
             else "PAPER_LANE_AVAILABLE"
  list(
    strategy_id = paste0("PL_", mid),
    hypothesis_signature = .hi_signature(
      .hi_infer_family(text), .hi_infer_signal_group(text, ttl),
      "kospi200_kosdaq150_intersection", paste0("paper_", kind)),
    title = sprintf("%s [%s/%s] %s", mid, kind, e$route %||% "?", ttl),
    verdict = verdict,
    grade = "",
    key_metrics = km[!vapply(km, is.null, logical(1))],
    source_paths = c(e$adapter %||% NA_character_, "06_Registry/method_registry.json",
                     e$paper_id %||% NA_character_),
    source_types = "paper_lane",
    date = substr(as.character(e$registered_at %||% e$date %||% ""), 1, 10)
  )
}

# --------------------------------------------------------------------
# (e) in-flight WT 파서 (2026-07-10 M6 — F6 병렬 세션 중복실행 실사고 2건 대응)
#   반환: NULL(양쪽 json 파싱 실패) / list(terminal=TRUE)(완주·중단 — 스킵 사유) / 엔트리.
#   phase 정보는 title에 [PHASE]로 임베드 — .hi_row 반환 스키마 불변 유지.
# --------------------------------------------------------------------
HI_INFLIGHT_FRESH_DAYS <- 14L
HI_WT_TERMINAL_REGEX <- "TERMINAT|ABORT|ARCHIV|REJECT|KILL|FAIL|NEGATIVE|DEFERRED|ADMIT|GOVERNOR_DONE|\\bCOMPLETED\\b"

.hi_parse_wt_inflight <- function(wt_dir) {
  req_p <- file.path(wt_dir, "request.json")
  st_p  <- file.path(wt_dir, "status.json")
  req <- if (file.exists(req_p)) tryCatch(fromJSON(req_p, simplifyVector = FALSE), error = function(e) NULL) else NULL
  st  <- if (file.exists(st_p))  tryCatch(fromJSON(st_p,  simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(req) && is.null(st)) return(NULL)

  phase <- toupper(.hi_join(st$current_phase %||% st$phase %||% ""))
  # terminal 판정은 phase + 단계 verdict 필드 합산 텍스트에 적용 — phase가 ALPHA_DONE처럼
  # non-terminal이어도 alpha_verdict=CLEAN_NEGATIVE 등으로 사실상 종결된 WT를 걸러낸다.
  term_txt <- toupper(.hi_join(c(phase, st$alpha_verdict, st$verdict, st$final_verdict)))
  if (nzchar(term_txt) && grepl(HI_WT_TERMINAL_REGEX, term_txt, perl = TRUE)) {
    return(list(terminal = TRUE))
  }

  wt_id <- .hi_join(req$task_id %||% req$wt_id %||% st$task_id %||% "")
  if (!nzchar(wt_id)) wt_id <- basename(wt_dir)

  title <- .hi_join(req$hypothesis_title)
  if (!nzchar(title)) title <- .hi_join(req$title)
  if (!nzchar(title)) title <- .hi_join(req$theme)
  if (!nzchar(title)) title <- .hi_join(req$hypothesis)
  if (!nzchar(title)) title <- wt_id
  desc <- substr(.hi_join(c(req$hypothesis_description, req$theme, req$mandate)), 1, 600)
  text <- .hi_lc(c(title, desc))

  # 활동 신호 = 디렉터리 내 최신 파일 mtime (status.json updated_at 문자열보다 신뢰)
  fs <- list.files(wt_dir, full.names = TRUE)
  mt <- suppressWarnings(max(file.info(fs)$mtime, na.rm = TRUE))
  age_days <- suppressWarnings(as.numeric(difftime(Sys.time(), mt, units = "days")))
  fresh <- is.finite(age_days) && age_days <= HI_INFLIGHT_FRESH_DAYS

  uni <- .hi_join((req$universe_definition %||% list())$label)
  if (!nzchar(uni)) uni <- "unknown"
  structure_tag <- paste0("wt_", tolower(.hi_join(req$wt_type %||% req$type %||% "unknown")))

  list(
    strategy_id = wt_id,
    hypothesis_signature = .hi_signature(
      .hi_infer_family(text), .hi_infer_signal_group(text, title),
      uni, structure_tag),
    title = paste0(wt_id, if (nzchar(phase)) paste0(" [", phase, "]") else "", ": ", title),
    verdict = if (fresh) "IN_PROGRESS" else "INFLIGHT_STALE",
    grade = NA_character_,
    key_metrics = list(),
    source_paths = sub(paste0("^", QM_ROOT, "/"), "", gsub("\\\\", "/", wt_dir)),
    source_types = "wt_inflight",
    date = if (is.finite(age_days)) format(mt, "%Y-%m-%d") else ""
  )
}

# --------------------------------------------------------------------
# 병합: 동일 strategy_id → 1엔트리 (선순위 원천이 기본, 결측만 보충)
# --------------------------------------------------------------------
.hi_merge <- function(base, add) {
  base$source_paths <- unique(c(base$source_paths, add$source_paths))
  base$source_types <- unique(c(base$source_types, add$source_types))
  if (is.na(base$grade %||% NA) && !is.na(add$grade %||% NA)) base$grade <- add$grade
  if ((base$verdict %||% "UNKNOWN") %in% c("UNKNOWN", "REGISTERED") &&
      !(add$verdict %||% "UNKNOWN") %in% c("UNKNOWN", "REGISTERED")) {
    base$verdict <- add$verdict
  }
  for (k in names(add$key_metrics)) {
    if (is.null(base$key_metrics[[k]])) base$key_metrics[[k]] <- add$key_metrics[[k]]
  }
  if (!nzchar(base$date %||% "") && nzchar(add$date %||% "")) base$date <- add$date
  base
}

# --------------------------------------------------------------------
# 빌더
# --------------------------------------------------------------------
build_hypothesis_index <- function(root = QM_ROOT, out_path = HI_INDEX_PATH,
                                   verbose = TRUE) {
  entries <- list()   # keyed by strategy_id
  cov <- list(alpha_search_manifest = 0L, alpha_search_hurdle_fallback = 0L,
              alpha_search_skipped_empty = 0L, alpha_search_parse_fail = 0L,
              lcode_indexed = 0L, lcode_skipped = 0L,
              lcode_supplement_indexed = 0L, lcode_supplement_skipped_dup = 0L,
              lcode_supplement_parse_fail = 0L,
              module_indexed = 0L, module_skipped = 0L,
              distilled_indexed = 0L, distilled_skipped = 0L,
              wt_inflight_indexed = 0L, wt_inflight_skipped_terminal = 0L,
              wt_inflight_skipped_empty = 0L, wt_inflight_parse_fail = 0L,
              wt_inflight_merged_completed = 0L,
              paper_lane_indexed = 0L, paper_lane_measured = 0L, paper_lane_skipped = 0L)

  add_entry <- function(e) {
    if (is.null(e)) return(FALSE)
    id <- e$strategy_id
    if (!is.null(entries[[id]])) entries[[id]] <<- .hi_merge(entries[[id]], e)
    else entries[[id]] <<- e
    TRUE
  }

  # --- (a) alpha_search stage_artifacts ---
  as_root <- file.path(root, "stage_artifacts/alpha_search")
  if (dir.exists(as_root)) {
    dirs <- list.dirs(as_root, recursive = FALSE)
    for (d in dirs) {
      mf <- file.path(d, "strategy_manifest.json")
      hf <- file.path(d, "hurdle_result.json")
      if (file.exists(mf)) {
        if (add_entry(.hi_parse_manifest(mf))) cov$alpha_search_manifest <- cov$alpha_search_manifest + 1L
        else cov$alpha_search_parse_fail <- cov$alpha_search_parse_fail + 1L
      } else if (file.exists(hf)) {
        if (add_entry(.hi_parse_hurdle(hf))) cov$alpha_search_hurdle_fallback <- cov$alpha_search_hurdle_fallback + 1L
        else cov$alpha_search_parse_fail <- cov$alpha_search_parse_fail + 1L
      } else {
        cov$alpha_search_skipped_empty <- cov$alpha_search_skipped_empty + 1L
      }
    }
  }

  # --- (b) lcode corpus ---
  lc_path <- file.path(root, ".cache/lcode_corpus.json")
  lc_seen <- character(0)   # (task#54-1) corpus 반영된 l_code 키 — 보충 스캔 dedup (corpus 우선)
  lc_mtime <- if (file.exists(lc_path)) file.info(lc_path)$mtime
              else as.POSIXct("1970-01-01", tz = "UTC")   # corpus 부재 → 전체 원본 스캔
  if (file.exists(lc_path)) {
    lc <- tryCatch(fromJSON(lc_path, simplifyVector = FALSE), error = function(e) NULL)
    for (e in (lc$lcodes %||% list())) {
      k <- .hi_join(e$l_code); if (nzchar(k)) lc_seen <- c(lc_seen, k)
      pe <- tryCatch(.hi_parse_lcode(e), error = function(err) {
        message(sprintf("[hypothesis_index][WARN] lcode parse 실패 skip: %s (%s)",
                        e$l_code %||% e$strategy_id %||% "?", conditionMessage(err)))
        NULL
      })
      if (add_entry(pe)) cov$lcode_indexed <- cov$lcode_indexed + 1L
      else cov$lcode_skipped <- cov$lcode_skipped + 1L
    }
  }

  # --- (b+) L-code 보충 스캔 (2026-07-13 task#54-1 — corpus 정체 시 게이트 실명 재발 방지) ---
  #   corpus mtime보다 새 원본 L-code 파일을 직접 파싱해 보충. dedup 키 = l_code
  #   (corpus 항목 우선 — corpus에 이미 있으면 skip). 파싱 실패는 skip + 카운트.
  #   경로 패턴은 harvester(lcode_harvester.py)와 동일: mode-분리 + flat back-compat.
  raw_lc_paths <- c(
    Sys.glob(file.path(root, "stage_artifacts/l_code/*/l_code_*.json")),
    Sys.glob(file.path(root, "stage_artifacts/l_code_*.json"))
  )
  if (length(raw_lc_paths)) {
    fi_raw <- file.info(raw_lc_paths)
    raw_new <- raw_lc_paths[!is.na(fi_raw$mtime) & fi_raw$mtime > lc_mtime]
    for (p in raw_new) {
      pe <- tryCatch({
        d <- .hi_raw_lcode_entry(p, root)
        k <- .hi_join(d$l_code)
        if (k %in% lc_seen) {
          cov$lcode_supplement_skipped_dup <- cov$lcode_supplement_skipped_dup + 1L
          NULL
        } else {
          lc_seen <- c(lc_seen, k)
          pe2 <- .hi_parse_lcode(d)
          pe2$source_types <- "lcode_supplement"   # 감사가능성: corpus 경유 아님을 명시
          pe2
        }
      }, error = function(err) {
        message(sprintf("[hypothesis_index][WARN] lcode 보충 스캔 parse 실패 skip: %s (%s)",
                        basename(p), conditionMessage(err)))
        cov$lcode_supplement_parse_fail <<- cov$lcode_supplement_parse_fail + 1L
        NULL
      })
      if (!is.null(pe) && add_entry(pe)) {
        cov$lcode_supplement_indexed <- cov$lcode_supplement_indexed + 1L
      }
    }
  }

  # --- (c) module catalog ---
  mc_path <- file.path(root, "06_Registry/module_catalog.json")
  if (file.exists(mc_path)) {
    mc <- tryCatch(fromJSON(mc_path, simplifyVector = FALSE), error = function(e) NULL)
    for (e in (mc$modules %||% list())) {
      pe <- tryCatch(.hi_parse_module(e), error = function(err) {
        message(sprintf("[hypothesis_index][WARN] module parse 실패 skip: %s (%s)",
                        e$strategy_id %||% "?", conditionMessage(err)))
        NULL
      })
      if (add_entry(pe)) cov$module_indexed <- cov$module_indexed + 1L
      else cov$module_skipped <- cov$module_skipped + 1L
    }
  }

  # --- (d) distilled knowledge (②Distilled — 2026-07-04) ---
  dk_path <- file.path(root, "06_Registry/distilled_knowledge.json")
  if (file.exists(dk_path)) {
    dk <- tryCatch(fromJSON(dk_path, simplifyVector = FALSE), error = function(e) NULL)
    for (e in (dk$entries %||% list())) {
      if (identical(e$status %||% "", "expired")) { cov$distilled_skipped <- cov$distilled_skipped + 1L; next }
      # ★silent-drop 가시화 (P0#1 동반): parse 예외를 조용히 NULL로 삼키지 않는다.
      #   실패 시 stderr WARN(dist_id + 사유) + 최소필드 엔트리로라도 포함(완전 드롭 금지).
      pe <- tryCatch(.hi_parse_distilled(e), error = function(err) {
        did <- e$dist_id %||% "(no dist_id)"
        message(sprintf("[hypothesis_index][WARN] distilled parse 실패 → 최소필드 포함: %s (%s)",
                        did, conditionMessage(err)))
        .hi_min_distilled_entry(e, conditionMessage(err))
      })
      if (add_entry(pe)) cov$distilled_indexed <- cov$distilled_indexed + 1L
      else cov$distilled_skipped <- cov$distilled_skipped + 1L
    }
  }

  # --- (f) 논문 레인 = method_registry (2026-08-13 신설, 도훈 지시) ---
  #   논문 라우팅의 종착 = 여기. 1차 리서치 결과를 모드가 조회 가능한 형태로 올려둔다.
  #   ★자기 strategy_id 공간(PL_*)을 쓰므로 (a)~(e) 와 병합 충돌이 없다 — 순서 무관.
  ml_path <- file.path(root, "06_Registry/method_registry.json")
  if (file.exists(ml_path)) {
    ml <- tryCatch(fromJSON(ml_path, simplifyVector = FALSE), error = function(e) NULL)
    pmeas <- tryCatch(.hi_paper_lane_measurements(root), error = function(e) list())
    for (e in (ml$methods %||% list())) {
      pe <- tryCatch(.hi_parse_paper_lane(e, pmeas), error = function(err) {
        message(sprintf("[hypothesis_index][WARN] paper_lane parse 실패 skip: %s (%s)",
                        e$method_id %||% "?", conditionMessage(err)))
        NULL
      })
      if (add_entry(pe)) {
        cov$paper_lane_indexed <- cov$paper_lane_indexed + 1L
        if (identical(pe$verdict, "PAPER_LANE_MEASURED"))
          cov$paper_lane_measured <- cov$paper_lane_measured + 1L
      } else cov$paper_lane_skipped <- cov$paper_lane_skipped + 1L
    }
  }

  # --- (e) in-flight WT mailbox (2026-07-10 M6 — 원천 5) ---
  #   반드시 (a)~(d) 뒤에 합류: 동일 strategy_id 병합 시 완주 산출물이 base가 되어
  #   IN_PROGRESS가 확정 verdict를 덮지 않는다 (.hi_merge verdict 규칙).
  wt_root <- file.path(root, "qepm/mailbox/worktask")
  if (dir.exists(wt_root)) {
    wdirs <- list.dirs(wt_root, recursive = FALSE)
    wdirs <- wdirs[!basename(wdirs) %in% c("processed", "integration")]
    for (d in wdirs) {
      if (!file.exists(file.path(d, "request.json")) &&
          !file.exists(file.path(d, "status.json"))) {
        cov$wt_inflight_skipped_empty <- cov$wt_inflight_skipped_empty + 1L
        next
      }
      pe <- tryCatch(.hi_parse_wt_inflight(d), error = function(err) {
        message(sprintf("[hypothesis_index][WARN] wt_inflight parse 실패 skip: %s (%s)",
                        basename(d), conditionMessage(err)))
        NULL
      })
      if (is.null(pe)) { cov$wt_inflight_parse_fail <- cov$wt_inflight_parse_fail + 1L; next }
      if (isTRUE(pe$terminal)) { cov$wt_inflight_skipped_terminal <- cov$wt_inflight_skipped_terminal + 1L; next }
      # prefix-병합: 완주 L-code/manifest가 "<WT_ID>_<slug>" 키로 적립되는 관례 →
      #   bare WT_ID와 키 불일치로 FAIL·IN_PROGRESS가 이중 표출되던 갭. prefix 일치 시
      #   완주 엔트리에 병합(완주 verdict 보존, source에 wt_inflight 누적).
      pref <- names(entries)[startsWith(names(entries), paste0(pe$strategy_id, "_"))]
      if (length(pref)) {
        entries[[pref[1]]] <- .hi_merge(entries[[pref[1]]], pe)
        cov$wt_inflight_merged_completed <- cov$wt_inflight_merged_completed + 1L
        next
      }
      if (add_entry(pe)) cov$wt_inflight_indexed <- cov$wt_inflight_indexed + 1L
      else cov$wt_inflight_parse_fail <- cov$wt_inflight_parse_fail + 1L
    }
  }

  out <- list(
    schema_version = "hypothesis_index_v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    note = paste("AS-03 duplicate-hypothesis prevention index.",
                 "signature = family|signal_group|universe|structure.",
                 "Rebuild: Rscript 02_Infrastructure/tools/hypothesis_index.R build"),
    coverage = cov,
    n_entries = length(entries),
    entries = unname(entries)
  )
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  # (F-1 2026-07-10 v8.3 적대검증) 원자적 쓰기 — 같은 디렉터리 temp + rename 교체.
  #   구 동작(write_json 직접)은 중단/동시읽기 시 반파일(손상 JSON)을 남기고, 손상 파일은
  #   mtime이 최신이라 stale 재빌드도 미트리거였음. temp-rename은 이 리포 확립 관행
  #   ([project-windows-arrow-mmap-1224] OneDrive 특성). Windows file.rename은 대상 존재 시
  #   실패 → 대상 제거 후 rename, 그래도 실패 시 file.copy(overwrite)+remove 폴백.
  tmp_path <- file.path(dirname(out_path),
                        paste0(".", basename(out_path), ".tmp_", Sys.getpid()))
  write_json(out, tmp_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (file.exists(out_path)) suppressWarnings(file.remove(out_path))
  renamed <- suppressWarnings(file.rename(tmp_path, out_path))
  if (!isTRUE(renamed)) {
    ok_copy <- suppressWarnings(file.copy(tmp_path, out_path, overwrite = TRUE))
    suppressWarnings(file.remove(tmp_path))
    if (!isTRUE(ok_copy)) {
      stop("[hypothesis_index] 원자적 교체 실패 — temp 기록은 성공했으나 rename/copy 모두 실패: ",
           tmp_path, " -> ", out_path)
    }
  }
  if (verbose) {
    cat(sprintf("[hypothesis_index] %d entries -> %s\n", length(entries), out_path))
    cat(sprintf("  manifest=%d hurdle_fallback=%d skipped_empty=%d parse_fail=%d\n",
                cov$alpha_search_manifest, cov$alpha_search_hurdle_fallback,
                cov$alpha_search_skipped_empty, cov$alpha_search_parse_fail))
    cat(sprintf("  lcode=%d (skip %d)  module=%d (skip %d)  distilled=%d (skip %d)\n",
                cov$lcode_indexed, cov$lcode_skipped,
                cov$module_indexed, cov$module_skipped,
                cov$distilled_indexed, cov$distilled_skipped))
    cat(sprintf("  lcode_supplement=%d (dup skip %d, parse_fail %d) [corpus보다 새 원본 직접 파싱]\n",
                cov$lcode_supplement_indexed, cov$lcode_supplement_skipped_dup,
                cov$lcode_supplement_parse_fail))
    cat(sprintf("  wt_inflight=%d (terminal skip %d, empty %d, parse_fail %d, merged_completed %d)\n",
                cov$wt_inflight_indexed, cov$wt_inflight_skipped_terminal,
                cov$wt_inflight_skipped_empty, cov$wt_inflight_parse_fail,
                cov$wt_inflight_merged_completed))
  }
  invisible(out)
}

# --------------------------------------------------------------------
# ★P0#3 쿼리측 정규화 (2026-07-04 감사): build 시점에만 쓰던 SIGNAL/FAMILY_PATTERNS를
#   조회 쿼리 키워드에도 적용. 쿼리 한 토큰이 어느 패밀리/시그널 패턴에 매치되면
#   그 canonical 별칭명을 haystack 매치 후보로 함께 추가 → 동의어/한영/축약 흡수.
#   패턴 사전이 없거나 매치 안 되면 최소 별칭맵으로 폴백 확장.
#   확장 결과는 "OR" 후보 집합(한 원 토큰 → {원토큰, 별칭...} 중 하나만 매치돼도 그 토큰 충족).
# --------------------------------------------------------------------
HI_QUERY_ALIAS <- list(
  value      = c("value", "가치", "밸류", "ep", "per", "pbr", "bm", "저평가"),
  momentum   = c("momentum", "모멘텀", "추세", "trend", "mom"),
  reversal   = c("reversal", "리버설", "반전", "contrarian", "역추세", "loser"),
  defense    = c("defense", "defensive", "방어", "low-beta", "lowbeta", "저베타", "lowvol", "저변동", "min-vol"),
  regime     = c("regime", "국면", "overlay", "오버레이", "timing", "타이밍"),
  quality    = c("quality", "퀄리티", "품질", "qmj"),
  profitability = c("profitability", "수익성", "roe", "roa", "마진"),
  earnings   = c("earnings", "어닝", "이익", "실적", "sue", "revision", "리비전"),
  flow       = c("flow", "수급", "외국인", "기관", "insider", "내부자", "공매도", "short"),
  size       = c("size", "소형주", "small-cap", "smallcap"),
  liquidity  = c("liquidity", "유동성", "amihud", "illiquid"),
  ml         = c("ml", "머신러닝", "딥러닝", "xgboost", "lightgbm", "hgb", "ipca", "sdf", "ensemble", "앙상블"),
  dividend   = c("dividend", "배당", "주주환원", "buyback", "자사주", "shareholder")
)

# 원 토큰 하나를 {원토큰} ∪ {패턴 매치된 canonical 명} ∪ {별칭맵 상호 별칭}으로 확장.
# 반환: 소문자 문자열 벡터(중복 제거). haystack에 이 중 하나라도 부분매치되면 그 토큰 충족.
.hi_expand_kw <- function(kw) {
  kw <- tolower(trimws(kw))
  out <- kw
  # (a) SIGNAL/FAMILY 패턴 사전이 로드돼 있으면 canonical 명 추가
  if (exists("SIGNAL_PATTERNS")) {
    for (nm in names(SIGNAL_PATTERNS)) {
      if (grepl(SIGNAL_PATTERNS[[nm]], kw, ignore.case = TRUE, perl = TRUE)) out <- c(out, nm)
    }
  }
  if (exists("FAMILY_PATTERNS")) {
    for (nm in names(FAMILY_PATTERNS)) {
      if (grepl(FAMILY_PATTERNS[[nm]], kw, ignore.case = TRUE, perl = TRUE)) out <- c(out, nm)
    }
  }
  # (b) 별칭맵: kw가 어느 별칭군에 속하면 그 군 전체를 후보로 추가(상호 확장)
  for (grp in names(HI_QUERY_ALIAS)) {
    al <- HI_QUERY_ALIAS[[grp]]
    if (kw %in% al || any(vapply(al, function(a) grepl(a, kw, fixed = TRUE), logical(1)))) {
      out <- c(out, grp, al)
    }
  }
  unique(out[nzchar(out)])
}

# stale 검사: distilled_knowledge.json / module_catalog.json / lcode_corpus.json /
# in-flight WT mailbox(request/status.json) mtime이 hypothesis_index.json mtime보다
# 최신이면 인덱스가 뒤처짐. warn=TRUE면 경고 메시지 (auto-rebuild 경로에선 FALSE로 억제).
.hi_stale_check <- function(index_path, root = QM_ROOT, warn = TRUE) {
  if (!file.exists(index_path)) return(invisible(NULL))
  idx_mt <- file.info(index_path)$mtime
  srcs <- c("06_Registry/distilled_knowledge.json",
            "06_Registry/module_catalog.json",
            ".cache/lcode_corpus.json",
            # (2026-08-13) 논문 레인 원천 — 이게 빠져 있으면 어댑터를 등재해도 인덱스가
            #   stale 로 안 잡히고 lookup 이 **옛 인덱스를 조용히 내준다**. 콜렉터만 붙이고
            #   여기를 안 고치면 "등재했는데 모드에겐 안 보이는" 상태가 그대로 남는다
            #   — 이 저장소가 반복 확인한 '존재 = 배선 완료' 오독 계통.
            "06_Registry/method_registry.json",
            "06_Registry/book_carrier/h2_regime_overlay_ab.csv",
            "06_Registry/book_carrier/h1b_sigma_ab_overlay.csv")
  stale <- character(0)
  for (s in srcs) {
    p <- file.path(root, s)
    if (file.exists(p) && file.info(p)$mtime > idx_mt) stale <- c(stale, s)
  }
  # (task#54-1 2026-07-13) 원본 L-code 파일이 인덱스보다 최신이면 stale — corpus 정체와
  #   무관하게 lookup 자동 재빌드(→ 보충 스캔 소비)가 트리거되도록 원본 계층을 직접 감시.
  raw_lc <- c(Sys.glob(file.path(root, "stage_artifacts/l_code/*/l_code_*.json")),
              Sys.glob(file.path(root, "stage_artifacts/l_code_*.json")))
  if (length(raw_lc)) {
    raw_mt <- suppressWarnings(max(file.info(raw_lc)$mtime, na.rm = TRUE))
    if (is.finite(raw_mt) && raw_mt > idx_mt) stale <- c(stale, "stage_artifacts/l_code (원본 L-code)")
  }
  # (M6 2026-07-10) in-flight WT 원천 stale 검사 — mailbox의 request/status.json 최신 mtime
  wt_files <- Sys.glob(file.path(root, "qepm/mailbox/worktask/*", c("status.json", "request.json")))
  if (length(wt_files)) {
    wt_mt <- suppressWarnings(max(file.info(wt_files)$mtime, na.rm = TRUE))
    if (is.finite(wt_mt) && wt_mt > idx_mt) stale <- c(stale, "qepm/mailbox/worktask (in-flight WT)")
  }
  if (length(stale) && warn) {
    message(sprintf("[hypothesis_index][경고] 인덱스 stale — 다음 원천이 인덱스보다 최신: %s. build 권장 (Rscript 02_Infrastructure/tools/hypothesis_index.R build)",
                    paste(stale, collapse = ", ")))
  }
  invisible(stale)
}

# 엔트리 → 조회 결과 1행. (P2: distilled_status 컬럼 노출)
.hi_row <- function(e) {
  km <- e$key_metrics %||% list()
  data.frame(
    strategy_id = e$strategy_id,
    signature = e$hypothesis_signature,
    title = substr(e$title, 1, 80),
    verdict = e$verdict,
    grade = as.character(e$grade %||% NA_character_),
    # P2: consumer가 미승인 초안(proposed) vs 승인(distilled/5축통과)을 구분
    distilled_status = as.character(e$distilled_status %||% ""),
    sharpe = .hi_num(km$sharpe) %||% NA_real_,
    port_t = .hi_num(km$portfolio_alpha_t) %||% NA_real_,
    # ②Distilled negative failure-ledger: 지도-프레임 라벨(탐색됨→프론티어→트리거, INV-7 provisional)
    retry_policy = as.character(e$retry_policy %||% ""),
    date = e$date %||% "",
    source = paste(e$source_types %||% "", collapse = ","),
    stringsAsFactors = FALSE
  )
}

# 한 엔트리가 키워드 집합을 (AND) 충족하는가.
#   각 원 키워드는 확장 후보 집합 중 하나라도 haystack에 부분매치되면 충족(OR).
#   전 키워드가 충족돼야 엔트리 매치(AND).
.hi_entry_matches <- function(e, kw_expansions) {
  hay <- tolower(paste(e$hypothesis_signature, e$title, e$verdict,
                       e$grade %||% "", e$strategy_id))
  all(vapply(kw_expansions, function(cands)
    any(vapply(cands, function(k) grepl(k, hay, fixed = TRUE), logical(1))),
    logical(1)))
}

# --------------------------------------------------------------------
# 조회: lookup_hypothesis(keywords)
#   keywords: 문자 벡터 또는 공백구분 문자열. 전 키워드 AND 매치(각 키워드는 별칭 OR 확장).
#   (signature + title + verdict + grade + strategy_id 텍스트에 대해 대소문자 무시 부분매치)
#   반환: data.frame (distilled 우선 → date 내림차순).
#   ★P0#2: N어 AND가 0건이면 마지막 키워드 단독 재조회 + 배너.
#   ★P0#3: 각 키워드는 SIGNAL/FAMILY 패턴 + 별칭맵으로 확장(동의어/한영/축약 흡수).
#   ★P1→M6 (2026-07-10): stale 감지 시 경고-only → 인라인 자동 재빌드 (auto_rebuild=TRUE
#     기본. 전체 빌드 실측 ~2s. 재빌드 실패 시 기존 인덱스로 폴백 + 경고 — lookup은 항상 응답).
# --------------------------------------------------------------------
lookup_hypothesis <- function(keywords, index_path = HI_INDEX_PATH,
                              max_rows = 30L, auto_rebuild = TRUE) {
  if (!file.exists(index_path)) {
    stop("hypothesis_index.json not found — run build_hypothesis_index() first: ", index_path)
  }
  stale <- .hi_stale_check(index_path, warn = !auto_rebuild)   # M6: 자동 재빌드 경로선 경고 억제
  if (auto_rebuild && length(stale)) {
    message(sprintf("[hypothesis_index] stale 감지(%s) → 인라인 자동 재빌드",
                    paste(stale, collapse = ", ")))
    ok <- tryCatch({
      build_hypothesis_index(out_path = index_path, verbose = FALSE)
      TRUE
    }, error = function(e) {
      message("[hypothesis_index][경고] 인라인 재빌드 실패 — 기존(stale) 인덱스로 진행: ",
              conditionMessage(e))
      FALSE
    })
    if (isTRUE(ok)) message("[hypothesis_index] 재빌드 완료 — fresh 인덱스로 조회")
  }
  # (F-1 2026-07-10 v8.3 적대검증) 손상 인덱스 자가치유 — 손상 파일은 mtime이 최신이라
  #   위 stale 재빌드가 미트리거. parse 실패 시 강제 재빌드 폴백(재빌드도 실패하면 명시 에러).
  idx <- tryCatch(fromJSON(index_path, simplifyVector = FALSE), error = function(e) {
    message("[hypothesis_index][경고] 인덱스 파싱 실패(손상 추정): ", conditionMessage(e),
            " → 강제 재빌드")
    ok <- tryCatch({
      build_hypothesis_index(out_path = index_path, verbose = FALSE)
      TRUE
    }, error = function(e2) {
      message("[hypothesis_index][오류] 강제 재빌드 실패: ", conditionMessage(e2))
      FALSE
    })
    if (!isTRUE(ok)) {
      stop("hypothesis_index.json 손상 + 강제 재빌드 실패 — 수동 점검 필요: ", index_path,
           " (원 파싱 오류: ", conditionMessage(e), ")")
    }
    tryCatch(fromJSON(index_path, simplifyVector = FALSE), error = function(e3) {
      stop("hypothesis_index.json 재빌드 직후에도 파싱 실패 — 수동 점검 필요: ", index_path,
           " (", conditionMessage(e3), ")")
    })
  })
  kws <- tolower(unlist(strsplit(paste(keywords, collapse = " "), "\\s+")))
  kws <- kws[nzchar(kws)]
  if (length(kws) == 0) stop("empty keywords")

  # 각 키워드 별칭 확장(P0#3)
  kw_exp <- lapply(kws, .hi_expand_kw)

  collect <- function(expansions) {
    rows <- list()
    for (e in idx$entries) {
      if (.hi_entry_matches(e, expansions)) rows[[length(rows) + 1L]] <- .hi_row(e)
    }
    rows
  }

  rows <- collect(kw_exp)

  # ★P0#2 다어 폴백: N어 AND 0건이면 마지막 키워드 단독 재조회
  if (length(rows) == 0 && length(kws) > 1) {
    last_kw <- kws[length(kws)]
    message(sprintf("[경고] %d어 AND 0건 → 단일어 폴백('%s')", length(kws), last_kw))
    rows <- collect(list(.hi_expand_kw(last_kw)))
  }

  if (length(rows) == 0) {
    message("[hypothesis_index] no prior attempt matched: ", paste(kws, collapse = " "))
    return(invisible(data.frame()))
  }
  df <- do.call(rbind, rows)
  # distilled 계층 우선 노출(폴백 배너 상황에서도), 그 다음 date 내림차순.
  # dist_rank 0 = distilled(먼저), 1 = 그 외. date는 문자열 역순.
  dist_rank <- ifelse(grepl("^DISTILLED", df$verdict), 0L, 1L)
  ord <- order(dist_rank, -xtfrm(df$date))
  df <- df[ord, , drop = FALSE]
  rownames(df) <- NULL
  head(df, max_rows)
}

# --------------------------------------------------------------------
# CLI dispatch (Rscript 직접 실행 시에만)
# --------------------------------------------------------------------
if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && args[1] == "build") {
    build_hypothesis_index()
  } else if (length(args) >= 2 && args[1] == "lookup") {
    res <- lookup_hypothesis(args[-1])
    if (nrow(res) > 0) print(res, right = FALSE)
  } else {
    cat("usage:\n  Rscript hypothesis_index.R build\n  Rscript hypothesis_index.R lookup <keyword> [keyword...]\n")
  }
}
