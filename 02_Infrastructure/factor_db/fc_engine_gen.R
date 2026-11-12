#!/usr/bin/env Rscript
#==============================================================================
# fc_engine_gen.R — 팩터 척추 1단계(F0) 생성기: 팩터 가족 합성 엔진 14개 + 토탈 스코어 1개(자체 사양 엔진)
#   설계 04_Research/01_reports/factor_spine_design_20261111/README.md §3-1 ~ §3-4 · 결정 FACTOR-SPINE-STAGE1-20261112
#   (D1 (나) 레인 + 자체 사양 엔진 · D2 (가) P1R03 · D3 (가) 가족 14 + 토탈 1 · D5 (가) 방어 계열도 기대수익 방향 ·
#    D6 (가) 만들기는 지금 · 등록 · 측정은 판 2 시드 판정 뒤). 이 파일은 엔진을 만들기만 한다 — 등록 · 측정 없음.
#
# 무엇을 하나:
#   ① fce_members(family) — 구성원 표. 설계 §3-2 규칙 1~5 그대로 + 규칙 6 의 v0 판(아래).
#      등록부는 정본 판독기(factor_db_connector.R::.load_registry — 결합용 뷰 factor_combinable.R 의 접근자 환경)로만 읽는다.
#      성과에서 나온 표식(labels.evidence_tier · lifecycle.research_stage · factor_evidence.json 단계)과 dedup 표식은 읽지 않는다.
#   ② fce_spec(family | "total") — 사양. core(엔진을 정하는 전부 · 사양 md5 의 대상) + 문서(근거 문헌 · 규칙 메모 · 제외 목록) + 출처(입력 md5).
#   ③ fce_engine_text(spec) — 엔진 본문. core 와 사양 md5 만으로 정해진다(같은 core → 같은 바이트 · LF · UTF-8).
#      생성기 md5 · 사양 md5 를 본문에 박는다 — 엔진 md5 하나가 사양 전체를 고정한다.
#   ④ fce_write(spec, dir) — engine.R + own_spec.json. 같은 엔진(md5)이 이미 있으면 건드리지 않는다(선언 시각 보존).
#   ⑤ fce_verify(dir) — own_spec.json 에서 엔진을 다시 만들어 파일 md5 와 대조한다(손 편집 · 생성기 변경 탐지).
#   ⑥ fce_generate_all() — 15개 전부 · 엔진 md5 표.
#
# 규칙 6 의 v0 판(PIT 우선 · 설계 §3-2 규칙 6 '중복 군집마다 하나만'을 바꾼다):
#   등록부 dedup · retired_dedup 표식(상관 · 군집 스캔 = 전기간 통계 측정)은 구성원 규칙에 쓰지 않는다 —
#   전기간 상관으로 구성원을 고르면 .claude/rules/pit.md C1 · C14 에 걸린다. 빼는 것은 '정의상 별칭'뿐이다:
#   같은 가족 · 같은 data_source · 같은 update_freq 안에서
#     (F) definition 문장 전체가 같다(공백 · 대소문자만 정규화)
#     (D) definition 이 다른 구성원을 'alias of <id>' · 'identical to <id>' 로 선언한다(id 전체 또는 유일한 id 접두)
#   정의로 판별할 수 없으면 빼지 않는다(F0-2 중복 재스캔은 하지 않는다).
#   묶음마다 남기는 하나 = factor id 사전순 첫째(C 로캘 정렬) — 성과를 읽지 않는 기계 규칙. 등록부 dedup.canonical · reason 같은
#   표식(전기간 통계에서 나온 근거가 섞여 있다)은 남길 쪽을 정하는 데도 쓰지 않는다(판단 Superfan T1 참고 C-20261112-007).
#   적용 범위 = 가족 안(가족 점수 = 가족 안 평균). 가족을 넘는 같은 정의는 남기고 규칙 메모에 적는다(설계 §9 '가족 구분의 겹침').
#
# 쓰기(저장소 루트에서): Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write [--out DIR]
#                       Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --dry-run   (쓰지 않고 md5 표만)
#   --out = 전략 폴더들의 부모(기본 04_Research/strategies). source() 하면 함수만 싣는다.
#   생성 엔진은 손으로 고치지 않는다 — 이 파일을 고치고 다시 만든다(생성기 md5 가 엔진에 박혀 모든 엔진이 다시 선언된다).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

FCE_RULE      <- "fce_rule_v0"
FCE_SCHEMA    <- "fc_own_spec_v0"
FCE_DECISION  <- "FACTOR-SPINE-STAGE1-20261112"
FCE_DESIGN    <- "04_Research/01_reports/factor_spine_design_20261111/README.md"
FCE_GEN_REL   <- "02_Infrastructure/factor_db/fc_engine_gen.R"
FCE_OUT_REL   <- "04_Research/strategies"
FCE_TOTAL_ID  <- "FC_TOTAL_EW"
## 가족 14개 — 설계 §3-1 표의 순서(결정 D3 (가)). 토탈 v0 는 이 순서의 가족 점수를 평균한다.
FCE_FAMILIES  <- c("quality", "defense", "liquidity", "momentum", "accrual", "value", "growth", "investor_flow",
                   "risk", "crowding", "consensus", "technical", "regime", "leverage")
FCE_LEFT_OUT  <- c(size   = "설계 §3-1 — 규칙 적용 뒤 구성원 1개라 합성이 아니다(결정 D3 (가) 가족 14 + 토탈 1)",
                   custom = "설계 §3-1 — 논문 엔진 동결 패널 2건이라 자체 사양이 아니다(결정 D3 (가) 가족 14 + 토탈 1)")
FCE_DEF_FAMILIES <- c("defense", "risk", "liquidity", "regime")      # 설계 §3-2 '방향' · 결정 D5 (가)
## 설계 §3-1 표의 구성원 초안 수(11-11 등록부 · 규칙 6 원안 = 통계 dedup 표식 사용) — 비교 기록용(규칙 입력 아님)
FCE_DESIGN_DRAFT_N <- c(quality = 42L, defense = 36L, liquidity = 36L, momentum = 27L, accrual = 20L, value = 19L, growth = 17L,
                        investor_flow = 15L, risk = 13L, crowding = 13L, consensus = 12L, technical = 12L, regime = 8L, leverage = 5L)
