# sleeve_delivery.R — 처치 전달량 계약 (B7 슬리브 전달량 · cap_core 코어 몫) · 2026-10-03 신설
# =============================================================================
# ★라벨: "진단 — 등급 대체 아님". 등급은 essence_score.R 하나다. 이 계약은 한 칸의 산출 디렉터리에서 엔진 진단(rf_engine_diag.json)의
#   시그널일별 행을 읽어 **요약을 재도출**하고, 같은 디렉터리 authoritative_remeasure.json 의 실현 규약(measurement_regime.exec_price)을 붙여
#   판정 입력이 될 수 있는 산출물(sd_write)을 낸다. 엔진이 적은 요약은 믿지 않는다 — 재도출 값과 다르면 멈춘다(AX-008 · 손 수치·변조 차단).
#
# 왜 필요한가 (결정 PR-L2-B7-EXCL-UNIT (c) · 도훈 2026-09-26): PR-L2 B7 처치는 F1 기저 팩터 id 만 제외하므로(결정 문언 = id 단위) 같은 계열
#   (D35/D36 등)이 슬리브를 차지해 **바닥이 이미 보유한 이름을 다시 고르는** 희석이 남는다. 희석은 막지 않고 잰다 — 슬리브가 교체한 자리 중
#   바닥 보유와 다른 종목 비율을 사전등록 지표로 두고, 하한 미달이면 결말 treatment_dilution(판정 불가). 하한 값은 이 계약이 정하지 않는다.
#
# 정의 (section = "sleeve_delivery" · rf_sleeve.R::rf_sl_delivery 와 같은 식 — 여기서 행으로부터 다시 계산한다):
#   시그널일 t: n_alpha = min(n_max − k, n_before) · n_sleeve = n_after − n_alpha · n_new = 슬리브 전 바닥 선정에 없던 이름 수 ·
#   delivery_t = n_new / n_sleeve (n_sleeve > 0 인 날만).
#   ★value = δ = Σ_t n_new / Σ_t n_sleeve (풀링) — 사전등록 지표 treatment_delivery 의 문언 그대로(PR-L2 draft3 metrics ·
#     "δ = Σ_t |S_t \ H_t| / Σ_t |S_t| (풀링)" · 2026-10-03 재개 정합 — 초판은 시그널일 등가중 평균을 value 로 냈다. 슬리브 자리 수가
#     시그널일마다 같으면(k 고정 · 후보 충분) 두 값이 같지만, 자리 수가 갈리는 날이 있으면 다르다 — 판정 입력은 등록 문언이어야 한다).
#   mean_by_date = mean_t(delivery_t)(시그널일 등가중 · 보고용) · min · median · share_zero(delivery=0 인 날 비율) · share_full ·
#   per_date = 시그널일별 (n_sleeve, n_new, delivery) 표 · n_signal_dates.
#   ★'바닥 보유' = 같은 실행의 슬리브 전 선정(.sl_before)이다 — 칸 스펙 = 바닥 스펙 + 슬리브일 때 바닥 F1 의 보유와 같다(rebalance·overlay 가
#     바닥에 없을 때 · PR-L2 F1 = rebalance null · overlay 없음). 다른 칸에서 쓰면 그 전제를 산출물 basis 로 드러낸다.
# 정의 (section = "cap_core"): value = mean_t(Σ코어_t) · 그 밖 겹침·절단·보유 수 요약(진단).
#
# 입력 계약(어기면 stop): 진단 schema = rf_engine_diag_v1 · 해당 section 존재 · 행의 (Date) 유일 · 정수 불변식(0 ≤ n_new ≤ n_sleeve) ·
#   엔진 요약 ≡ 재도출(허용 1e-12) · authoritative_remeasure.json 존재 ∧ measurement_regime.exec_price 비어 있지 않음.
# 출력 = 최상위 measurement_regime(exec_price · source) + contract·version·label·section·value(δ 풀링)·pooled·mean_by_date·min·median·
#   share_zero·share_full·n_dates·n_signal_dates·per_date·k · excluded_ids·resolved_id·cell_code·spec_md5 · source_artifact·source_sha256(진단 파일) ·
#   inputs{diag_sha256, auth_sha256}. sd_write(res, out_dir, metric =, target =) = 명시 out_dir 에만 JSON(원자 쓰기 · metric·target 을 주면
#   최상위에 실어 소비자가 측정 객체와 대조한다).
# 소비: rf_prereg.R 판정 입력 검사 — prereg_config verdict.contracts 에 'sleeve_delivery'(artifact_regime_required=true)가 등재돼 있어야
#   한다(등재는 사전등록 설정 개정 = preregfix 소관 · 이 키트는 계약만). 소비자는 등재 file 의 **존재**만 본다 — 등재 file 은 이 파일
#   (02_Infrastructure/contracts/sleeve_delivery.R · 산출 writer)을 권고한다(preregfix 스테이징판은 rf_sleeve.R 을 적었다 · 보고서 교차 항목).
# 검사 = 08_Tests/contracts/test_sleeve_delivery.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

