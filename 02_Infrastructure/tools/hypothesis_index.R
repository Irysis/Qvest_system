# =====================================================================
# hypothesis_index.R — 가설 중복실험 방지 인덱스 (빌더 + 조회)
# =====================================================================
# 감사 AS-03 대응: 687회+ 실험의 "이미 시도됨" 판정이 LLM 메모리에 의존하던
# 구조를 파일 인덱스로 대체. alpha-search Step 0 이전 조회 의무
# (.claude/skills/alpha-search/SKILL.md 참조).
#
# 원천 4계층 (2026-07-04 엔진 재설계 — distilled 추가):
#   (a) stage_artifacts/alpha_search/*/strategy_manifest.json  (완주 run)
#       + strategy_manifest 부재 시 hurdle_result.json fallback (초기 run)
#       + 둘 다 없는 빈 디렉터리는 중단 run으로 스킵 (사유 기록)
#   (b) .cache/lcode_corpus.json                               (L-code 594건+)
#   (c) 06_Registry/module_catalog.json                        (등록 모듈 265건+)
#   (d) 06_Registry/distilled_knowledge.json                   (②Distilled 클러스터 통합 지식)
#       verdict = DISTILLED_NEG / DISTILLED_COND / DISTILLED_POS.
#       negative는 lookup 결과에 retry_policy를 지도-프레임(탐색됨 → 프론티어(미탐색) →
#       부활 트리거 → 봉투 안 차별점 명시 시 진행 가능; INV-7 provisional = 불변 기각 아님)으로
#       표출. frontier/live_trigger 필드 있으면 표출, 없으면 retry_condition/expiry 폴백.
#       반복기록 N건보다 대표 1건 + 회차 이력이 가설 시점 pull 대조에 정밀.
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
              module_indexed = 0L, module_skipped = 0L,
              distilled_indexed = 0L, distilled_skipped = 0L)

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
  if (file.exists(lc_path)) {
    lc <- tryCatch(fromJSON(lc_path, simplifyVector = FALSE), error = function(e) NULL)
    for (e in (lc$lcodes %||% list())) {
      pe <- tryCatch(.hi_parse_lcode(e), error = function(err) {
        message(sprintf("[hypothesis_index][WARN] lcode parse 실패 skip: %s (%s)",
                        e$l_code %||% e$strategy_id %||% "?", conditionMessage(err)))
        NULL
      })
      if (add_entry(pe)) cov$lcode_indexed <- cov$lcode_indexed + 1L
      else cov$lcode_skipped <- cov$lcode_skipped + 1L
    }
  }

  # --- (c) module catalog ---
  mc_path <- file.path(root, "06_Registry/module_catalog.json")
  if (file.exists(mc_path)) {
    mc <- tryCatch(fromJSON(mc_path, simplifyVector = FALSE), error = function(e) NULL)
    for (e in (mc$modules %||% list())) {
      pe <- tryCatch(.hi_parse_module(e), error = function(err) NULL)
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
  write_json(out, out_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (verbose) {
    cat(sprintf("[hypothesis_index] %d entries -> %s\n", length(entries), out_path))
    cat(sprintf("  manifest=%d hurdle_fallback=%d skipped_empty=%d parse_fail=%d\n",
                cov$alpha_search_manifest, cov$alpha_search_hurdle_fallback,
                cov$alpha_search_skipped_empty, cov$alpha_search_parse_fail))
    cat(sprintf("  lcode=%d (skip %d)  module=%d (skip %d)  distilled=%d (skip %d)\n",
                cov$lcode_indexed, cov$lcode_skipped,
                cov$module_indexed, cov$module_skipped,
                cov$distilled_indexed, cov$distilled_skipped))
  }
  invisible(out)
}

# --------------------------------------------------------------------
# 조회: lookup_hypothesis(keywords)
#   keywords: 문자 벡터 또는 공백구분 문자열. 전 키워드 AND 매치
#   (signature + title + verdict + grade + strategy_id 텍스트에 대해
#    대소문자 무시 부분매치). 반환: data.frame (date 내림차순).
# --------------------------------------------------------------------
lookup_hypothesis <- function(keywords, index_path = HI_INDEX_PATH,
                              max_rows = 30L) {
  if (!file.exists(index_path)) {
    stop("hypothesis_index.json not found — run build_hypothesis_index() first: ", index_path)
  }
  idx <- fromJSON(index_path, simplifyVector = FALSE)
  kws <- tolower(unlist(strsplit(paste(keywords, collapse = " "), "\\s+")))
  kws <- kws[nzchar(kws)]
  if (length(kws) == 0) stop("empty keywords")
  rows <- list()
  for (e in idx$entries) {
    hay <- tolower(paste(e$hypothesis_signature, e$title, e$verdict,
                         e$grade %||% "", e$strategy_id))
    if (all(vapply(kws, function(k) grepl(k, hay, fixed = TRUE), logical(1)))) {
      km <- e$key_metrics %||% list()
      rows[[length(rows) + 1L]] <- data.frame(
        strategy_id = e$strategy_id,
        signature = e$hypothesis_signature,
        title = substr(e$title, 1, 80),
        verdict = e$verdict,
        grade = as.character(e$grade %||% NA_character_),
        sharpe = .hi_num(km$sharpe) %||% NA_real_,
        port_t = .hi_num(km$portfolio_alpha_t) %||% NA_real_,
        # ②Distilled negative failure-ledger: 지도-프레임 라벨(탐색됨→프론티어→트리거, INV-7 provisional)
        retry_policy = as.character(e$retry_policy %||% ""),
        date = e$date %||% "",
        source = paste(e$source_types %||% "", collapse = ","),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    message("[hypothesis_index] no prior attempt matched: ", paste(kws, collapse = " "))
    return(invisible(data.frame()))
  }
  df <- do.call(rbind, rows)
  df <- df[order(df$date, decreasing = TRUE), , drop = FALSE]
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
