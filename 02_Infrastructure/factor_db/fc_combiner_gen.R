#!/usr/bin/env Rscript
#==============================================================================
# fc_combiner_gen.R — 팩터 척추 결합기 T1 생성기: as-of IC 가중 합성(자체 사양 엔진)
#   설계 04_Research/01_reports/factor_spine_design_20261111/README.md §4-2 T1 · 결정 FACTOR-SPINE-STAGE1-20261112
#   구성원 = P1R03 이 선언한 T0 사양(04_Research/strategies/FC_FAM_<가족>/own_spec.json core.members) 그대로 — 가중만 바꾼다.
#   이 파일은 엔진을 만들기만 한다(등록 · 측정 없음). T0 생성기 fc_engine_gen.R(P1R03 핀)은 읽지도 고치지도 않는다.
#
# 규칙 fcc_rule_t1_v0(성과를 읽는 곳은 엔진 실행 때의 as-of IC 한 곳뿐 — 생성기는 IC · 성과를 읽지 않는다):
#   팩터 가중 w_i(d) = max(s_reg_i × ICIR_i(d), 0)
#     ICIR_i(d) = 정본 접근자 compute_rolling_ic_all(d, 36, 120)(factor_db_connector.R — IC 원장 Usable_Date ≤ d · 최근 120개월 ·
#     36개월 미만 = 없음 → 가중 0). 부호는 등록부 기대수익 부호 s_reg 로 고정(C13 — 뒤집지 않는다 · 반대 부호 IC = 가중 0).
#   가족 T1 점수 S_f = Σ_{i∈f, 값 있음} w_i z_i / Σ_{i∈f, 값 있음} w_i(분모 0 = 결측) · z = 결합용 뷰 순위 [−1, 1](등록부 방향)
#     가족 엔진 FC_FAM_<가족>_ICW: 그 달 그 가족 구성원 가중이 모두 0 이면 등가중(= T0 와 같은 값)으로 둔다(대체 · 진단에 표식).
#   토탈 T1 FC_TOTAL_ICW: 가족 가중 W_f = 그 달 뷰에 있는 그 가족 구성원 가중의 평균(가족 균형 — 구성원 수에 비례하지 않는다)
#     S = Σ_f W_f S_f / Σ_{f: S_f 값 있음} W_f · W_f = 0 인 가족은 빠진다 · 모든 W_f = 0 인 달은 T0(가족 등가중)로 둔다.
#   ICIR 이 모두 같으면 두 엔진 모두 T0 와 같은 점수 — T1 은 T0 를 품는다(차이 = as-of IC 정보 하나).
#
# 쓰기(저장소 루트에서): Rscript 02_Infrastructure/factor_db/fc_combiner_gen.R --write [--only total|families|all] [--out DIR]
#                       Rscript 02_Infrastructure/factor_db/fc_combiner_gen.R --dry-run
#   생성 엔진은 손으로 고치지 않는다 — 이 파일을 고치고 다시 만든다(생성기 md5 가 엔진에 박힌다).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

FCC_RULE     <- "fcc_rule_t1_v0"
FCC_SCHEMA   <- "fc_own_spec_v0"
FCC_DECISION <- "FACTOR-SPINE-STAGE1-20261112"
FCC_DESIGN   <- "04_Research/01_reports/factor_spine_design_20261111/README.md"
FCC_GEN_REL  <- "02_Infrastructure/factor_db/fc_combiner_gen.R"
FCC_OUT_REL  <- "04_Research/strategies"
FCC_SRC_REL  <- "04_Research/strategies"           # T0 사양 원천(P1R03 선언분)
FCC_TOTAL_ID <- "FC_TOTAL_ICW"
FCC_T0_TOTAL <- "FC_TOTAL_EW"
## 가족 14개 — T0 와 같은 순서(FC_TOTAL_EW own_spec core.families 와 대조한다)
FCC_FAMILIES <- c("quality", "defense", "liquidity", "momentum", "accrual", "value", "growth", "investor_flow",
                  "risk", "crowding", "consensus", "technical", "regime", "leverage")
FCC_READ <- list(direction = "registry", missing = "na", dedup = FALSE, family = FALSE)   # 엔진 본문의 호출과 같아야 한다(패널이 필요 · 가족 평균은 엔진이 가중으로)
FCC_IC <- list(accessor = "factor_db_connector.R::compute_rolling_ic_all", min_months = 36L, max_months = 120L,
               weight = "max(s_reg * ICIR, 0)",
               basis = paste("정본 접근자 compute_rolling_ic_all 의 기본값(min_months 36 · max_months 120) 그대로 — 새 숫자 없음.",
                             "결합용 뷰 ic_asof 부호(빌드 .load_ic_direction_cached(asof, 36L))와 같은 최소 36개월.",
                             "설계 §4-2 T1 '기존 창 36~120개월'."))