FCE_START_RULE <- "rp_start_date_else_measurement_axis_active_epoch_start_date"
FCE_READ <- list(direction = "registry", missing = "na", dedup = FALSE, family = TRUE)   # 설계 §3-3 읽기 경로(엔진 본문의 호출과 같아야 한다)
FCE_PROBE_DATE <- as.Date("2022-12-31")   # 생성 때 뷰 판 · 부호 대조용 한 달(τ_D 달 · 팩터 값 대조뿐 — 성과를 읽지 않는다)
FCE_ALIAS_RX <- "(?i)\\b(?:alias of|identical to)\\s+([A-Za-z][A-Za-z0-9_]*)"
## 근거 문헌 — 설계 §3-2 표(원문 링크 = 설계 §10 · 11-11 확인)
FCE_LIT <- list(
  list(use = "transform", rule = "매 시점 횡단면 순위 → [−1, 1] · 동순위 평균(결합용 뷰 저장 변환 · factor_combinable.json transform)",
       ref = "Gu, Kelly & Xiu (2020) Empirical Asset Pricing via Machine Learning, RFS 33(5):2223-2273",
       url = "https://doi.org/10.1093/rfs/hhaa009"),
  list(use = "family_score", rule = "가족 구성원 중 값이 있는 것의 평균 · 하나도 없으면 결측",
       ref = "Asness, Frazzini & Pedersen (2019) Quality Minus Junk, RAS 24(1):34-112",
       url = "https://doi.org/10.1007/s11142-018-9470-2"),
  list(use = "family_score", rule = "팩터를 주제로 묶어 평균",
       ref = "Jensen, Kelly & Pedersen (2023) Is There a Replication Crisis in Finance?, JF 78(5):2465-2518",
       url = "https://doi.org/10.1111/jofi.13249"),
  list(use = "total_v0", rule = "가족 점수 중 값이 있는 것의 평균(가족 균형 등가중) — 같은 규칙을 한 층 위에 적용",
       ref = "Asness, Frazzini & Pedersen (2019) · Jensen, Kelly & Pedersen (2023)(위 두 편)",
       url = "https://doi.org/10.1111/jofi.13249"),
  list(use = "missing", rule = "점수가 결측인 종목은 그날 패널에서 뺀다(0 으로 채우지 않는다)",
       ref = "06_Registry/factor_combinable.json missing.options 의 'na'", url = NULL))
FCE_ROOT_PAPER <- list(url = "https://doi.org/10.1111/jofi.13249", title = "Is There a Replication Crisis in Finance?")

## ── 작은 도구 ────────────────────────────────────────────────────────────────
fce_root <- function() {
  # 순서 = CLAUDE_PROJECT_DIR → QM_ROOT(결합용 뷰 fc_root 와 같다 · 루트를 지어내지 않는다)
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[fce] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
}
.fce_md5_file <- function(p) unname(as.character(tools::md5sum(p)))
.fce_md5_text <- function(s) {
  tf <- tempfile("fce_"); on.exit(unlink(tf), add = TRUE)
  writeBin(charToRaw(enc2utf8(s)), tf)
  .fce_md5_file(tf)
}
.fce_write_text <- function(text, path) {                      # 원자적 쓰기 · LF 그대로(텍스트 모드 변환 없음)
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  writeBin(charToRaw(enc2utf8(text)), tmp)
  if (file.exists(path) && !file.remove(path)) { unlink(tmp); stop("[fce] 기존 파일 제거 실패: ", path) }
  if (!file.rename(tmp, path)) { unlink(tmp); stop("[fce] 이름 바꾸기 실패: ", path) }
  invisible(path)
}
.fce_json <- function(x) paste0(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), "\n")
.fce_core_json <- function(core) as.character(toJSON(core, auto_unbox = TRUE, digits = NA, null = "null", na = "null"))
.fce_str <- function(x) { v <- unlist(x); if (is.null(v) || !length(v)) NA_character_ else paste(as.character(v), collapse = " ") }
.fce_norm <- function(s) gsub("\\s+", " ", trimws(tolower(s)))
.fce_sort <- function(x) sort(x, method = "radix")             # 로캘 무관 정렬(C 로캘 순서)

.FCE <- new.env(parent = emptyenv())
.fce_fc <- function(root) {                                    # 결합용 뷰 모듈(함수만 · CLI 블록은 sys.source 에서 돌지 않는다)
  if (!is.null(.FCE$fc) && identical(.FCE$root, root)) return(.FCE$fc)
  e <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure", "factor_db", "factor_combinable.R"), envir = e, keep.source = FALSE)
  .FCE$fc <- e; .FCE$root <- root
  e
}