SD_VERSION <- "sleeve_delivery_v1"
.sd_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.sd_sha <- function(p) {   # rf_prereg.R .rfp_sha_raw 와 같은 규약(바이트 sha256 · digest > openssl · 없으면 stop)
  r <- readBin(p, "raw", n = file.info(p)$size)
  if (requireNamespace("digest", quietly = TRUE)) return(digest::digest(r, algo = "sha256", serialize = FALSE))
  if (requireNamespace("openssl", quietly = TRUE)) return(as.character(openssl::sha256(r)))
  stop("[sd] sha256 도구(digest/openssl) 부재")
}

#' 산출 디렉터리 → 계약 산출(list). section = "sleeve_delivery" | "cap_core"
sd_measure <- function(artifact_dir, section = c("sleeve_delivery", "cap_core"), diag_name = "rf_engine_diag.json",
                       auth_name = "authoritative_remeasure.json") {
  section <- match.arg(section)
  if (missing(artifact_dir) || !nzchar(artifact_dir) || !dir.exists(artifact_dir)) stop("[sd] 산출 디렉터리 부재: ", artifact_dir)
  dp <- file.path(artifact_dir, diag_name); ap <- file.path(artifact_dir, auth_name)
  if (!file.exists(dp)) stop("[sd] 엔진 진단 부재(", diag_name, ") — 엔진이 이 칸에서 진단을 안 썼다(러너 밖 실행?) · 전달량 미측정")
  if (!file.exists(ap)) stop("[sd] authoritative_remeasure.json 부재 — 실현 규약(exec_price)을 재도출할 수 없다")
  D <- fromJSON(dp, simplifyVector = TRUE)
  if (!identical(as.character(.sd_or(D$schema, "")), "rf_engine_diag_v1")) stop("[sd] 진단 schema 불일치: ", .sd_or(D$schema, "(없음)"))
  S <- D[[section]]
  if (is.null(S)) stop(sprintf("[sd] 진단에 %s 절이 없다 — 이 칸은 그 처치를 안 받았다", section))
  A <- fromJSON(ap, simplifyVector = TRUE)
  ep <- as.character(.sd_or(.sd_or(A$measurement_regime, list())$exec_price, ""))
  if (length(ep) != 1L || !nzchar(ep)) stop("[sd] authoritative_remeasure.json 에 measurement_regime.exec_price 가 없다(실현 규약 재도출 불가)")
  res <- if (identical(section, "sleeve_delivery")) .sd_sleeve(S) else .sd_capcore(S)
  d_sha <- .sd_sha(dp)
  c(list(contract = "sleeve_delivery", version = SD_VERSION, label = "진단 — 등급 대체 아님", section = section),
    res,
    list(cell_code = as.character(.sd_or(D$cell_code, NA_character_)), spec_md5 = as.character(.sd_or(D$spec_md5, NA_character_)),
         source_artifact = normalizePath(dp, winslash = "/", mustWork = TRUE), source_sha256 = d_sha,
         measurement_regime = list(exec_price = ep, source = auth_name),
         inputs = list(artifact_dir = normalizePath(artifact_dir, winslash = "/", mustWork = TRUE),
                       diag = diag_name, diag_sha256 = d_sha, auth = auth_name, auth_sha256 = .sd_sha(ap)),
         computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")))
}

.sd_num <- function(x) suppressWarnings(as.numeric(.sd_or(x, NA_real_)))[1]
.sd_same <- function(a, b) (is.na(a) && is.na(b)) || (!is.na(a) && !is.na(b) && abs(a - b) <= 1e-12)

.sd_sleeve <- function(S) {
  R <- as.data.table(S$rows)
  need <- c("Date", "n_before", "n_after", "n_alpha", "n_sleeve", "n_new")
  if (!nrow(R) || !all(need %in% names(R))) stop(sprintf("[sd] sleeve_delivery 행 열 부재: %s", paste(setdiff(need, names(R)), collapse = ",")))
  if (anyDuplicated(R$Date)) stop("[sd] sleeve_delivery 행 Date 중복")
  for (cc in need[-1]) R[[cc]] <- as.integer(R[[cc]])
  k <- as.integer(.sd_or(.sd_or(S$summary, list())$k, .sd_or(S$rule, list())$k)); nmax <- as.integer(.sd_or(S$summary$n_max, NA_integer_))
  if (length(k) != 1L || is.na(k) || length(nmax) != 1L || is.na(nmax)) stop("[sd] k·n_max 부재")
  # 정수 불변식 — 행끼리의 관계를 다시 잰다(엔진 계산과 독립)
  if (any(R$n_alpha != pmin(nmax - k, R$n_before))) stop("[sd] n_alpha ≠ min(n_max − k, n_before) — 행 변조 또는 계산 불일치")
  if (any(R$n_sleeve != R$n_after - R$n_alpha)) stop("[sd] n_sleeve ≠ n_after − n_alpha")
  if (any(R$n_sleeve < 0L) || any(R$n_new < 0L) || any(R$n_new > R$n_sleeve)) stop("[sd] 0 ≤ n_new ≤ n_sleeve 위반")
  ok <- R$n_sleeve > 0L
  v <- R$n_new[ok] / R$n_sleeve[ok]
  pooled <- if (sum(R$n_sleeve) > 0L) sum(R$n_new) / sum(R$n_sleeve) else NA_real_
  out <- list(value = pooled,   # ★δ(풀링) = 사전등록 treatment_delivery 문언 — 등가중 평균(mean_by_date)이 아니다
              pooled = pooled,
              mean_by_date = if (length(v)) mean(v) else NA_real_,
              min = if (length(v)) min(v) else NA_real_, median = if (length(v)) stats::median(v) else NA_real_,
              share_zero = if (length(v)) mean(v == 0) else NA_real_, share_full = if (length(v)) mean(v == 1) else NA_real_,
              n_dates = nrow(R), n_signal_dates = nrow(R), n_dates_with_sleeve = sum(ok), k = k, n_max = nmax,
              per_date = R[, .(Date = as.character(Date), n_sleeve, n_new,
                               delivery = ifelse(n_sleeve > 0L, n_new / pmax(n_sleeve, 1L), NA_real_))])
  # 엔진 요약 ≡ 재도출 — 다르면 멈춘다(엔진 요약을 판정 입력으로 쓰지 않는다)
  es <- S$summary
  chk <- c(value = "pooled", pooled = "pooled", mean_by_date = "mean_by_date", min = "min", median = "median",
           share_zero = "share_zero", share_full = "share_full")
  bad <- names(chk)[!vapply(names(chk), function(nm) .sd_same(.sd_num(out[[nm]]), .sd_num(es[[chk[[nm]]]])), logical(1))]
  if (length(bad)) stop(sprintf("[sd] 엔진 요약 ≠ 재도출(%s) — 진단 변조 또는 계산 불일치", paste(bad, collapse = ",")))
  c(out, list(metric_definition = "delivery_t = n_new / n_sleeve · value = δ = Σ_t n_new / Σ_t n_sleeve (풀링 · treatment_delivery 문언) · mean_by_date = 시그널일 등가중(보고)",
              basis = "바닥 보유 = 같은 실행의 슬리브 전 선정(.sl_before) — 칸 = 바닥 + 슬리브(rebalance·overlay 없음)일 때 바닥 보유와 같다",
              resolved_id = as.character(.sd_or(S$resolved_id, NA_character_)),
              exclude_rule = as.character(.sd_or(S$exclude_rule, "")),
              excluded_ids = as.character(unlist(.sd_or(S$excluded_ids, character(0)))),
              excluded_in_pool = as.character(unlist(.sd_or(S$excluded_in_pool, character(0)))),
              sleeve_kind = as.character(.sd_or(S$rule$kind, NA_character_))))
}

.sd_capcore <- function(S) {
  C <- as.data.table(S$compose)
  need <- c("Date", "n_core", "n_overlap", "n_truncated", "n_hold", "sum_core", "sum_sat")
  if (!nrow(C) || !all(need %in% names(C))) stop(sprintf("[sd] cap_core 행 열 부재: %s", paste(setdiff(need, names(C)), collapse = ",")))
  if (anyDuplicated(C$Date)) stop("[sd] cap_core 행 Date 중복")
  if (any(abs(C$sum_core + C$sum_sat - 1) > 1e-8)) stop("[sd] cap_core Σ코어 + Σ위성 ≠ 1")
  if (any(C$sum_core <= 0 | C$sum_core >= 1)) stop("[sd] cap_core Σ코어 ∉ (0,1)")
  out <- list(value = mean(C$sum_core), min = min(C$sum_core), max = max(C$sum_core), median = stats::median(C$sum_core),
              mean_overlap = mean(C$n_overlap), mean_truncated = mean(C$n_truncated), max_hold = max(C$n_hold),
              n_dates = nrow(C), k = as.integer(.sd_or(S$summary$k, NA_integer_)))
  es <- S$summary
  chk <- c(value = "mean_sum_core", min = "min_sum_core", max = "max_sum_core", mean_overlap = "mean_overlap", mean_truncated = "mean_truncated")
  bad <- names(chk)[!vapply(names(chk), function(nm) .sd_same(.sd_num(out[[nm]]), .sd_num(es[[chk[[nm]]]])), logical(1))]
  if (length(bad)) stop(sprintf("[sd] 엔진 요약 ≠ 재도출(%s) — 진단 변조 또는 계산 불일치", paste(bad, collapse = ",")))
  c(out, list(metric_definition = "value = 시그널일 평균 Σ코어(t-1 벤치 비중 근사)", satellite = as.character(.sd_or(S$summary$satellite, NA_character_))))
}

#' 원자 쓰기 — 명시 out_dir 에만(기본 경로 없음)
#' @param metric,target 주면 최상위에 싣는다(사전등록 지표 id · arm id — 소비자 .rfp_check_measurement 가 측정 객체와 대조). 빈 문자열은 거부.
sd_write <- function(res, out_dir, prefix = NULL, metric = NULL, target = NULL) {
  if (missing(out_dir) || !nzchar(out_dir)) stop("[sd] out_dir 필수 — 기본 쓰기 경로 없음")
  for (nm in c("metric", "target")) {
    v <- get(nm)
    if (!is.null(v)) {
      if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) stop(sprintf("[sd] %s 는 비어 있지 않은 문자열 하나", nm))
      res[[nm]] <- v
    }
  }
  prefix <- prefix %||% paste0("sleeve_delivery_", res$section)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(out_dir, paste0(prefix, ".json")); tmp <- file.path(out_dir, paste0(".", prefix, ".json.tmp", Sys.getpid()))
  writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null"), tmp, useBytes = TRUE)
  if (!file.rename(tmp, out)) { unlink(tmp); stop("[sd] 원자 쓰기 실패: ", out) }
  invisible(out)
}
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

cat("[sleeve_delivery.R] Loaded (", SD_VERSION, ") — sd_measure · sd_write\n", sep = "")