FCC_START_RULE <- "rp_start_date_else_measurement_axis_active_epoch_start_date"
FCC_TAU_SRC <- "06_Registry/behavior_card.json::tau_d"   # 진단 파일(IC 에서 나온 값)은 이 날까지만 쓴다
FCC_LIT <- list(
  list(use = "ic_weight", rule = "결합 가중을 팩터의 IC · IC 변동성(ICIR)으로 — 다요인 알파 모형의 IC 기반 결합",
       ref = "Qian, Hua & Sorensen (2007) Quantitative Equity Portfolio Management: Modern Techniques and Applications, Chapman & Hall/CRC (다요인 알파 모형 장)",
       url = "https://doi.org/10.1201/9781420010794"),
  list(use = "positive_part", rule = "지난 성과가 양(+)인 팩터에만 가중(시계열 팩터 모멘텀 — 음의 팩터를 뒤집지 않고 뺀다)",
       ref = "Ehsani & Linnainmaa (2022) Factor Momentum and the Momentum Factor, JF 77(3):1877-1919",
       url = "https://doi.org/10.1111/jofi.13131"),
  list(use = "transform", rule = "매 시점 횡단면 순위 → [−1, 1] · 동순위 평균(결합용 뷰 저장 변환 — T0 와 같다)",
       ref = "Gu, Kelly & Xiu (2020) Empirical Asset Pricing via Machine Learning, RFS 33(5):2223-2273",
       url = "https://doi.org/10.1093/rfs/hhaa009"),
  list(use = "family_unit", rule = "팩터를 주제(가족)로 묶어 합성 — 가족 균형(T0 와 같은 단위)",
       ref = "Jensen, Kelly & Pedersen (2023) Is There a Replication Crisis in Finance?, JF 78(5):2465-2518",
       url = "https://doi.org/10.1111/jofi.13249"))
FCC_ROOT_PAPER <- list(url = "https://doi.org/10.1201/9781420010794",
                       title = "Quantitative Equity Portfolio Management: Modern Techniques and Applications")

## ── 작은 도구 ────────────────────────────────────────────────────────────────
fcc_root <- function() {
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[fcc] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
}
.fcc_md5_file <- function(p) unname(as.character(tools::md5sum(p)))
.fcc_md5_text <- function(s) {
  tf <- tempfile("fcc_"); on.exit(unlink(tf), add = TRUE)
  writeBin(charToRaw(enc2utf8(s)), tf)
  .fcc_md5_file(tf)
}
.fcc_write_text <- function(text, path) {
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  writeBin(charToRaw(enc2utf8(text)), tmp)
  if (file.exists(path) && !file.remove(path)) { unlink(tmp); stop("[fcc] 기존 파일 제거 실패: ", path) }
  if (!file.rename(tmp, path)) { unlink(tmp); stop("[fcc] 이름 바꾸기 실패: ", path) }
  invisible(path)
}
.fcc_json <- function(x) paste0(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), "\n")
.fcc_core_json <- function(core) as.character(toJSON(core, auto_unbox = TRUE, digits = NA, null = "null", na = "null"))

## ── 입력 — P1R03 이 선언한 T0 사양(구성원 · 부호 · 가족) ──────────────────────────
##   T0 사양마다: spec_md5 = core 의 md5 · 엔진 파일 md5 = 기록 md5(손 편집 없음) — 어긋나면 멈춘다.
fcc_t0 <- function(root = fcc_root()) {
  rd <- function(id) {
    sp <- file.path(root, FCC_SRC_REL, id, "own_spec.json"); ep <- file.path(root, FCC_SRC_REL, id, "engine.R")
    if (!file.exists(sp) || !file.exists(ep)) stop("[fcc] T0 사양 · 엔진 없음: ", id)
    s <- fromJSON(sp, simplifyVector = FALSE)
    cm <- .fcc_md5_text(as.character(toJSON(s$core, auto_unbox = TRUE, digits = NA, null = "null", na = "null")))
    if (!identical(cm, s$spec_md5)) stop("[fcc] T0 사양 md5 불일치(core 손상): ", id)
    if (!identical(.fcc_md5_file(ep), s$engine$md5)) stop("[fcc] T0 엔진 md5 ≠ 사양 기록(손 편집?): ", id)
    list(id = id, spec = s, spec_md5 = s$spec_md5, engine_md5 = s$engine$md5, own_spec_md5 = .fcc_md5_file(sp))
  }
  fam <- setNames(lapply(paste0("FC_FAM_", FCC_FAMILIES), rd), FCC_FAMILIES)
  tot <- rd(FCC_T0_TOTAL)
  if (!identical(unlist(tot$spec$core$families), FCC_FAMILIES)) stop("[fcc] T0 토탈의 가족 순서가 이 생성기와 다르다")
  vb <- unique(vapply(c(fam, list(tot)), function(x) x$spec$core$view_builder, ""))
  if (length(vb) != 1L) stop("[fcc] T0 사양들의 뷰 빌더 판이 서로 다르다: ", paste(vb, collapse = ","))
  M <- rbindlist(lapply(FCC_FAMILIES, function(f) rbindlist(lapply(fam[[f]]$spec$core$members, as.data.table))))
  MT <- rbindlist(lapply(tot$spec$core$members, as.data.table))
  if (!identical(sort(M$id), sort(MT$id)) || anyDuplicated(M$id)) stop("[fcc] 가족 구성원 합 ≠ T0 토탈 구성원")
  chk <- merge(M, MT, by = "id")
  if (any(chk$s_reg.x != chk$s_reg.y | chk$family.x != chk$family.y)) stop("[fcc] 가족 · 토탈 사양의 부호 · 가족이 서로 다르다")
  cfgp <- file.path(root, "06_Registry", "factor_combinable.json")
  list(fam = fam, tot = tot, members = M, view_builder = vb, view_cfg_version = tot$spec$core$view_cfg_version,
       view_cfg_md5 = .fcc_md5_file(cfgp), generator = list(path = FCC_GEN_REL, md5 = .fcc_md5_file(file.path(root, FCC_GEN_REL))))
}