## ── 입력 — 등록부(정본 판독기) · 패널 축 · PIT 격리 · 결합용 뷰 판 ─────────────────
fce_inputs <- function(root = fce_root()) {
  gp <- file.path(root, FCE_GEN_REL)
  if (!file.exists(gp)) stop("[fce] 생성기 파일이 정본 경로에 없다: ", gp)
  rp <- file.path(root, "02_Infrastructure", "factor_db", "factor_registry.json")
  if (!file.exists(rp)) stop("[fce] 등록부 없음: ", rp)
  m0 <- .fce_md5_file(rp)
  FC <- .fce_fc(root)
  E <- FC$.fc_env(root)                                        # config.R · factor_db_connector.R · factor_dup_scan.R
  cand <- unique(c(file.path(E$FUNC_PATH, "factor_db", "factor_registry.json"), file.path(E$.fdc_self_dir, "factor_registry.json"),
                   E$FACTOR_REG_PATH))
  used <- cand[file.exists(cand)][1]
  if (is.na(used) || !identical(normalizePath(used, winslash = "/"), normalizePath(rp, winslash = "/")))
    stop("[fce] 정본 판독기가 읽는 등록부(", used, ")가 ", rp, " 와 다르다")
  reg <- E$.load_registry()
  if (!identical(m0, .fce_md5_file(rp))) stop("[fce] 등록부가 판독 중에 바뀌었다 — 다시 돌릴 것: ", rp)
  if (!is.list(reg) || !length(reg)) stop("[fce] 등록부 판독 실패")
  ids <- names(reg)
  if (any(!grepl("^[A-Za-z0-9_]+$", ids))) stop("[fce] id 형식 밖 등록부 항목: ", paste(utils::head(ids[!grepl("^[A-Za-z0-9_]+$", ids)], 5), collapse = ","))
  ## 패널 축(파생 사이드카 · 표본 달 횡단면 고유값 관측 — 성과 아님)
  ax_p <- file.path(root, "06_Registry", "factor_panel_axis.json")
  AX <- fromJSON(ax_p, simplifyVector = FALSE)
  if (!identical(AX[["schema"]], "factor_panel_axis_v1")) stop("[fce] factor_panel_axis.json schema 밖: ", .fce_str(AX[["schema"]]))
  ## PIT 격리 목록(정본 판독기)
  qe <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure", "validation", "pit_quarantine.R"), envir = qe, keep.source = FALSE)
  qids <- qe$pitq_factor_ids(root); q_p <- qe$pitq_path(root)
  ## 결합용 뷰 — 설정 정본 + 저장본 판(정본 접근자로 한 달 읽어 빌더 판 · 부호표를 본다 · 저장본 직접 읽기 없음)
  cfg <- FC$fc_config(root)
  pr <- NULL
  invisible(utils::capture.output(pr <- FC$fc_load_month(FCE_PROBE_DATE, direction = "registry", factors = NULL, missing = "na",
                                                         dedup = FALSE, family = FALSE, root = root)))
  if (!identical(pr$info$builder, FC$FC_BUILDER))
    stop(sprintf("[fce] 결합용 뷰 저장본 빌더(%s) ≠ 코드 빌더(%s) — 뷰를 다시 지은 뒤 생성할 것", .fce_str(pr$info$builder), FC$FC_BUILDER))
  g1 <- function(x, k) .fce_str(x[[k]])
  T <- data.table(id = ids,
                  category    = vapply(reg, g1, "", k = "category"),
                  status      = vapply(reg, function(x) .fce_str((x[["lifecycle"]] %||% list())[["status"]]), ""),
                  definition  = vapply(reg, g1, "", k = "definition"),
                  data_source = vapply(reg, g1, "", k = "data_source"),
                  update_freq = vapply(reg, g1, "", k = "update_freq"),
                  direction   = vapply(reg, g1, "", k = "direction"),
                  rp          = vapply(reg, function(x) !is.null(x[["release_pending"]]), TRUE),
                  rp_status   = vapply(reg, function(x) { r <- x[["release_pending"]]; if (is.null(r)) NA_character_ else .fce_str(r[["status"]] %||% "present") }, ""))
  T[, axis := vapply(id, function(f) { a <- AX[["factors"]][[f]]; if (is.null(a)) NA_character_ else .fce_str(a[["panel_axis"]]) }, "")]
  T[, quarantined := id %in% qids]
  ## 부호 = 결합용 뷰 .fc_reg_signs 와 같은 규칙(lower_better → −1 · 그 밖 → +1)
  T[, s_reg := fifelse(!is.na(direction) & direction == "lower_better", -1L, 1L)]
  T[, fail := fifelse(is.na(status) | status != "active", "R2_lifecycle_status",
              fifelse(is.na(axis) | axis != "cross_sectional", "R3_panel_axis",
              fifelse(quarantined, "R4_pit_quarantine",
              fifelse(rp, "R5_release_pending", NA_character_))))]
  T[, fail_detail := fcase(fail == "R2_lifecycle_status", paste0("lifecycle.status = ", fifelse(is.na(status), "(없음)", status)),
                           fail == "R3_panel_axis", paste0("panel_axis = ", fifelse(is.na(axis), "(판정 없음)", axis)),
                           fail == "R4_pit_quarantine", "06_Registry/pit_quarantine.json 효력 항목",
                           fail == "R5_release_pending", paste0("release_pending.status = ", rp_status),
                           default = NA_character_)]
  list(root = root, reg_ids = ids, T = T,
       generator = list(path = FCE_GEN_REL, md5 = .fce_md5_file(gp)),
       registry = list(path = "02_Infrastructure/factor_db/factor_registry.json", md5 = m0,
                       mtime = format(file.info(rp)$mtime, "%Y-%m-%dT%H:%M:%S"), n_entries = length(ids),
                       reader = "factor_db_connector.R::.load_registry (factor_combinable.R .fc_env 경유)",
                       note = "작업 트리 판 — 미커밋 변경이 있으면 그것까지 포함한 바이트의 md5"),
       panel_axis = list(path = "06_Registry/factor_panel_axis.json", md5 = .fce_md5_file(ax_p), generated_at = .fce_str(AX[["generated_at"]]),
                         sample_months = .fce_str(AX[["sample_months"]])),
       pit_quarantine = list(path = "06_Registry/pit_quarantine.json", md5 = if (file.exists(q_p)) .fce_md5_file(q_p) else NA_character_,
                             reader = "02_Infrastructure/validation/pit_quarantine.R::pitq_factor_ids", ids = as.list(.fce_sort(qids))),
       view = list(builder = pr$info$builder, cfg_path = "06_Registry/factor_combinable.json", cfg_version = cfg$version,
                   cfg_md5 = .fce_md5_file(file.path(root, "06_Registry", "factor_combinable.json")), transform = cfg$transform$rule,
                   family_composite = cfg$family$composite, probe_date = format(FCE_PROBE_DATE), probe_asof = pr$info$asof),
       probe_meta = as.data.table(pr$meta)[, .(Factor_Name, view_s_reg = s_reg, view_category = category)])
}

## ── 규칙 6 의 v0 판 — 정의상 별칭 ───────────────────────────────────────────
.fce_resolve <- function(tok, all_ids) {
  if (tok %in% all_ids) return(tok)
  p <- all_ids[sub("_.*$", "", all_ids) == tok]
  if (length(p) == 1L) p else NA_character_
}
## 후보(규칙 1~5 통과) C 안에서 (F) 정의 문장 동일 쌍 · (D) 선언 간선을 찾는다. same_family = FALSE 면 가족을 넘는 것만.
.fce_alias_links <- function(C, all_ids, same_family = TRUE) {
  C <- copy(C)[, key := paste(data_source, update_freq, sep = "\r")][, ndef := .fce_norm(definition)]
  L <- list()
  ## (F) 같은 키 · 같은 정규화 정의
  for (g in split(C, by = c("key", "ndef"))) if (nrow(g) > 1L) {
    ids <- .fce_sort(g$id)
    for (a in ids[-1]) {
      b <- ids[1]
      if (same_family == (C[id == a]$category == C[id == b]$category))
        L[[length(L) + 1L]] <- data.table(from = a, to = b, basis = "F",
                                          phrase = substr(g$definition[1], 1L, 160L))
    }
  }
  ## (D) definition 의 'alias of <id>' · 'identical to <id>' 선언
  for (i in seq_len(nrow(C))) {
    m <- regmatches(C$definition[i], gregexpr(FCE_ALIAS_RX, C$definition[i], perl = TRUE))[[1]]
    for (ph in m) {
      to <- .fce_resolve(sub(FCE_ALIAS_RX, "\\1", ph, perl = TRUE), all_ids)
      if (is.na(to) || identical(to, C$id[i]) || !(to %in% C$id)) next
      if (!identical(C[id == to]$key, C$key[i])) next
      if (same_family != identical(C[id == to]$category, C$category[i])) next
      L[[length(L) + 1L]] <- data.table(from = C$id[i], to = to, basis = "D", phrase = ph)
    }
  }
  if (length(L)) unique(rbindlist(L), by = c("from", "to", "basis")) else data.table(from = character(0), to = character(0), basis = character(0), phrase = character(0))
}
## 한 가족의 별칭 묶음 → 남길 것 · 뺄 것
.fce_alias_drop <- function(C, all_ids) {
  E <- .fce_alias_links(C, all_ids, same_family = TRUE)
  if (!nrow(E)) return(data.table(id = character(0), keep = character(0), basis = character(0), detail = character(0)))
  nodes <- .fce_sort(unique(c(E$from, E$to)))
  lab <- setNames(seq_along(nodes), nodes)
  repeat {                                                      # 연결 요소(작은 그래프 · 단순 반복)
    ch <- FALSE
    for (k in seq_len(nrow(E))) {
      a <- E$from[k]; b <- E$to[k]; m <- min(lab[[a]], lab[[b]])
      if (lab[[a]] != m || lab[[b]] != m) { lab[lab == lab[[a]] | lab == lab[[b]]] <- m; ch <- TRUE }
    }
    if (!ch) break
  }
  out <- list()
  for (comp in split(names(lab), lab)) {
    keep <- .fce_sort(comp)[1]                                  # 남길 쪽 = id 사전순 첫째(성과 · dedup 표식을 읽지 않는 기계 규칙)
    for (d in .fce_sort(setdiff(comp, keep))) {
      r <- C[id == d]
      ed <- E[from == d | to == d]
      txt <- paste(vapply(seq_len(nrow(ed)), function(j) {
        if (ed$basis[j] == "D") sprintf("(D) %s 의 definition 이 '%s' 로 선언", ed$from[j], ed$phrase[j])
        else sprintf("(F) %s 와 %s 의 definition 문장 전체가 같다('%s')", ed$from[j], ed$to[j], ed$phrase[j])
      }, ""), collapse = " · ")
      out[[length(out) + 1L]] <- data.table(id = d, keep = keep, basis = paste(.fce_sort(unique(ed$basis)), collapse = "+"),
                                            detail = sprintf("%s · data_source %s · update_freq %s 같음 → %s 를 남긴다",
                                                             txt, r$data_source, r$update_freq, keep))
    }
  }
  rbindlist(out)
}