## ── 사양 ────────────────────────────────────────────────────────────────────
fcc_spec <- function(target, inputs = fcc_t0()) {
  is_total <- identical(target, "total")
  if (!is_total && !target %in% FCC_FAMILIES) stop("[fcc] 대상은 가족 14개 또는 'total': ", target)
  fams <- if (is_total) FCC_FAMILIES else target
  M <- inputs$members[family %in% fams]
  M <- M[order(match(family, FCC_FAMILIES), match(id, inputs$members$id))]
  src <- if (is_total) c(lapply(FCC_FAMILIES, function(f) inputs$fam[[f]]), list(inputs$tot)) else list(inputs$fam[[target]])
  sid <- if (is_total) FCC_TOTAL_ID else paste0("FC_FAM_", target, "_ICW")
  core <- list(spec_id = sid, kind = if (is_total) "total_icw" else "family_icw", families = as.list(fams), rule_version = FCC_RULE,
               generator_md5 = inputs$generator$md5, view_builder = inputs$view_builder, view_cfg_version = inputs$view_cfg_version,
               read = FCC_READ, ic = FCC_IC[c("accessor", "min_months", "max_months", "weight")], start_rule = FCC_START_RULE,
               members_from = lapply(src, function(x) list(spec_id = x$id, spec_md5 = x$spec_md5, engine_md5 = x$engine_md5)),
               members = lapply(seq_len(nrow(M)), function(i) list(id = M$id[i], s_reg = as.integer(M$s_reg[i]), family = M$family[i])))
  spec_md5 <- .fcc_md5_text(.fcc_core_json(core))
  t0 <- if (is_total) FCC_T0_TOTAL else paste0("FC_FAM_", target)
  notes <- c(
    sprintf("구성원 %d개 = T0 사양 %s(P1R03 선언 · spec_md5 %s)과 같다 — 구성원 · 부호 · 가족은 그 사양에서 옮겼고 등록부를 다시 읽지 않았다.",
            nrow(M), t0, (if (is_total) inputs$tot else inputs$fam[[target]])$spec_md5),
    "가중 = max(s_reg × ICIR, 0) — ICIR 은 엔진 실행 때 그 달 as-of 로 정본 접근자(compute_rolling_ic_all · IC 원장 Usable_Date ≤ as-of)가 낸다. 생성기는 IC · 성과를 읽지 않았다.",
    "부호는 등록부 기대수익 부호로 고정(C13) — as-of IC 가 등록부 방향과 반대인 구성원은 뒤집지 않고 가중 0 이다.",
    if (is_total) "토탈 T1 = 가족 가중 W_f(그 달 가족 구성원 가중의 평균) × 가족 T1 점수의 가중 평균 · W_f = 0 인 가족은 빠진다 · 모든 W_f = 0 인 달은 T0(가족 등가중)."
    else "가족 T1 = 구성원 가중 평균 · 그 달 가족 구성원 가중이 모두 0 이면 등가중(T0 와 같은 값)으로 둔다 — 대체한 달은 진단에 표식.",
    "ICIR 이 모두 같으면 T0 와 같은 점수다(T1 은 T0 를 품는다 · 차이 = as-of IC 정보 하나).",
    "IC 원장의 한계(설계 §9): IC 는 전 종목 · 원값 · 1개월 지평 — 측정 축(전 종목 + 위생 · 동전주 바닥) 위의 IC 가 아니다(PIT 문제 아님 · 품질 문제).",
    "진단 파일 fce_diag.csv 는 IC 에서 나온 값을 담으므로 정보 경계(06_Registry/behavior_card.json::tau_d) 이전 행만 쓴다.")
  list(schema = FCC_SCHEMA, spec_id = sid, spec_md5 = spec_md5, core = core,
       n_members = nrow(M), n_members_by_family = as.list(M[, .N, by = family][, setNames(N, family)]),
       family_root = paste0("FC:", if (is_total) "total" else target),
       root_paper = c(FCC_ROOT_PAPER, list(paper_key = sid)),
       literature = FCC_LIT, ic = FCC_IC,
       composite = list(transform = "cross_sectional_rank_to_pm1(결합용 뷰 · registry 방향)", member_weight = FCC_IC$weight,
                        family_score = "weighted_mean_of_available_members", total = if (is_total) "family_weight_mean_member_weight" else NULL,
                        fallback = if (is_total) "all_family_weights_zero -> T0 total" else "all_member_weights_zero -> T0 family (equal)",
                        missing = "drop_ticker_date (fc_load_month missing = na)"),
       output = "FACTORS(Date, Ticker, Score) — Date = 결합용 뷰의 그 달 as-of · 점수 결측 종목 제외 · PORTFOLIO 없음",
       t0_counterpart = t0, rule_notes = as.list(notes),
       decision = FCC_DECISION, design = FCC_DESIGN, generator = inputs$generator,
       inputs = list(view_cfg = list(path = "06_Registry/factor_combinable.json", md5 = inputs$view_cfg_md5),
                     t0_own_spec_md5 = lapply(src, function(x) list(spec_id = x$id, own_spec_md5 = x$own_spec_md5))),
       engine = list(path = file.path(FCC_OUT_REL, sid, "engine.R"), md5 = NA_character_),
       declared_at = NA_character_)
}

## ── 엔진 본문 ────────────────────────────────────────────────────────────────
## 본문 규약(T0 와 같다): 데이터 접근 = fc_load_month 한 곳(방향 인자 = 문자열 상수) + IC = compute_rolling_ic_all 한 곳 ·
##   팩터 DB · 뷰 · IC 원장 저장본 경로 없음 · 손 부호 반전 없음 · 소문자 's','i','g' 연속 글자를 쓰지 않는다(lookahead_detector 문맥 패턴) ·
##   본문은 core 와 사양 md5 로만 정해진다.
FCC_TPL <- r"---[## @@SPEC_ID@@ — @@TITLE@@ (자체 사양 엔진 · 팩터 척추 결합기 T1 · as-of IC 가중)
## ★생성기 산출 — 손으로 고치지 않는다. 다시 만들기(저장소 루트): Rscript 02_Infrastructure/factor_db/fc_combiner_gen.R --write
##   생성기 md5 @@GEN_MD5@@ · 사양 md5 @@SPEC_MD5@@ · 규칙 판 @@RULE@@ · 사양 원문 = 같은 폴더 own_spec.json
##   팩터 척추 설계안 §4-2 T1 · 구성원 = P1R03 선언 T0 사양(@@T0@@)과 같다 — 가중만 다르다
@@WHAT@@
##   팩터 가중 w = max(s_reg × ICIR, 0) · ICIR = 정본 접근자 compute_rolling_ic_all(그 달 as-of, 36, 120)
##     (IC 원장 Usable_Date ≤ as-of 를 접근자가 강제 · 최근 120개월 · 36개월 미만 = 없음 → 가중 0 · 반대 부호 IC = 가중 0 · 뒤집지 않는다)
##   근거: IC 기반 결합 — Qian, Hua & Sorensen (2007) QEPM https://doi.org/10.1201/9781420010794
##     · 양의 지난 성과 팩터만 — Ehsani & Linnainmaa (2022) JF 77(3) https://doi.org/10.1111/jofi.13131
##     · 순위 변환 — Gu, Kelly & Xiu (2020) RFS 33(5) https://doi.org/10.1093/rfs/hhaa009 · 가족 단위 — JKP (2023) https://doi.org/10.1111/jofi.13249
##   ICIR 이 모두 같으면 T0 와 같은 점수(T1 은 T0 를 품는다)
## 계약: 입력 = RAWDATA(거래일 달력 — Date 열만 쓴다) · .RP_START_DATE(없으면 측정 축 정본의 활성 epoch 시작일)
##   출력 = FACTORS(Date, Ticker, Score) 만 · 날짜 = 결합용 뷰의 그 달 as-of(월말 거래일 — 셀 경로 달 스냅에서 항등)
##   as-of 가 시작일 이후인 달만 · 패널 마지막 달을 뷰가 아직 못 따라왔으면 그 달만 뺀다(그 달은 뒤 수익이 없다)
## PIT: 팩터 값 = fc_load_month 한 길(C15) · 방향 인자 = 문자열 상수 registry(C13 · 부호 = 등록부 고정 · 가중 ≥ 0 단정)
##   · IC = compute_rolling_ic_all 한 길(C14 — Usable_Date ≤ as-of) · 재무 시차는 팩터 DB 가 이미 적용한 값만(C4)
##   · 구성원 · 부호 · 가족 · 뷰 빌더 판 · IC 창은 선언 때 고정 — 실행 때 다르면 멈춘다(새 사양으로 다시 선언)
## 진단(판정 입력 아님): 날짜별 구성원 수 · 양의 가중 수 · 대체 여부 · 점수 범위 · 유효 수 → 이 폴더 fce_diag.csv
##   IC 에서 나온 값이라 정보 경계(06_Registry/behavior_card.json tau_d) 이전 행만 쓴다 · options(fce.diag_dir) 로 바꾼다 · 폴더가 없으면 쓰지 않는다
.FCE_SPEC_ID <- "@@SPEC_ID@@"
.FCE_KIND <- "@@KIND@@"
.FCE_FAMILIES <- c(@@FAMILIES@@)
.FCE_RULE <- "@@RULE@@"
.FCE_GEN_MD5 <- "@@GEN_MD5@@"
.FCE_SPEC_MD5 <- "@@SPEC_MD5@@"
.FCE_VIEW_BUILDER <- "@@VIEW_BUILDER@@"
.FCE_IC_MIN <- @@IC_MIN@@L
.FCE_IC_MAX <- @@IC_MAX@@L
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
## IC 접근자 — 정본 커넥터(결합용 뷰 .fc_env 와 같은 적재 순서: config.R → factor_db_connector.R · 작업 폴더 = 02_Infrastructure)
.fce_ic <- new.env(parent = globalenv())
local({
  .fce_owd <- setwd(file.path(.fce_root, "02_Infrastructure")); on.exit(setwd(.fce_owd), add = TRUE)
  invisible(utils::capture.output(suppressMessages({
    sys.source(file.path(.fce_root, "02_Infrastructure", "config.R"), envir = .fce_ic, keep.source = FALSE)
    sys.source(file.path(.fce_root, "02_Infrastructure", "factor_db", "factor_db_connector.R"), envir = .fce_ic, keep.source = FALSE)
  })))
})
if (!is.function(.fce_ic$compute_rolling_ic_all)) stop("[@@SPEC_ID@@] IC 접근자 compute_rolling_ic_all 을 싣지 못했다")
.fce_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else local({
  e <- new.env(parent = globalenv())
  sys.source(file.path(.fce_root, "02_Infrastructure", "contracts", "measurement_axis.R"), envir = e, keep.source = FALSE)
  as.Date(e$ma_epoch(root = .fce_root)$start_date)
})
if (length(.fce_start) != 1L || is.na(.fce_start)) stop("[@@SPEC_ID@@] 측정 시작일을 읽지 못했다")
.fce_tau <- tryCatch(as.Date(jsonlite::fromJSON(file.path(.fce_root, "06_Registry", "behavior_card.json"))$tau_d), error = function(e) as.Date(NA))
if (!exists("RAWDATA")) stop("[@@SPEC_ID@@] RAWDATA 없음 — 셀 경로 · 러너가 넘기는 패널(거래일 달력)이 필요하다")
.fce_cal <- sort(unique(as.Date(RAWDATA[["Date"]])))
.fce_me <- .fce_cal[!duplicated(format(.fce_cal, "%Y%m"), fromLast = TRUE)]
.fce_me <- .fce_me[.fce_me >= .fce_start]
if (!length(.fce_me)) stop(sprintf("[%s] 시작일 %s 뒤 월말 거래일이 패널에 없다", .FCE_SPEC_ID, format(.fce_start)))
## 가중 합성 — 열 j 의 가중 w 로 종목마다 (값 있는 구성원 가중 합)으로 나눈다(분모 0 = 결측)
.fce_wavg <- function(Z0, A, j, w) {
  num <- drop(Z0[, j, drop = FALSE] %*% w); den <- drop(A[, j, drop = FALSE] %*% w)
  ifelse(den > 0, num / den, NA_real_)
}
.fce_rows <- list(); .fce_dg <- list()
for (.fce_i in seq_along(.fce_me)) {
  .fce_d <- .fce_me[.fce_i]
  .fce_r <- NULL
  invisible(utils::capture.output(.fce_r <- tryCatch(
    .fce_fc$fc_load_month(.fce_d, direction = "registry", factors = .FCE_MEMBERS$id, missing = "na", dedup = FALSE, family = FALSE),
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
  ## as-of IC → 구성원 가중(부호 = 등록부 고정 · 음수 · 없음 = 0)
  .fce_icr <- NULL
  invisible(utils::capture.output(.fce_icr <- .fce_ic$compute_rolling_ic_all(.fce_asof, .FCE_IC_MIN, .FCE_IC_MAX)))
  .fce_a <- .FCE_MEMBERS$s_reg * .fce_icr$ICIR[match(.FCE_MEMBERS$id, .fce_icr$Factor_Name)]
  .fce_w <- ifelse(is.finite(.fce_a) & .fce_a > 0, .fce_a, 0)
  if (length(.fce_w) != nrow(.FCE_MEMBERS) || any(!is.finite(.fce_w)) || any(.fce_w < 0))
    stop(sprintf("[%s] 가중 단정 위반(유한 · 비음수 · 구성원 수) — %s", .FCE_SPEC_ID, format(.fce_d, "%Y-%m")))
  .fce_P <- as.data.frame(.fce_r$panel)
  .fce_cols <- intersect(.FCE_MEMBERS$id, names(.fce_P))
  .fce_kc <- match(.fce_cols, .FCE_MEMBERS$id)
  .fce_wc <- .fce_w[.fce_kc]; .fce_fm <- .FCE_MEMBERS$family[.fce_kc]
  .fce_Z0 <- as.matrix(.fce_P[, .fce_cols, drop = FALSE]); storage.mode(.fce_Z0) <- "double"
  .fce_A <- !is.na(.fce_Z0); .fce_Z0[!.fce_A] <- 0
@@SCORE_BLOCK@@
  .fce_rows[[length(.fce_rows) + 1L]] <- data.frame(Date = rep(.fce_asof, sum(.fce_v)), Ticker = .fce_P$Ticker[.fce_v],
                                                    Score = .fce_s[.fce_v], stringsAsFactors = FALSE)
  .fce_dg[[length(.fce_dg) + 1L]] <- data.frame(Date = .fce_asof, n_members_present = length(.fce_cols), n_pos_weight = .fce_npos,
    n_families_weighted = .fce_np, fallback_t0 = .fce_fb, n_scored = sum(.fce_v),
    score_min = if (any(.fce_v)) min(.fce_s[.fce_v]) else NA_real_, score_max = if (any(.fce_v)) max(.fce_s[.fce_v]) else NA_real_,
    n_valid_min = if (length(.fce_nv)) min(.fce_nv) else NA_real_, n_valid_median = if (length(.fce_nv)) stats::median(.fce_nv) else NA_real_,
    n_valid_max = if (length(.fce_nv)) max(.fce_nv) else NA_real_)
}
if (!length(.fce_rows)) stop(sprintf("[%s] 산출이 비었다 — 시작일 %s 뒤 점수가 있는 달이 없다", .FCE_SPEC_ID, format(.fce_start)))
FACTORS <- data.table::rbindlist(.fce_rows)
if (!nrow(FACTORS)) stop(sprintf("[%s] 산출이 비었다 — 점수가 있는 종목이 없다", .FCE_SPEC_ID))
.fce_dgt <- do.call(rbind, .fce_dg)
cat(sprintf("[%s] FACTORS %d행 · 달 %d(%s ~ %s) · 시작 %s · 구성원 선언 %d · 달마다 있는 구성원 %d ~ %d\n", .FCE_SPEC_ID, nrow(FACTORS),
            nrow(.fce_dgt), format(min(.fce_dgt$Date)), format(max(.fce_dgt$Date)), format(.fce_start), nrow(.FCE_MEMBERS),
            min(.fce_dgt$n_members_present), max(.fce_dgt$n_members_present)))
.fce_dd <- getOption("fce.diag_dir", file.path(.fce_root, "04_Research", "strategies", .FCE_SPEC_ID))
if (dir.exists(.fce_dd) && !is.na(.fce_tau)) {
  .fce_dgt <- .fce_dgt[.fce_dgt$Date <= .fce_tau, , drop = FALSE]
  .fce_dgt$start <- rep(format(.fce_start), nrow(.fce_dgt)); .fce_dgt$spec_md5 <- rep(.FCE_SPEC_MD5, nrow(.fce_dgt))
  .fce_tmp <- file.path(.fce_dd, sprintf(".fce_diag_%d.tmp", Sys.getpid()))
  .fce_to <- file.path(.fce_dd, "fce_diag.csv")
  .fce_wr <- tryCatch({
    utils::write.csv(.fce_dgt, .fce_tmp, row.names = FALSE)
    if (file.exists(.fce_to)) file.remove(.fce_to)
    file.rename(.fce_tmp, .fce_to)
  }, error = function(e) FALSE)
  if (!isTRUE(.fce_wr)) { unlink(.fce_tmp); warning(sprintf("[%s] 진단 파일을 쓰지 못했다(판정 무관): %s", .FCE_SPEC_ID, .fce_dd)) }
}
suppressWarnings(rm(list = c(".fce_rows", ".fce_dg", ".fce_dgt", ".fce_r", ".fce_m", ".fce_in", ".fce_k", ".fce_ok", ".fce_s", ".fce_v",
                             ".fce_nv", ".fce_np", ".fce_npos", ".fce_fb", ".fce_icr", ".fce_a", ".fce_w", ".fce_P", ".fce_cols", ".fce_kc",
                             ".fce_wc", ".fce_fm", ".fce_Z0", ".fce_A", ".fce_j", ".fce_S", ".fce_W", ".fce_g", ".fce_Wm", ".fce_den",
                             ".fce_cal", ".fce_me", ".fce_d", ".fce_i", ".fce_asof", ".fce_em", ".fce_dd", ".fce_tmp", ".fce_wr", ".fce_to",
                             ".fce_fc", ".fce_ic", ".fce_start", ".fce_tau", ".fce_wavg", ".FCE_M")))
invisible(gc(verbose = FALSE))
]---"

FCC_TPL_WHAT_FAMILY <- r"---[## 점수 = 종목마다 구성원 @@N@@개(등록부 category = @@FAMILY@@)의 결합용 뷰 점수를 as-of IC 가중으로 평균(값 있는 구성원만)
##   그 달 구성원 가중이 모두 0 이면 등가중(T0 FC_FAM_@@FAMILY@@ 와 같은 값) — 진단 fallback_t0]---"
FCC_TPL_WHAT_TOTAL <- r"---[## 점수 = 종목마다 가족 T1 점수 @@NF@@개의 가중 평균 · 가족 가중 = 그 달 그 가족 구성원 가중의 평균(가족 균형) · 구성원 @@N@@개
##   가족 가중 0 인 가족은 빠진다 · 모든 가족 가중이 0 인 달은 T0(FC_TOTAL_EW 와 같은 가족 등가중) — 진단 fallback_t0]---"

FCC_TPL_SCORE_FAMILY <- r"---[  ## 가족 T1 점수 = 구성원 가중 평균(값 있는 구성원) · 가중이 모두 0 이면 등가중(T0)
  .fce_j <- which(.fce_fm == .FCE_FAMILIES)
  .fce_npos <- sum(.fce_wc[.fce_j] > 0)
  .fce_fb <- length(.fce_j) > 0L && .fce_npos == 0L
  .fce_s <- if (!length(.fce_j)) rep(NA_real_, nrow(.fce_Z0)) else
    .fce_wavg(.fce_Z0, .fce_A, .fce_j, if (.fce_fb) rep(1, length(.fce_j)) else .fce_wc[.fce_j])
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- if (length(.fce_j)) rowSums(.fce_A[, .fce_j, drop = FALSE][, (.fce_wc[.fce_j] > 0) | .fce_fb, drop = FALSE])[.fce_v] else numeric(0)
  .fce_np <- as.integer(.fce_npos > 0L)]---"

FCC_TPL_SCORE_TOTAL <- r"---[  ## 토탈 T1 = 가족 T1 점수의 가중 평균 · 가족 가중 W = 그 달 가족 구성원 가중의 평균 · 모든 W = 0 이면 T0(가족 등가중)
  .fce_S <- matrix(NA_real_, nrow(.fce_Z0), length(.FCE_FAMILIES)); .fce_W <- numeric(length(.FCE_FAMILIES))
  .fce_npos <- sum(.fce_wc > 0)
  .fce_fb <- .fce_npos == 0L
  for (.fce_g in seq_along(.FCE_FAMILIES)) {
    .fce_j <- which(.fce_fm == .FCE_FAMILIES[.fce_g])
    if (!length(.fce_j)) next
    if (.fce_fb) {
      .fce_W[.fce_g] <- 1; .fce_S[, .fce_g] <- .fce_wavg(.fce_Z0, .fce_A, .fce_j, rep(1, length(.fce_j)))
    } else {
      .fce_W[.fce_g] <- mean(.fce_wc[.fce_j])
      if (.fce_W[.fce_g] > 0) .fce_S[, .fce_g] <- .fce_wavg(.fce_Z0, .fce_A, .fce_j, .fce_wc[.fce_j])
    }
  }
  if (any(!is.finite(.fce_W)) || any(.fce_W < 0)) stop(sprintf("[%s] 가족 가중 단정 위반 — %s", .FCE_SPEC_ID, format(.fce_d, "%Y-%m")))
  .fce_Wm <- matrix(.fce_W, nrow(.fce_S), length(.fce_W), byrow = TRUE); .fce_Wm[is.na(.fce_S)] <- 0
  .fce_den <- rowSums(.fce_Wm)
  .fce_s <- ifelse(.fce_den > 0, rowSums(.fce_Wm * ifelse(is.na(.fce_S), 0, .fce_S)) / .fce_den, NA_real_)
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- rowSums(!is.na(.fce_S))[.fce_v]
  .fce_np <- sum(.fce_W > 0)]---"