## ── 구성원 표 ────────────────────────────────────────────────────────────────
fce_members <- function(family, inputs = fce_inputs()) {
  T <- inputs$T
  if (!family %in% T$category) stop("[fce] 등록부에 없는 가족: ", family)
  A <- T[category == family]
  C <- A[is.na(fail)]
  D <- .fce_alias_drop(C, inputs$reg_ids)
  M <- C[!(id %in% D$id)]
  M <- M[order(match(id, .fce_sort(id)))]
  ex <- rbind(A[!is.na(fail), .(id, rule = fail, detail = fail_detail)],
              if (nrow(D)) D[, .(id, rule = "R6_definitional_alias", detail)] else NULL)
  if (nrow(ex)) ex <- ex[order(match(id, .fce_sort(id)))]
  list(family = family, n_registry = nrow(A), n_after_rules_1_5 = nrow(C),
       members = M[, .(id, s_reg, family = category, data_source, update_freq)],
       excluded = ex, aliases = D)
}

## 가족을 넘는 정의상 같은 구성원(남긴다 · 메모용)
.fce_cross_family <- function(inputs) {
  T <- inputs$T
  C <- T[category %in% FCE_FAMILIES & is.na(fail)]
  ## 가족 안 별칭으로 빠진 것은 제외하고 본다
  drop <- unlist(lapply(FCE_FAMILIES, function(f) .fce_alias_drop(C[category == f], inputs$reg_ids)$id))
  C <- C[!(id %in% drop)]
  X <- .fce_alias_links(C, inputs$reg_ids, same_family = FALSE)
  if (!nrow(X)) return(X[, .(from, to, basis, phrase, from_family = character(0), to_family = character(0))])
  X[, `:=`(from_family = C$category[match(from, C$id)], to_family = C$category[match(to, C$id)])]
  X[]
}

## ── 사양 ────────────────────────────────────────────────────────────────────
.fce_common_notes <- function(inputs) c(
  "구성원 규칙 fce_rule_v0 = 설계 §3-2 규칙 1~5 그대로 — ① 등록부 category = 가족 ② lifecycle.status = active ③ factor_panel_axis.json panel_axis = cross_sectional ④ PIT 격리 목록(pit_quarantine.R::pitq_factor_ids) 밖 ⑤ release_pending 표식 없음 — 에 규칙 6 의 v0 판을 더한다.",
  "규칙 6(v0 · PIT 우선 — 설계 원안 '중복 군집마다 하나만'을 바꿈): 등록부 dedup · retired_dedup 표식(2026-08-02 · 08-09 상관 · 군집 스캔 = 전기간 통계 측정)은 읽지 않았다. 전기간 상관으로 구성원을 고르면 pit.md C1 · C14 에 걸린다. 빼는 것은 정의상 별칭뿐 — 같은 가족 · 같은 data_source · 같은 update_freq 안에서 (F) definition 문장 전체가 같거나(공백 · 대소문자 정규화) (D) definition 이 다른 구성원을 'alias of <id>' · 'identical to <id>' 로 선언한 것. 정의로 판별할 수 없으면 빼지 않았다. F0-2(수리 뒤 중복 재스캔)는 하지 않았다.",
  "별칭 묶음에서 남기는 하나 = factor id 사전순 첫째(C 로캘 정렬) — 성과를 읽지 않는 기계 규칙이다. 등록부 dedup.canonical · reason 같은 표식(전기간 통계에서 나온 근거가 섞여 있다)은 남길 쪽을 정하는 데도 쓰지 않았다(판단 Superfan T1 참고 C-20261112-007).",
  "적용 범위 = 가족 안(가족 점수 = 가족 안 평균). 가족을 넘어 정의가 같은 구성원은 남겼다 — 그런 쌍은 해당 사양의 메모에 적는다.",
  "성과에서 나온 표식(labels.evidence_tier · lifecycle.research_stage · factor_evidence.json 단계)은 읽지 않았다(C1 · C14).",
  "방향 = 등록부 기대수익 방향 direction(lower_better → s_reg −1 · 그 밖 → +1 — 결합용 뷰 .fc_reg_signs 와 같은 규칙). 엔진은 direction = \"registry\" 상수로 읽고, 실행 때 뷰 메타의 s_reg · category · 빌더 판이 선언과 다르면 멈춘다 — 등록부 방향 · 가족이 바뀌면 새 사양으로 다시 선언한다.",
  sprintf("패널 축 판정 = factor_panel_axis.json(%s 생성 · 표본 달 %s 의 횡단면 고유값 관측 — 구조 판정이지 성과가 아니다).",
          inputs$panel_axis$generated_at, inputs$panel_axis$sample_months),
  sprintf("구성원 수는 이 등록부 판(md5 %s · %s)에 규칙을 다시 적용해 낸 값이다. 설계 §3-1 초안 수는 통계 dedup 표식을 쓴 규칙 6 원안 기준이라 다르다.",
          inputs$registry$md5, inputs$registry$mtime))

.fce_member_core <- function(M) lapply(seq_len(nrow(M)), function(i) list(id = M$id[i], s_reg = as.integer(M$s_reg[i]), family = M$family[i]))

.fce_view_check <- function(M, inputs) {                       # 생성 때 대조(τ_D 달 뷰 메타 vs 선언 부호 · 가족)
  P <- merge(M[, .(Factor_Name = id, s_reg, family)], inputs$probe_meta, by = "Factor_Name")
  bad <- P[view_s_reg != s_reg | view_category != family]
  list(probe_date = inputs$view$probe_date, probe_asof = inputs$view$probe_asof, n_checked = nrow(P), n_not_in_probe_month = nrow(M) - nrow(P),
       mismatches = if (nrow(bad)) lapply(seq_len(nrow(bad)), function(i) as.list(bad[i])) else list())
}

fce_spec <- function(target, inputs = fce_inputs()) {
  is_total <- identical(target, "total")
  if (!is_total && !target %in% FCE_FAMILIES) stop("[fce] 대상은 가족 14개 또는 'total': ", target)
  fams <- if (is_total) FCE_FAMILIES else target
  per <- lapply(fams, fce_members, inputs = inputs); names(per) <- fams
  M <- rbindlist(lapply(per, `[[`, "members"))
  if (!nrow(M)) stop("[fce] 구성원 0: ", target)
  sid <- if (is_total) FCE_TOTAL_ID else paste0("FC_FAM_", target)
  core <- list(spec_id = sid, kind = if (is_total) "total" else "family", families = as.list(fams), rule_version = FCE_RULE,
               generator_md5 = inputs$generator$md5, view_builder = inputs$view$builder, view_cfg_version = inputs$view$cfg_version,
               read = FCE_READ, start_rule = FCE_START_RULE, members = .fce_member_core(M))
  spec_md5 <- .fce_md5_text(.fce_core_json(core))
  X <- .fce_cross_family(inputs)
  Xf <- if (is_total) X else X[from_family == target | to_family == target]
  notes <- .fce_common_notes(inputs)
  if (!is_total) {
    pf <- per[[target]]
    notes <- c(notes, sprintf("가족 %s: 등록부 %d → 규칙 1~5 뒤 %d → 정의상 별칭 %d 제외 → 구성원 %d (설계 §3-1 초안 %d).",
                              target, pf$n_registry, pf$n_after_rules_1_5, nrow(pf$aliases), nrow(M), FCE_DESIGN_DRAFT_N[[target]]))
    if (nrow(pf$aliases)) notes <- c(notes, sprintf("정의상 별칭 제외 %s — %s", pf$aliases$id, pf$aliases$detail))
    else notes <- c(notes, "정의상 별칭 제외 없음 — 등록부 정의 필드로 같은 식 · 같은 원천이라 판별되는 구성원 쌍이 이 가족에 없다(통계로만 겹치는 쌍은 남겼다).")
    if (target %in% FCE_DEF_FAMILIES)
      notes <- c(notes, "방어 계열 가족도 1단계에서는 기대수익 방향(direction = \"registry\")으로 잰다 — 결정 D5 (가) · 방어 방향(direction = \"defensive\") 판은 P2 상설 판 뒤.")
  } else {
    cnt <- vapply(per, function(p) nrow(p$members), 1L)
    notes <- c(notes,
      "토탈 v0 = 종목마다 가족 점수 14개 가운데 값이 있는 것의 평균(가족 균형 등가중 · 전부 결측이면 뺀다). 가족 점수는 가족 엔진 FC_FAM_<가족> 과 같은 값이다(같은 구성원 · 같은 접근자 인자 · 가족 점수 = 결합용 뷰 fc_family_scores).",
      sprintf("가족별 구성원: %s · 합 %d.", paste(sprintf("%s %d", names(cnt), cnt), collapse = " · "), sum(cnt)),
      "2000년대 초에는 재무 계열 가족의 구성원이 적고 accrual · leverage(2000-05) · consensus(2001-06)는 늦게 생긴다 — 그 전에는 가격 계열 가족이 평균의 대부분이다(설계 §3-1). PIT 문제는 아니지만 구성이 시간에 따라 달라진다 — 보고에 적는다(달마다 있는 가족 수 = fce_diag.csv n_families_present).",
      sprintf("빠진 계열: %s.", paste(sprintf("%s(%s · v0 규칙 적용 시 구성원 %d)", names(FCE_LEFT_OUT), FCE_LEFT_OUT,
                                             vapply(names(FCE_LEFT_OUT), function(f) if (f %in% inputs$T$category) nrow(fce_members(f, inputs)$members) else 0L, 1L)),
                                     collapse = " · ")))
  }
  if (nrow(Xf)) notes <- c(notes, sprintf("가족을 넘는 정의상 같은 구성원은 남겼다(규칙 6 v0 의 적용 범위 = 가족 안 · 토탈에서는 그 양이 두 가족에 한 번씩 들어간다 — 설계 §9 '가족 구분의 겹침'): %s.",
                                          paste(sprintf("%s(%s) ↔ %s(%s) [%s: %s]", Xf$from, Xf$from_family, Xf$to, Xf$to_family, Xf$basis, Xf$phrase), collapse = " · ")))
  excluded <- if (is_total) {
    lapply(names(FCE_LEFT_OUT), function(f) list(family = f, rule = "left_out_family", detail = FCE_LEFT_OUT[[f]]))
  } else {
    ex <- per[[target]]$excluded
    if (nrow(ex)) lapply(seq_len(nrow(ex)), function(i) list(id = ex$id[i], rule = ex$rule[i], detail = ex$detail[i])) else list()
  }
  list(schema = FCE_SCHEMA, spec_id = sid, spec_md5 = spec_md5, core = core,
       n_members = nrow(M),
       n_members_by_family = as.list(vapply(per, function(p) nrow(p$members), 1L)),
       design_draft_n_members = if (is_total) sum(FCE_DESIGN_DRAFT_N) else FCE_DESIGN_DRAFT_N[[target]],
       family_root = paste0("FC:", if (is_total) "total" else target),
       root_paper = c(FCE_ROOT_PAPER, list(paper_key = sid)),
       literature = FCE_LIT,
       composite = list(transform = inputs$view$transform, family_score = inputs$view$family_composite,
                        total = if (is_total) "mean_of_available_family_scores" else NULL, missing = "drop_ticker_date (fc_load_month missing = na)"),
       output = "FACTORS(Date, Ticker, Score) — Date = 결합용 뷰의 그 달 as-of · 점수 결측 종목 제외 · PORTFOLIO 없음",
       rule_notes = as.list(notes),
       excluded = excluded,
       view_check = .fce_view_check(M, inputs),
       decision = FCE_DECISION, design = FCE_DESIGN,
       generator = inputs$generator,
       inputs = list(registry = inputs$registry, panel_axis = inputs$panel_axis, pit_quarantine = inputs$pit_quarantine, view = inputs$view),
       engine = list(path = file.path(FCE_OUT_REL, sid, "engine.R"), md5 = NA_character_),
       declared_at = NA_character_)
}