.fcc_fill <- function(txt, kv) { for (k in names(kv)) txt <- gsub(paste0("@@", k, "@@"), kv[[k]], txt, fixed = TRUE); txt }

fcc_engine_text <- function(spec) {
  core <- spec[["core"]]
  if (is.null(core)) stop("[fcc] 사양에 core 가 없다")
  sm <- .fcc_md5_text(.fcc_core_json(core))
  if (!identical(sm, spec[["spec_md5"]])) stop("[fcc] 사양 md5 불일치 — core 가 바뀌었거나 손상(", spec[["spec_md5"]], " ≠ ", sm, ")")
  if (!identical(as.character(toJSON(core[["read"]], auto_unbox = TRUE)), as.character(toJSON(FCC_READ, auto_unbox = TRUE))))
    stop("[fcc] 이 생성기는 읽기 인자 ", as.character(toJSON(FCC_READ, auto_unbox = TRUE)), " 만 만든다")
  if (!identical(core[["rule_version"]], FCC_RULE) || !identical(core[["start_rule"]], FCC_START_RULE))
    stop("[fcc] 규칙 판 · 시작 규칙이 이 생성기와 다르다")
  ic <- core[["ic"]]
  if (!identical(as.integer(ic[["min_months"]]), FCC_IC$min_months) || !identical(as.integer(ic[["max_months"]]), FCC_IC$max_months) ||
      !identical(ic[["weight"]], FCC_IC$weight)) stop("[fcc] IC 창 · 가중 규칙이 이 생성기와 다르다")
  kind <- core[["kind"]]; fams <- unlist(core[["families"]]); mem <- core[["members"]]
  if (!kind %in% c("family_icw", "total_icw")) stop("[fcc] kind 밖: ", kind)
  ids <- vapply(mem, function(m) as.character(m[["id"]]), ""); sr <- vapply(mem, function(m) as.integer(m[["s_reg"]]), 1L)
  mf <- vapply(mem, function(m) as.character(m[["family"]]), "")
  if (any(!grepl("^[A-Za-z0-9_]+$", c(ids, fams, mf)))) stop("[fcc] 구성원 · 가족 이름 형식 밖")
  if (anyDuplicated(ids) || !all(sr %in% c(-1L, 1L)) || !all(mf %in% fams)) stop("[fcc] 구성원 표 손상")
  ml <- sprintf('  "%s", "%d", "%s"', ids, sr, mf)
  if (length(ml) > 1L) ml[-length(ml)] <- paste0(ml[-length(ml)], ",")
  fam1 <- kind == "family_icw"
  what <- if (fam1) .fcc_fill(FCC_TPL_WHAT_FAMILY, list(N = as.character(length(ids)), FAMILY = fams))
          else .fcc_fill(FCC_TPL_WHAT_TOTAL, list(N = as.character(length(ids)), NF = as.character(length(fams))))
  body <- .fcc_fill(FCC_TPL, list(WHAT = what, SCORE_BLOCK = if (fam1) FCC_TPL_SCORE_FAMILY else FCC_TPL_SCORE_TOTAL))
  ## 'sig' 금지 검사 — 구성원 줄을 넣기 전 본문(lookahead_detector 의 신호일 문맥 패턴과 겹치지 않게)
  if (grepl("sig", body, fixed = TRUE)) stop("[fcc] 엔진 본문 틀에 's','i','g' 연속 글자가 있다 — 고칠 것")
  txt <- .fcc_fill(body, list(
    TITLE = if (fam1) sprintf("결합기 T1 · 가족 %s(as-of IC 가중)", fams) else sprintf("결합기 T1 토탈 · 가족 %d개(as-of IC 가중 · 가족 균형)", length(fams)),
    T0 = if (fam1) paste0("FC_FAM_", fams) else FCC_T0_TOTAL,
    SPEC_ID = core[["spec_id"]], KIND = kind, FAMILIES = paste(sprintf('"%s"', fams), collapse = ", "),
    RULE = core[["rule_version"]], GEN_MD5 = core[["generator_md5"]], SPEC_MD5 = sm, VIEW_BUILDER = core[["view_builder"]],
    IC_MIN = as.character(FCC_IC$min_months), IC_MAX = as.character(FCC_IC$max_months),
    N = as.character(length(ids)), MEMBER_LINES = paste(ml, collapse = "\n")))
  if (grepl("@@", txt, fixed = TRUE)) stop("[fcc] 채우지 못한 자리표시 남음")
  txt
}