## ── 엔진 본문 ────────────────────────────────────────────────────────────────
## 본문 규약(정적 검사 · PIT 스캔이 엔진 파일만 보고 판정하도록): 데이터 접근 = fc_load_month 호출 한 곳(방향 인자 = 문자열 상수) ·
##   팩터 DB · 결합용 뷰 저장본 경로 없음 · IC · 부호 층 함수 없음 · 'sig' 라는 글자를 쓰지 않는다(lookahead_detector INV13 · C14 문맥 패턴이
##   투자자 수급 구성원 id 둘레에서 'Date … sig' 를 찾는다) · 본문은 core 와 사양 md5 로만 정해진다.
FCE_TPL_HEAD <- r"---[## @@SPEC_ID@@ — @@TITLE@@ (자체 사양 엔진 · 팩터 척추 1단계 F0)
## ★생성기 산출 — 손으로 고치지 않는다. 다시 만들기(저장소 루트): Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write
##   생성기 md5 @@GEN_MD5@@ · 사양 md5 @@SPEC_MD5@@ · 규칙 판 @@RULE@@ · 사양 원문 = 같은 폴더 own_spec.json
##   결정 FACTOR-SPINE-STAGE1-20261112 · 팩터 척추 설계안 §3(문서 경로 = own_spec.json)
@@WHAT@@
##   결합용 뷰 점수 = 매 시점 횡단면 순위 [−1, 1](동순위 평균) × 등록부 기대수익 방향
##     — Gu, Kelly & Xiu (2020) RFS 33(5) https://doi.org/10.1093/rfs/hhaa009
##   평균 규칙 = Asness, Frazzini & Pedersen (2019) RAS 24(1) https://doi.org/10.1007/s11142-018-9470-2
##     · Jensen, Kelly & Pedersen (2023) JF 78(5) https://doi.org/10.1111/jofi.13249
##   결측 종목은 그 날 패널에서 뺀다(0 으로 채우지 않는다 · 06_Registry/factor_combinable.json missing 선택지 na)
## 계약: 입력 = RAWDATA(거래일 달력 — Date 열만 쓴다) · .RP_START_DATE(없으면 측정 축 정본의 활성 epoch 시작일)
##   출력 = FACTORS(Date, Ticker, Score) 만 · 날짜 = 결합용 뷰의 그 달 as-of(월말 거래일 — 셀 경로 달 스냅에서 항등)
##   as-of 가 시작일 이후인 달만 · 패널 마지막 달을 뷰가 아직 못 따라왔으면 그 달만 뺀다(그 달은 뒤 수익이 없다)
## PIT: 팩터 값은 정본 접근자 fc_load_month 한 길로만 읽는다(C15) · 방향 인자 = 문자열 상수 registry(C13 · 수동 반전 없음)
##   · IC 를 읽지 않는다(C1 · C14) · 재무 시차는 팩터 DB 가 이미 적용한 값만 쓴다(C4)
##   · 구성원 · 부호(s_reg) · 가족 · 뷰 빌더 판은 선언 때 고정 — 실행 때 뷰 메타와 다르면 멈춘다(새 사양으로 다시 선언)
## 진단(판정 입력 아님): 날짜별 구성원 수 · 점수 범위 · 종목별 유효 수(@@VALID_WHAT@@) 분포
##   → 이 폴더 fce_diag.csv(options(fce.diag_dir) 로 바꾼다 · 폴더가 없으면 쓰지 않는다)
.FCE_SPEC_ID <- "@@SPEC_ID@@"
.FCE_KIND <- "@@KIND@@"
.FCE_FAMILIES <- c(@@FAMILIES@@)
.FCE_RULE <- "@@RULE@@"
.FCE_GEN_MD5 <- "@@GEN_MD5@@"
.FCE_SPEC_MD5 <- "@@SPEC_MD5@@"
.FCE_VIEW_BUILDER <- "@@VIEW_BUILDER@@"
## 구성원(선언 때 고정) — id · 등록부 기대수익 부호 s_reg · 가족(등록부 category)
.FCE_M <- matrix(ncol = 3L, byrow = TRUE, data = c(
@@MEMBER_LINES@@
))
.FCE_MEMBERS <- data.frame(id = .FCE_M[, 1L], s_reg = as.integer(.FCE_M[, 2L]), family = .FCE_M[, 3L], stringsAsFactors = FALSE)
if (nrow(.FCE_MEMBERS) != @@N@@L || anyDuplicated(.FCE_MEMBERS$id) > 0L || !all(.FCE_MEMBERS$s_reg %in% c(-1L, 1L)) ||
    !all(.FCE_MEMBERS$family %in% .FCE_FAMILIES))
  stop("[@@SPEC_ID@@] 구성원 표가 선언과 다르다 — 생성기로 다시 만들 것(손 편집 금지)")
.fce_root <- local({
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[@@SPEC_ID@@] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
})
.fce_fc <- new.env(parent = globalenv())
sys.source(file.path(.fce_root, "02_Infrastructure", "factor_db", "factor_combinable.R"), envir = .fce_fc, keep.source = FALSE)
.fce_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else local({
  e <- new.env(parent = globalenv())
  sys.source(file.path(.fce_root, "02_Infrastructure", "contracts", "measurement_axis.R"), envir = e, keep.source = FALSE)
  as.Date(e$ma_epoch(root = .fce_root)$start_date)
})
if (length(.fce_start) != 1L || is.na(.fce_start)) stop("[@@SPEC_ID@@] 측정 시작일을 읽지 못했다")
if (!exists("RAWDATA")) stop("[@@SPEC_ID@@] RAWDATA 없음 — 셀 경로 · 러너가 넘기는 패널(거래일 달력)이 필요하다")
.fce_cal <- sort(unique(as.Date(RAWDATA[["Date"]])))
.fce_me <- .fce_cal[!duplicated(format(.fce_cal, "%Y%m"), fromLast = TRUE)]
.fce_me <- .fce_me[.fce_me >= .fce_start]
if (!length(.fce_me)) stop(sprintf("[%s] 시작일 %s 뒤 월말 거래일이 패널에 없다", .FCE_SPEC_ID, format(.fce_start)))
.fce_rows <- list(); .fce_dg <- list()
for (.fce_i in seq_along(.fce_me)) {
  .fce_d <- .fce_me[.fce_i]
  .fce_r <- NULL
  invisible(utils::capture.output(.fce_r <- tryCatch(
    .fce_fc$fc_load_month(.fce_d, direction = "registry", factors = .FCE_MEMBERS$id, missing = "na", dedup = FALSE, family = TRUE),
    error = function(e) e)))
  if (inherits(.fce_r, "error")) {
    .fce_em <- conditionMessage(.fce_r)
    if (.fce_i == length(.fce_me) && (grepl("결합용 뷰에 그 달이 없다", .fce_em, fixed = TRUE) || grepl("보다 이르다", .fce_em, fixed = TRUE))) {
      cat(sprintf("[%s] 패널 마지막 달 %s 은 뺀다 — 결합용 뷰가 패널 끝을 아직 못 따라왔다(그 달은 뒤 수익이 없다): %s\n",
                  .FCE_SPEC_ID, format(.fce_d, "%Y-%m"), .fce_em))
      next
    }
    stop(.fce_r)
  }
  .fce_in <- .fce_r$info
  if (!identical(.fce_in$builder, .FCE_VIEW_BUILDER) || !identical(.fce_in$direction, "registry") || !identical(.fce_in$missing, "na") ||
      !identical(.fce_in$dedup, FALSE) || !identical(.fce_in$rerank_within_tickers, FALSE))
    stop(sprintf("[%s] 결합용 뷰 판 · 읽기 인자가 선언과 다르다(뷰 %s · 선언 %s) — 사양을 다시 선언할 것", .FCE_SPEC_ID,
                 as.character(.fce_in$builder)[1], .FCE_VIEW_BUILDER))
  .fce_asof <- as.Date(.fce_in$asof)
  if (.fce_asof < .fce_start) next
  .fce_m <- .fce_r$meta
  .fce_k <- match(.fce_m$Factor_Name, .FCE_MEMBERS$id)
  .fce_ok <- !is.na(.fce_k) & !is.na(.fce_m$s_reg) & !is.na(.fce_m$category)
  .fce_ok[.fce_ok] <- .fce_m$s_reg[.fce_ok] == .FCE_MEMBERS$s_reg[.fce_k[.fce_ok]] &
    .fce_m$category[.fce_ok] == .FCE_MEMBERS$family[.fce_k[.fce_ok]]
  if (!all(.fce_ok))
    stop(sprintf("[%s] 방향 · 가족 고정 위반 — 뷰 메타의 s_reg · category 가 선언과 다르다(%s): %s — 사양을 다시 선언할 것", .FCE_SPEC_ID,
                 format(.fce_d, "%Y-%m"), paste(utils::head(.fce_m$Factor_Name[!.fce_ok], 8L), collapse = ", ")))
  .fce_f <- .fce_r$families
@@SCORE_BLOCK@@
  .fce_rows[[length(.fce_rows) + 1L]] <- data.frame(Date = rep(.fce_asof, sum(.fce_v)), Ticker = .fce_f$Ticker[.fce_v],
                                                    Score = .fce_s[.fce_v], stringsAsFactors = FALSE)
  .fce_dg[[length(.fce_dg) + 1L]] <- data.frame(Date = .fce_asof, n_members_present = nrow(.fce_m), n_families_present = .fce_np,
    n_scored = sum(.fce_v), score_min = if (any(.fce_v)) min(.fce_s[.fce_v]) else NA_real_,
    score_max = if (any(.fce_v)) max(.fce_s[.fce_v]) else NA_real_, n_valid_min = if (length(.fce_nv)) min(.fce_nv) else NA_real_,
    n_valid_median = if (length(.fce_nv)) stats::median(.fce_nv) else NA_real_, n_valid_max = if (length(.fce_nv)) max(.fce_nv) else NA_real_)
}
if (!length(.fce_rows)) stop(sprintf("[%s] 산출이 비었다 — 시작일 %s 뒤 점수가 있는 달이 없다", .FCE_SPEC_ID, format(.fce_start)))
FACTORS <- data.table::rbindlist(.fce_rows)
if (!nrow(FACTORS)) stop(sprintf("[%s] 산출이 비었다 — 점수가 있는 종목이 없다", .FCE_SPEC_ID))
.fce_dgt <- do.call(rbind, .fce_dg)
.fce_dgt$start <- format(.fce_start)
.fce_dgt$spec_md5 <- .FCE_SPEC_MD5
cat(sprintf("[%s] FACTORS %d행 · 달 %d(%s ~ %s) · 시작 %s · 구성원 선언 %d · 달마다 있는 구성원 %d ~ %d\n", .FCE_SPEC_ID, nrow(FACTORS),
            nrow(.fce_dgt), format(min(.fce_dgt$Date)), format(max(.fce_dgt$Date)), format(.fce_start), nrow(.FCE_MEMBERS),
            min(.fce_dgt$n_members_present), max(.fce_dgt$n_members_present)))
.fce_dd <- getOption("fce.diag_dir", file.path(.fce_root, "04_Research", "strategies", .FCE_SPEC_ID))
if (dir.exists(.fce_dd)) {
  .fce_tmp <- file.path(.fce_dd, sprintf(".fce_diag_%d.tmp", Sys.getpid()))
  .fce_to <- file.path(.fce_dd, "fce_diag.csv")
  .fce_wr <- tryCatch({
    utils::write.csv(.fce_dgt, .fce_tmp, row.names = FALSE)
    if (file.exists(.fce_to)) file.remove(.fce_to)
    file.rename(.fce_tmp, .fce_to)
  }, error = function(e) FALSE)
  if (!isTRUE(.fce_wr)) { unlink(.fce_tmp); warning(sprintf("[%s] 진단 파일을 쓰지 못했다(판정 무관): %s", .FCE_SPEC_ID, .fce_dd)) }
}
suppressWarnings(rm(list = c(".fce_rows", ".fce_dg", ".fce_dgt", ".fce_r", ".fce_f", ".fce_m", ".fce_in", ".fce_k", ".fce_ok", ".fce_s",
                             ".fce_v", ".fce_nv", ".fce_np", ".fce_x", ".fce_nf", ".fce_fcol", ".fce_cal", ".fce_me", ".fce_d", ".fce_i",
                             ".fce_asof", ".fce_em", ".fce_dd", ".fce_tmp", ".fce_wr", ".fce_to", ".fce_fc", ".fce_start", ".FCE_M")))
invisible(gc(verbose = FALSE))
]---"

FCE_TPL_WHAT_FAMILY <- r"---[## 점수 = 종목마다 구성원 @@N@@개(등록부 category = @@FAMILY@@)의 결합용 뷰 점수 가운데 값이 있는 것의 평균 · 하나도 없으면 결측]---"
FCE_TPL_WHAT_TOTAL <- r"---[## 점수 = 종목마다 가족 점수 @@NF@@개 가운데 값이 있는 것의 평균(가족 균형 등가중) · 전부 결측이면 결측
##   가족 점수 = 그 가족 구성원 중 값이 있는 것의 평균 — 가족 엔진 FC_FAM_<가족> 과 같은 값(같은 구성원 · 같은 접근자 인자) · 구성원 @@N@@개]---"

FCE_TPL_SCORE_FAMILY <- r"---[  ## 가족 점수 = 결합용 뷰가 낸 가족 평균(구성원 중 값이 있는 것의 평균 · 하나도 없으면 결측 · 열이 없으면 그 달 구성원 0)
  .fce_s <- if (.FCE_FAMILIES %in% names(.fce_f)) .fce_f[[.FCE_FAMILIES]] else rep(NA_real_, nrow(.fce_f))
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- if (nrow(.fce_r$n_avail) == nrow(.fce_f)) .fce_r$n_avail$n_avail[.fce_v] else integer(0)
  .fce_np <- as.integer(.FCE_FAMILIES %in% names(.fce_f))]---"

FCE_TPL_SCORE_TOTAL <- r"---[  ## 토탈 v0 = 가족 점수(결합용 뷰가 낸 가족 평균) 가운데 값이 있는 것의 평균 · 전부 결측이면 결측
  .fce_fcol <- intersect(.FCE_FAMILIES, names(.fce_f))
  if (length(.fce_fcol)) {
    .fce_x <- do.call(cbind, lapply(.fce_fcol, function(cc) .fce_f[[cc]]))
    .fce_nf <- rowSums(!is.na(.fce_x))
    .fce_s <- ifelse(.fce_nf > 0L, rowSums(.fce_x, na.rm = TRUE) / pmax(.fce_nf, 1L), NA_real_)
  } else {
    .fce_nf <- integer(nrow(.fce_f)); .fce_s <- rep(NA_real_, nrow(.fce_f))
  }
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- .fce_nf[.fce_v]
  .fce_np <- length(.fce_fcol)]---"

.fce_fill <- function(txt, kv) { for (k in names(kv)) txt <- gsub(paste0("@@", k, "@@"), kv[[k]], txt, fixed = TRUE); txt }