## ── 쓰기 · 대조 ─────────────────────────────────────────────────────────────
fcc_write <- function(spec, dir) {
  txt <- fcc_engine_text(spec)
  md5_new <- .fcc_md5_text(txt)
  ep <- file.path(dir, "engine.R"); sp <- file.path(dir, "own_spec.json")
  if (file.exists(ep) && file.exists(sp)) {
    old <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    if (identical(.fcc_md5_file(ep), md5_new) && !is.null(old) && identical(old[["engine"]][["md5"]], md5_new) &&
        identical(old[["spec_md5"]], spec[["spec_md5"]]))
      return(list(spec_id = spec$spec_id, engine_md5 = md5_new, status = "unchanged"))
  }
  prev <- if (file.exists(ep)) .fcc_md5_file(ep) else NA_character_
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  .fcc_write_text(txt, ep)
  if (!identical(.fcc_md5_file(ep), md5_new)) stop("[fcc] 쓴 엔진의 md5 가 본문과 다르다: ", ep)
  spec$engine$md5 <- md5_new
  spec$declared_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (!is.na(prev)) spec$supersedes_engine_md5 <- prev
  .fcc_write_text(.fcc_json(spec), sp)
  list(spec_id = spec$spec_id, engine_md5 = md5_new, status = if (is.na(prev)) "written" else "rewritten")
}