fce_engine_text <- function(spec) {
  core <- spec[["core"]]
  if (is.null(core)) stop("[fce] 사양에 core 가 없다")
  sm <- .fce_md5_text(.fce_core_json(core))
  if (!identical(sm, spec[["spec_md5"]])) stop("[fce] 사양 md5 불일치 — core 가 바뀌었거나 손상(", spec[["spec_md5"]], " ≠ ", sm, ")")
  if (!identical(as.character(toJSON(core[["read"]], auto_unbox = TRUE)), as.character(toJSON(FCE_READ, auto_unbox = TRUE))))
    stop("[fce] 이 생성기는 읽기 인자 ", as.character(toJSON(FCE_READ, auto_unbox = TRUE)), " 만 만든다")
  if (!identical(core[["rule_version"]], FCE_RULE) || !identical(core[["start_rule"]], FCE_START_RULE))
    stop("[fce] 규칙 판 · 시작 규칙이 이 생성기와 다르다")
  kind <- core[["kind"]]; fams <- unlist(core[["families"]]); mem <- core[["members"]]
  if (!kind %in% c("family", "total")) stop("[fce] kind 밖: ", kind)
  ids <- vapply(mem, function(m) as.character(m[["id"]]), ""); sr <- vapply(mem, function(m) as.integer(m[["s_reg"]]), 1L)
  mf <- vapply(mem, function(m) as.character(m[["family"]]), "")
  if (any(!grepl("^[A-Za-z0-9_]+$", c(ids, fams, mf)))) stop("[fce] 구성원 · 가족 이름 형식 밖")
  if (anyDuplicated(ids) || !all(sr %in% c(-1L, 1L)) || !all(mf %in% fams)) stop("[fce] 구성원 표 손상")
  ml <- sprintf('  "%s", "%d", "%s"', ids, sr, mf)
  if (length(ml) > 1L) ml[-length(ml)] <- paste0(ml[-length(ml)], ",")
  what <- if (kind == "family") .fce_fill(FCE_TPL_WHAT_FAMILY, list(N = as.character(length(ids)), FAMILY = fams))
          else .fce_fill(FCE_TPL_WHAT_TOTAL, list(N = as.character(length(ids)), NF = as.character(length(fams))))
  txt <- .fce_fill(FCE_TPL_HEAD, list(
    WHAT = what,
    SCORE_BLOCK = if (kind == "family") FCE_TPL_SCORE_FAMILY else FCE_TPL_SCORE_TOTAL,
    TITLE = if (kind == "family") sprintf("팩터 가족 합성 엔진 · 가족 %s", fams) else sprintf("토탈 스코어 v0 · 가족 %d개 등가중", length(fams)),
    VALID_WHAT = if (kind == "family") "값이 있는 구성원 수" else "값이 있는 가족 수",
    SPEC_ID = core[["spec_id"]], KIND = kind, FAMILIES = paste(sprintf('"%s"', fams), collapse = ", "),
    RULE = core[["rule_version"]], GEN_MD5 = core[["generator_md5"]], SPEC_MD5 = sm, VIEW_BUILDER = core[["view_builder"]],
    N = as.character(length(ids)), MEMBER_LINES = paste(ml, collapse = "\n")))
  if (grepl("@@", txt, fixed = TRUE)) stop("[fce] 채우지 못한 자리표시 남음")
  txt
}

## ── 쓰기 · 대조 ─────────────────────────────────────────────────────────────
fce_write <- function(spec, dir) {
  txt <- fce_engine_text(spec)
  md5_new <- .fce_md5_text(txt)
  ep <- file.path(dir, "engine.R"); sp <- file.path(dir, "own_spec.json")
  if (file.exists(ep) && file.exists(sp)) {
    old <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    if (identical(.fce_md5_file(ep), md5_new) && !is.null(old) && identical(old[["engine"]][["md5"]], md5_new) &&
        identical(old[["spec_md5"]], spec[["spec_md5"]]))
      return(list(spec_id = spec$spec_id, engine_md5 = md5_new, status = "unchanged"))
  }
  prev <- if (file.exists(ep)) .fce_md5_file(ep) else NA_character_
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  .fce_write_text(txt, ep)
  if (!identical(.fce_md5_file(ep), md5_new)) stop("[fce] 쓴 엔진의 md5 가 본문과 다르다: ", ep)
  spec$engine$md5 <- md5_new
  spec$declared_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (!is.na(prev)) spec$supersedes_engine_md5 <- prev
  .fce_write_text(.fce_json(spec), sp)
  list(spec_id = spec$spec_id, engine_md5 = md5_new, status = if (is.na(prev)) "written" else "rewritten")
}

#' own_spec.json 에서 엔진을 다시 만들어 대조 — ok = 파일 md5 · 재생성 md5 · 기록 md5 가 같다 · generator_drift = 지금 생성기 ≠ 사양의 생성기
fce_verify <- function(dir, root = fce_root()) {
  sp <- fromJSON(file.path(dir, "own_spec.json"), simplifyVector = FALSE)
  fm <- .fce_md5_file(file.path(dir, "engine.R")); rm5 <- .fce_md5_text(fce_engine_text(sp))
  gn <- .fce_md5_file(file.path(root, FCE_GEN_REL))
  list(spec_id = sp$spec_id, file_md5 = fm, regen_md5 = rm5, recorded_md5 = sp$engine$md5,
       ok = identical(fm, rm5) && identical(rm5, sp$engine$md5), generator_drift = !identical(gn, sp$core$generator_md5))
}

## ── 진입점 ──────────────────────────────────────────────────────────────────
fce_generate_all <- function(root = fce_root(), out = NULL, write = FALSE, verbose = TRUE) {
  inputs <- fce_inputs(root)
  out <- gsub("\\\\", "/", out %||% file.path(root, FCE_OUT_REL))
  res <- rbindlist(lapply(c(FCE_FAMILIES, "total"), function(t) {
    sp <- fce_spec(t, inputs)
    vc <- sp$view_check
    if (length(vc$mismatches))
      warning(sprintf("[fce] %s — τ_D 달 뷰 메타와 선언 부호 · 가족이 다른 구성원 %d개(실행 때 엔진이 멈춘다 · 뷰 재빌드 또는 등록부 확인)",
                      sp$spec_id, length(vc$mismatches)), call. = FALSE)
    w <- if (write) fce_write(sp, file.path(out, sp$spec_id))
         else list(engine_md5 = .fce_md5_text(fce_engine_text(sp)), status = "dry_run")
    data.table(spec_id = sp$spec_id, kind = sp$core$kind, n_members = sp$n_members, design_draft = sp$design_draft_n_members,
               n_view_mismatch = length(vc$mismatches), engine_md5 = w$engine_md5, status = w$status)
  }))
  if (verbose) {
    cat(sprintf("[fce] 생성기 %s · 등록부 %s(%s) · 뷰 %s · 규칙 %s · 출력 %s%s\n", inputs$generator$md5, inputs$registry$md5,
                inputs$registry$mtime, inputs$view$builder, FCE_RULE, out, if (write) "" else " (dry-run · 쓰지 않음)"))
    cat(sprintf("%-22s %-7s %9s %12s %8s  %-32s  %s\n", "spec_id", "kind", "n_members", "design_draft", "view_mis", "engine_md5", "status"))
    for (i in seq_len(nrow(res)))
      cat(sprintf("%-22s %-7s %9d %12d %8d  %-32s  %s\n", res$spec_id[i], res$kind[i], res$n_members[i], res$design_draft[i],
                  res$n_view_mismatch[i], res$engine_md5[i], res$status[i]))
  }
  invisible(res)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  arg <- function(k) { i <- match(k, a); if (is.na(i) || i == length(a)) NULL else a[i + 1L] }
  if (!any(c("--write", "--dry-run") %in% a)) {
    cat("쓰기: Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write | --dry-run [--out DIR]\n")
    quit(save = "no", status = 2L)
  }
  fce_generate_all(out = arg("--out"), write = "--write" %in% a)
}