#' own_spec.json 에서 엔진을 다시 만들어 대조 — ok = 파일 md5 · 재생성 md5 · 기록 md5 가 같다 · generator_drift = 지금 생성기 ≠ 사양의 생성기
fcc_verify <- function(dir, root = fcc_root()) {
  sp <- fromJSON(file.path(dir, "own_spec.json"), simplifyVector = FALSE)
  fm <- .fcc_md5_file(file.path(dir, "engine.R")); rm5 <- .fcc_md5_text(fcc_engine_text(sp))
  gn <- .fcc_md5_file(file.path(root, FCC_GEN_REL))
  list(spec_id = sp$spec_id, file_md5 = fm, regen_md5 = rm5, recorded_md5 = sp$engine$md5,
       ok = identical(fm, rm5) && identical(rm5, sp$engine$md5), generator_drift = !identical(gn, sp$core$generator_md5))
}

## ── 진입점 ──────────────────────────────────────────────────────────────────
fcc_generate <- function(root = fcc_root(), out = NULL, write = FALSE, only = "all", verbose = TRUE) {
  inputs <- fcc_t0(root)
  out <- gsub("\\\\", "/", out %||% file.path(root, FCC_OUT_REL))
  tg <- switch(only, all = c(FCC_FAMILIES, "total"), total = "total", families = FCC_FAMILIES, stop("[fcc] --only 는 all | total | families"))
  res <- rbindlist(lapply(tg, function(t) {
    sp <- fcc_spec(t, inputs)
    w <- if (write) fcc_write(sp, file.path(out, sp$spec_id)) else list(engine_md5 = .fcc_md5_text(fcc_engine_text(sp)), status = "dry_run")
    data.table(spec_id = sp$spec_id, kind = sp$core$kind, n_members = sp$n_members, family_root = sp$family_root,
               engine_md5 = w$engine_md5, status = w$status)
  }))
  if (verbose) {
    cat(sprintf("[fcc] 생성기 %s · 뷰 %s · 규칙 %s · IC 창 %d~%d개월 · 출력 %s%s\n", inputs$generator$md5, inputs$view_builder, FCC_RULE,
                FCC_IC$min_months, FCC_IC$max_months, out, if (write) "" else " (dry-run · 쓰지 않음)"))
    for (i in seq_len(nrow(res)))
      cat(sprintf("%-26s %-11s %4d  %-18s %s  %s\n", res$spec_id[i], res$kind[i], res$n_members[i], res$family_root[i], res$engine_md5[i], res$status[i]))
  }
  invisible(res)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  arg <- function(k) { i <- match(k, a); if (is.na(i) || i == length(a)) NULL else a[i + 1L] }
  if (!any(c("--write", "--dry-run") %in% a)) {
    cat("쓰기: Rscript 02_Infrastructure/factor_db/fc_combiner_gen.R --write | --dry-run [--only all|total|families] [--out DIR]\n")
    quit(save = "no", status = 2L)
  }
  fcc_generate(out = arg("--out"), write = "--write" %in% a, only = arg("--only") %||% "all")
}
