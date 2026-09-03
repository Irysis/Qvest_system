# promote.R — 5-Axis Promoter (v8.0: 원전 r7 복원 + 2-tier + INV-1/4/6/7)
#
# 원전 00_Lawbook/Axiom_아키텍처/r7_axiom_design.md 5축 boolean-AND 복원:
#   Independence(construction 다양성) / Rigor(metric_type 게이트) / Falsification(적극 반증)
#   / External(OOS) / Mechanism. 현 구현의 열화(weighted-sum / strategy_id 착시 /
#   negative auto-bonus)를 교정한다.
#
# INV-4: 5축 각 min-hurdle 동시 충족(boolean AND)이 통과 — weighted는 랭킹용.
# INV-1: 본 함수는 mode-local 승격(AX-<MODE>-NNN). global은 promote_global.R(backtested+essence_score §3).
# INV-7: negative = provisional(epistemic_status) + 비대칭 burden(construction 상향) + expiry.
# INV-6: 초안 statement(`[초안]...확정 필요`)는 needs_refinement 표기.
# INV-2: 자동 승격 = enforcement_mode=documented / enforcement="" (hook block은 주간 confirm).
#
# ── v9 "Lean Loop" 재보정 (2026-08-23, 도훈 결정 §3.4(a) + §6 D-f/D-g) ─────────
# 실측: 728회 재채점에서 5축 동시 통과 **0건**, 마지막 승격 2026-05-02. 07-04 진단
#   ("입력 결측이라 문턱 불변")은 external 축 실측 중앙값 −0.04 로 반증됐다.
# ⇒ ①mode-local hurdle 축을 3종(independence/rigor_research/mechanism)으로 축소
#     (external·falsification 은 점수만 — .TIER 참조) ②independence 판정 기준을
#     grade 최빈 비율 → **win/loss** 로 교체 ③단일 L-code·polarity unknown 은 조기 SKIP
#     ④양성·조건부 = `status=proposed` 공리(도훈 1줄 confirm 후 approve_axiom 으로 active)
#     ⑤음성 = 공리 아님 → DIST 탐색지도 카드 자동 활성화(auto_map_negative, INV-7)
#     ⑥review_log = 클러스터당 1파일 + history[] (MAX_PATH 무음 crash 해소)
#   전역 Law(promote_global.R · .HURDLE · INV-1 · 2.95 · AX-008)는 **불변**.
#
# Usage: Rscript promote.R [--dry-run] qepm/memory/axioms/candidates/CAND_XXX.json
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.px_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
             Sys.getenv("QVEST_PROJECT_DIR", ""), Sys.getenv("PROJECT_ROOT", ""), getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.MODE_PREFIX <- c(alpha_search = "AS", alpha_research = "AR", qepm_legacy = "QPM",
                  judge_gate = "JG", governor_admission = "GV",
                  strategy_rotation = "FR",  # v9.21 개명 (prefix 유지)
                  factor_rotation = "FR",    # 역사 라벨
                  regime_research = "RR",
                  ramp = "RAMP",
                  ## ★부채 봉합 2026-08-24: `overlay_research` 가 여기에만 없었다.
                  ##   lcode_emit.R:33 은 OVL 을 갖는데 이 맵이 빠뜨려서, OVL L-code 11건이
                  ##   승격 경로에서 GEN 폴백으로 떨어졌다 — 모드가 있는데 prefix 가 없으면
                  ##   그 계열은 조용히 다른 계급으로 집계된다.
                  overlay_research = "OVL")  # 2026-07-03: RAMP 4번째 모드 (lcode_emit/.LCODE_MODE_PREFIX·lcode_schema와 정합)

# crash-safe prefix 조회 — named vector `[[`는 missing name에 hard error라
# `%||% "GEN"` 폴백이 실행되지 않던 결함(예: research_mode="qepm"/"global") 교정.
.mode_prefix <- function(mode) {
  if (is.null(mode) || !length(mode) || is.na(mode[1])) return("GEN")
  p <- unname(.MODE_PREFIX[as.character(mode)[1]])
  if (is.na(p)) "GEN" else p
}

.HURDLE <- list(
  indep_min_constructions = 2L, indep_min_constructions_neg = 3L,  # INV-7 negative 상향
  indep_min_direction = 0.8,
  rigor_backtested_port_t = 2.95, rigor_neg_frac_fail = 0.8,
  fals_min_attempts = 1L, fals_min_retained = 0.5,
  # External 재정의 (2026-07-03 도훈 confirm, 감사 GOV-01/AXM-01):
  #   구 hurdle(oos_months>=3 AND oos_effect_vs_is>=0.5)의 oos_months는 L-code corpus 실값 0건
  #   = 영구 불충족(측정 불가능 지표). oos_retention은 corpus 457/594건 실값 보유 —
  #   '요건 완화가 아니라 측정 불가능 지표의 측정 가능 지표 교체'.
  #   문턱 0.5 = 구 vs_is 0.5 개념 유지 + measurement-graduation.md §3
  #   'oos_retention < 0.5 무조건 FAIL' 하한과 정합 (창작 수치 아님).
  ext_min_oos_retention = 0.5,
  ext_min_oos_months = 3  # 가산 증거로 강등 — 실값 존재+충족 시 score 가산만, hurdle 무관
)

# ── v9 Lean Loop: tier 별 승격 사다리 (2026-08-23 도훈 결정 §3.4(a)·§6 D-g) ─────
# 근거 = 실측 728회 재채점에서 5축 동시 통과 0건, 최소 2축 실패(external 93%·
#   independence 89%·falsification 80%). 07-04 진단("입력 결측 → 문턱 불변")은
#   external 축 실측 중앙값 −0.04 로 반증됐다 — 통계량 자체가 도달 불가였다.
# ⇒ mode-local 은 축을 3종(independence / rigor_research / mechanism)으로 줄이고
#   방향 판정을 grade 최빈 비율 대신 win/loss 기준으로 바꾼다.
#   external·falsification 은 점수(랭킹)로만 남고 hurdle 이 아니다.
# ★.HURDLE(위)은 전역 Law 문턱이며 promote_global.R 이 그대로 쓴다 — 무변경.
.TIER <- list(
  mode_local = list(
    hurdle_axes             = c("independence", "rigor_research", "mechanism"),
    indep_min_constructions = 2L,
    direction_basis         = "win_loss",   # A/B = win, C/F = loss (.grade_direction)
    indep_min_direction     = 0.8,          # positive/negative: 우세 방향 비율 하한
    conditional_min_win     = 2L,           # conditional/mixed: 양 가지 각각의 최소 건수
    conditional_min_loss    = 2L,
    rigor_research_min_n    = 2L,           # positive/conditional: A/B ∨ canonical/backtested
    negative_min_fail       = 2L,           # negative: C/F 건수
    skip_polarity           = c("unknown"), # 방향 미상은 사다리 대상 아님
    passed_rule             = "all_hurdles",# weighted 는 랭킹 전용(문턱 아님)
    # ── v9.1 커밋14 활성 상한 ─────────────────────────────────────────────
    #   ★2026-08-30 문구 정정: 구 주석 "사람 승인이 사라지므로 필수" 는 오독을 부른다 —
    #   **사람 승인은 사라지지 않았다**. promote.R 은 status="proposed" 까지만 쓰고
    #   활성화는 approve_axiom(ids, approved_by="dohoon") 명시 호출로만 일어난다.
    #   자동 경로(weekly_cleaner_sweep.R)는 그 함수를 **부르지 않고 안내만** 한다(833행).
    #   훅도 status=="active" 만 주입한다. 2026-08-30 실측: mode-local 18건 전부 proposed,
    #   active 0 — 관문이 실제로 작동 중이다. 상한은 승인 부재 대비가 아니라
    #   **승인된 재고가 주입 렌더 상한(모드당 2·총 5줄)을 넘지 않게** 하는 장치다.
    #   초과 시 verdict = FAIL_CAP + 다이제스트 힌트. **자동 축출은 하지 않는다** —
    #   "무엇을 버릴지"는 사람이 정한다(deactivate_axiom / rollback_axiom).
    #   상한 6/20 의 근거: 주입 렌더 상한이 모드당 2·총 5줄이므로 활성 재고가 그보다
    #   3~4배 커지면 "활성인데 한 번도 주입되지 않는 공리"가 다수가 된다(= 원장 비대).
    max_active_per_mode     = 6L,
    max_active_total        = 20L,
    # 동일 refine_input_sha 로 이 주수만큼 연속 HELD 면 status="held_stale".
    #   ★삭제가 아니다(AX-000) — 입력이 바뀌면 다시 판정 대상이 된다.
    held_stale_weeks        = 8L,
    backlink_max_files      = 60L  # 초과 시 개별 L-code 파일 대신 역인덱스 1파일
  ),
  global = list(
    hurdle_axes = c("independence", "rigor", "falsification", "external", "mechanism")
  )
)

# hurdle_axes 라벨 → report$axes 키. mode-local 은 rigor 축을 'rigor_research' 로 부른다
# (같은 함수가 재는 것이 tier 마다 다른 양이므로 이름을 분리해 원장에서 구분 가능하게 함).
.AXIS_KEY <- c(independence = "independence", rigor = "rigor", rigor_research = "rigor",
               falsification = "falsification", external = "external", mechanism = "mechanism")

# sha1 — cluster_extractor._cluster_key(python hashlib.sha1) 과 바이트 동치여야 한다.
.sha1 <- function(txt) {
  if (requireNamespace("digest", quietly = TRUE))
    return(digest::digest(txt, algo = "sha1", serialize = FALSE))
  if (requireNamespace("openssl", quietly = TRUE))
    return(as.character(openssl::sha1(charToRaw(enc2utf8(txt)))))
  stop("sha1 계산 불가 — digest 또는 openssl 패키지 필요")
}

# cluster_key(12-hex) = sha1("|".join(sorted(set(l_codes)))) 앞 12자리.
#   ★sort(method="radix") 필수 — 기본 sort 는 로케일 collation 이라 python 의
#     코드포인트 정렬과 순서가 달라질 수 있고 그러면 같은 클러스터가 다른 키를 얻는다.
#   candidate 가 cluster_key 를 들고 있으면(v9 extractor 산출) 그것을 신뢰하고,
#   없으면(구 스키마) 여기서 재계산한다 — 두 경로가 같은 값을 내야 한다.
.cluster_key_from_lcodes <- function(l_codes) {
  ls <- sort(unique(as.character(l_codes %||% character(0))), method = "radix")
  substr(.sha1(paste(ls, collapse = "|")), 1, 12)
}
.cluster_key_of <- function(candidate) {
  k <- as.character(candidate$cluster_key %||% "")[1]
  if (!is.na(k) && nzchar(k) && grepl("^[0-9a-f]{12}$", k)) return(k)
  .cluster_key_from_lcodes(candidate$supporting_l_codes)
}

# candidate_sha — "이 후보를 다시 채점할 이유가 있는가"의 단일 판정값.
#   후보 파일 자체 + 그 멤버 L-code 의 채점 입력(grade/metric_type/construction_type/
#   portfolio_alpha_t/oos_retention)만 섞는다. corpus 전체를 섞으면 무관한 L-code 1건
#   추가로 전 후보가 재채점된다(주간 churn 의 원인).
#   ★weekly_cleaner_sweep.R 이 이 함수를 sys.source 로 그대로 재사용한다 —
#     술어를 두 벌로 두면 한쪽만 고쳐졌을 때 어느 검사에도 안 보인다.
.candidate_sha <- function(candidate_path, corpus) {
  if (!file.exists(candidate_path)) return(NA_character_)
  fh <- if (requireNamespace("digest", quietly = TRUE))
    digest::digest(file = candidate_path, algo = "sha1") else
    .sha1(paste(readLines(candidate_path, warn = FALSE), collapse = "\n"))
  cand <- tryCatch(fromJSON(candidate_path, simplifyVector = FALSE), error = function(e) NULL)
  sup <- sort(unique(as.character(cand$supporting_l_codes %||% character(0))), method = "radix")
  .fld <- function(lc, f) {
    v <- .lc_get(corpus, lc, f, NULL)
    if (is.null(v) || !length(v)) return("")
    as.character(v[[1]] %||% "")[1]
  }
  rows <- vapply(sup, function(lc) paste(lc, .fld(lc, "grade"), .fld(lc, "metric_type"),
                                         .fld(lc, "construction_type"), .fld(lc, "portfolio_alpha_t"),
                                         .fld(lc, "oos_retention"), sep = "\x1f"),
                 character(1), USE.NAMES = FALSE)
  .sha1(paste(c(fh, rows), collapse = "\x1e"))
}

.lc_get <- function(corpus, lc, field, default = NULL) {
  idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
  if (length(idx)) corpus$lcodes[[idx[1]]][[field]] %||% default else default
}

# grade → 방향(win/loss) 정규화 (conditional direction_consistency 재정의용)
.grade_direction <- function(g) {
  g <- toupper(as.character(g %||% ""))
  if (g %in% c("A", "B") || startsWith(g, "A_") || g == "B_ARCHIVE") return("win")
  if (g %in% c("C", "F", "REJECT")) return("loss")
  NA_character_
}

# ── 축 1: Independence (r7 — construction 다양성, strategy_id 착시 폐기) ──
# direction_consistency (2026-07-04 국소수리 ②, 문턱 0.8 불변 — 도훈 confirm 대상 항목):
#   - positive/negative: 종전과 동일 = 전체 grade 최빈 비율.
#   - conditional: '전체 grade 일치'는 정의상 conditional(성공+실패 혼재)과 모순 → 영구 미달.
#     재정의 = '조건 축 내 일관성': win군(A/B)·loss군(C/F) 각각의 내부 grade 일관성의 min.
#     (조건부 규칙의 증거 품질 = 각 조건 가지 안에서 방향이 일관되는가.)
#
# v9 (2026-08-23) mode-local 재정의 — direction_basis = "win_loss":
#   구 정의는 '전체 grade 최빈 비율'이라 같은 방향인데 등급 문자가 갈리면(A 3 + B 2)
#   0.6 으로 떨어져 미달했다. 재는 대상은 등급 문자열이 아니라 **방향**이다.
#   positive/negative = 우세 방향 비율 ≥ 0.8 ∧ 구성 ≥2 / conditional·mixed = 구성 ≥2 ∧
#   win ≥2 ∧ loss ≥2 (조건부 규칙은 양 가지가 각각 증거를 가져야 성립).
#   tier=="global" 은 구 계산 그대로 — 전역 Law 문턱 불변(INV-1).
.axis_independence <- function(candidate, corpus, tier = "mode_local") {
  sup <- candidate$supporting_l_codes %||% character(0)
  polarity <- candidate$polarity %||% "unknown"
  constructions <- vapply(sup, function(lc) .lc_get(corpus, lc, "construction_type", "unknown"), character(1))
  grades <- vapply(sup, function(lc) as.character(.lc_get(corpus, lc, "grade", "?") %||% "?"), character(1))
  n_constr <- length(unique(constructions))
  dc_def <- "overall_grade_majority"

  if (identical(tier, "mode_local")) {
    cfg   <- .TIER$mode_local
    dirs  <- vapply(grades, .grade_direction, character(1), USE.NAMES = FALSE)
    n_win  <- sum(!is.na(dirs) & dirs == "win")
    n_loss <- sum(!is.na(dirs) & dirs == "loss")
    n_tot  <- length(dirs)
    share  <- if (n_tot) max(n_win, n_loss) / n_tot else 0
    if (polarity %in% c("conditional", "mixed")) {
      hp <- (n_constr >= cfg$indep_min_constructions &&
             n_win  >= cfg$conditional_min_win &&
             n_loss >= cfg$conditional_min_loss)
      dc_def <- "win_loss_both_arms (v9 mode-local — 조건부/혼재는 양 가지 각각 최소 건수)"
    } else {
      hp <- (n_constr >= cfg$indep_min_constructions && share >= cfg$indep_min_direction)
      dc_def <- "win_loss_max_share (v9 mode-local)"
    }
    score <- min(1.0, (n_constr / max(cfg$indep_min_constructions, 1)) * 0.6 +
                        (if (share >= cfg$indep_min_direction) 0.4 else share * 0.4))
    return(list(score = round(score, 3), hurdle_pass = hp,
                n_constructions = n_constr,
                direction_basis = cfg$direction_basis,
                n_win = n_win, n_loss = n_loss, n_direction_unknown = sum(is.na(dirs)),
                direction_consistency = round(share, 3),
                direction_consistency_definition = dc_def,
                reason = sprintf("%d distinct constructions (min %d), win=%d loss=%d unknown=%d, max_share=%.2f [%s]",
                                 n_constr, cfg$indep_min_constructions, n_win, n_loss,
                                 sum(is.na(dirs)), share,
                                 if (polarity %in% c("conditional", "mixed")) "both-arms" else "max-share")))
  }

  if (identical(polarity, "conditional")) {
    dirs <- vapply(grades, .grade_direction, character(1))
    grp_cons <- c()
    for (d in c("win", "loss")) {
      gg <- grades[!is.na(dirs) & dirs == d]
      if (length(gg)) grp_cons <- c(grp_cons, max(table(gg)) / length(gg))
    }
    consistency <- if (length(grp_cons)) min(grp_cons) else 0
    dc_def <- "within_condition_axis (2026-07-04 재정의 — 주간 리포트 도훈 confirm 대상)"
  } else {
    consistency <- if (length(grades)) max(table(grades)) / length(grades) else 0
  }
  min_c <- if (polarity == "negative") .HURDLE$indep_min_constructions_neg else .HURDLE$indep_min_constructions
  score <- min(1.0, (n_constr / max(min_c, 1)) * 0.6 + (if (consistency >= 0.8) 0.4 else consistency * 0.4))
  list(score = round(score, 3),
       hurdle_pass = (n_constr >= min_c && consistency >= .HURDLE$indep_min_direction),
       n_constructions = n_constr, direction_consistency = round(consistency, 3),
       direction_consistency_definition = dc_def,
       reason = sprintf("%d distinct constructions (min %d), direction_consistency=%.2f [%s]",
                        n_constr, min_c, consistency,
                        if (identical(polarity, "conditional")) "within-condition-axis" else "overall"))
}

# ── 축 2: Rigor (r7 — metric_type 게이트; INV-1) ──
#
# v9 (2026-08-23) mode-local = rigor_research 축:
#   구 mode-local 분기는 hurdle_pass 를 무조건 TRUE 로 두어(관대) 축이 사실상 없었다.
#   재정의 = **증거의 급**을 센다 — positive/conditional/mixed 는 grade A/B 이거나
#   metric_type ∈ {canonical_screen, backtested} 인 supporting L-code 가 ≥2건,
#   negative 는 C/F 가 ≥2건. (negative 의 frac ≥0.8 은 점수로만 남는다.)
#   자본 게이트(PORT_t 2.95)는 여기 없다 — 그것은 자본 층(promote_global/essence_score) 소관.
.axis_rigor <- function(candidate, corpus, tier) {
  sup <- candidate$supporting_l_codes %||% character(0)
  polarity <- candidate$polarity %||% "unknown"
  metrics <- vapply(sup, function(lc) .lc_get(corpus, lc, "metric_type", "estimated"), character(1))
  grades  <- vapply(sup, function(lc) .lc_get(corpus, lc, "grade", "?"), character(1))
  n_bt <- sum(metrics == "backtested")

  if (identical(tier, "mode_local")) {
    cfg <- .TIER$mode_local
    if (identical(polarity, "negative")) {
      n_fail   <- sum(toupper(as.character(grades)) %in% c("C", "F"))
      frac_all <- if (length(grades)) n_fail / length(grades) else 0
      return(list(score = round(frac_all, 3),
                  hurdle_pass = (n_fail >= cfg$negative_min_fail),
                  rigor_research = n_fail, n_backtested = n_bt,
                  reason = sprintf("negative C/F=%d (min %d) frac=%.2f [점수만] n_backtested=%d",
                                   n_fail, cfg$negative_min_fail, frac_all, n_bt)))
    }
    is_rig <- vapply(seq_along(sup), function(i)
      identical(.grade_direction(grades[i]), "win") ||
        (as.character(metrics[i]) %in% c("canonical_screen", "backtested")),
      logical(1))
    n_rig <- sum(is_rig)
    return(list(score = round(min(1.0, n_rig / max(cfg$rigor_research_min_n, 1)), 3),
                hurdle_pass = (n_rig >= cfg$rigor_research_min_n),
                rigor_research = n_rig, n_backtested = n_bt,
                reason = sprintf("rigor_research=%d (A/B 또는 canonical_screen/backtested, min %d) n_backtested=%d",
                                 n_rig, cfg$rigor_research_min_n, n_bt)))
  }

  if (polarity == "negative") {
    bt_idx <- metrics == "backtested"
    frac_bt  <- if (any(bt_idx)) sum(grades[bt_idx] %in% c("F", "C")) / sum(bt_idx) else 0
    frac_all <- if (length(grades)) sum(grades %in% c("F", "C")) / length(grades) else 0
    if (tier == "global") { sc <- frac_bt; hp <- (n_bt >= 1 && frac_bt >= .HURDLE$rigor_neg_frac_fail) }
    else { sc <- frac_all; hp <- frac_all >= .HURDLE$rigor_neg_frac_fail }
    return(list(score = round(sc, 3), hurdle_pass = hp, n_backtested = n_bt,
                reason = sprintf("negative frac_fail[%s]=%.2f (n_backtested=%d)", tier, sc, n_bt)))
  }
  pts <- suppressWarnings(as.numeric(vapply(sup, function(lc) {
    v <- .lc_get(corpus, lc, "portfolio_alpha_t", NA); if (is.null(v)) NA_real_ else as.numeric(v) }, numeric(1))))
  pts <- pts[!is.na(pts)]
  if (tier == "global") {
    weakest <- if (length(pts)) min(pts) else NA_real_
    sc <- if (!is.na(weakest)) min(1.0, weakest / .HURDLE$rigor_backtested_port_t) else 0
    hp <- (!is.na(weakest) && weakest >= .HURDLE$rigor_backtested_port_t && n_bt == length(sup))
  } else {
    sc <- if (length(pts)) min(1.0, mean(pts) / 1.5) else 0.4
    hp <- TRUE  # mode-local: rigor 관대(Independence/Mechanism으로 게이트)
  }
  list(score = round(sc, 3), hurdle_pass = hp, n_backtested = n_bt,
       reason = sprintf("positive port_t n=%d[%s] n_backtested=%d", length(pts), tier, n_bt))
}

# ── 축 3: Falsification (r7 — 적극 반증; negative auto +0.5 폐기) ──
# 2026-07-04 국소수리 ① (crash-safe): attempts에 문자열(비구조체) 기록 수용.
#   구 코드: 문자열 a에 a$result 접근 = "$ operator is invalid for atomic vectors" crash
#   → mode-wiring 배선 가동(문자열 falsification 적립분) 즉시 터질 latent 결함(A2-F2②).
#   보수 처리: 문자열 = n 카운트만 (none_falsified 판정 근거 없음 → TRUE 유지,
#   retained_ok 판정 불가 → 구조체 분만 평가). 구조체 [{test,result,effect_retained}] 권장.
# 2026-07-17 운영감사 수리 A1+A2 (5축 hurdle 정의 불변: attempts>=1 ∧ none_falsified ∧
#   survived건 retained>=0.5):
#   A1 crash-safe — result=survived ∧ effect_retained 비수치 → as.numeric NA → if(NA) crash
#     (07-11 스윕 2/40 후보 침묵 실패 실측). 비수치는 retained-pass 불인정(보수 FALSE)+WARN.
#   A2 result 토큰 정규화 — identical() 정확일치가 비정규 토큰('mechanism_falsified'/
#     'negative'/'passed' 등 원장 8건 실측)을 none_falsified=TRUE로 방치(관대 방향 누락,
#     L-RAMP-20260711_152314 실사례) → .fals_norm_result 소비. 미상 토큰 = 보수 방향
#     (falsified 취급 = 승격 차단 쪽, INV-4: 불확실은 승격 금지 쪽)+WARN.
#     'diagnostic'은 emit 규약(run_alpha_search DSR 등 게이트-비적용 진단 산출)상
#     기존 중립 의미 유지 — 반증도 생존도 아님(retained 요건 비적용).
.fals_norm_result <- function(res) {
  s <- tolower(trimws(as.character(res %||% "")[1]))
  if (is.na(s) || !nzchar(s)) return("unknown")
  if (grepl("falsif", s, fixed = TRUE) || identical(s, "negative")) return("falsified")
  if (grepl("surviv", s, fixed = TRUE) || identical(s, "passed")) return("survived")
  if (grepl("weaken", s, fixed = TRUE)) return("weakened")
  if (identical(s, "diagnostic")) return("diagnostic")
  "unknown"
}

.axis_falsification <- function(candidate) {
  attempts_raw <- candidate$falsification_draft$attempts %||% list()
  if (is.character(attempts_raw)) attempts_raw <- as.list(attempts_raw)  # 최상위 chr vector 수용
  structured <- Filter(function(a) is.list(a), attempts_raw)
  n_string <- length(attempts_raw) - length(structured)
  n <- length(attempts_raw)
  raw_tok <- vapply(structured, function(a) as.character(a$result %||% "")[1], character(1))
  res_norm <- vapply(raw_tok, .fals_norm_result, character(1), USE.NAMES = FALSE)
  n_nonstd <- sum(!(tolower(trimws(raw_tok)) %in% c("survived", "falsified", "weakened", "diagnostic")))
  n_unknown <- sum(res_norm == "unknown")
  if (n_unknown) {
    cat(sprintf("[promote][WARN] falsification result 미상 토큰 %d건(%s) — 보수 처리(falsified 취급, INV-4)\n",
                n_unknown, paste(unique(raw_tok[res_norm == "unknown"]), collapse = " | ")))
    res_norm[res_norm == "unknown"] <- "falsified"
  }
  retained_vec <- vapply(seq_along(structured), function(i) {
    if (!identical(res_norm[[i]], "survived")) return(TRUE)
    er <- suppressWarnings(tryCatch(as.numeric(structured[[i]]$effect_retained %||% NA)[1],
                                    error = function(e) NA_real_))
    if (!is.finite(er)) return(NA)  # 비수치 표식 → 아래 보수 FALSE (A1 crash-safe)
    er >= .HURDLE$fals_min_retained
  }, logical(1))
  n_retained_nonnum <- sum(is.na(retained_vec))
  if (n_retained_nonnum) {
    cat(sprintf("[promote][WARN] survived건 effect_retained 비수치 %d건 — retained-pass 불인정(보수 FALSE, crash-safe)\n",
                n_retained_nonnum))
    retained_vec[is.na(retained_vec)] <- FALSE
  }
  retained_ok <- if (length(retained_vec)) all(retained_vec) else TRUE
  none_falsified <- !any(res_norm == "falsified")
  score <- min(1.0, (if (n >= 1) 0.5 else 0) + (if (n >= 3) 0.3 else 0) + (if (retained_ok && n >= 1) 0.2 else 0))
  list(score = round(score, 3),
       hurdle_pass = (n >= .HURDLE$fals_min_attempts && none_falsified && retained_ok),
       n_attempts = n, n_unstructured = n_string,
       n_result_nonstandard = n_nonstd, n_retained_nonnumeric = n_retained_nonnum,
       reason = sprintf("active attempts=%d (unstructured=%d, nonstd_result=%d, retained_nonnum=%d) none_falsified=%s retained_ok=%s%s",
                        n, n_string, n_nonstd, n_retained_nonnum, none_falsified, retained_ok,
                        if (n_string) " [문자열 기록 — 구조체 전환 권장]" else ""))
}

# ── 축 4: External (OOS — 2026-07-03 재정의, 도훈 confirm / 감사 GOV-01·AXM-01) ──
# hurdle = supporting L-code corpus의 oos_retention 실값 존재 AND cluster median >= 0.5.
#   - 1차 소스: corpus 직접 조회(supporting_l_codes → oos_retention).
#   - 폴백: corpus 실값 0건이면 candidate$oos_validation_draft$oos_effect_vs_is
#     (cluster_extractor._draft_oos가 oos_retention median을 이 필드에 기록).
#   - oos_months는 hurdle에서 강등 — 실값 존재 ∧ >= ext_min_oos_months 시 score +0.2 가산 증거만.
.axis_external <- function(candidate, corpus) {
  sup <- unique(as.character(candidate$supporting_l_codes %||% character(0)))
  rets <- suppressWarnings(as.numeric(vapply(sup, function(lc) {
    v <- .lc_get(corpus, lc, "oos_retention", NA)
    if (is.null(v) || !length(v)) NA_character_ else as.character(v[[1]]) }, character(1))))
  rets_real <- rets[!is.na(rets)]
  n_real <- length(rets_real)
  src <- "corpus"
  o <- candidate$oos_validation_draft %||% list()
  if (!n_real) {  # 폴백: extractor가 기록한 oos_retention median (oos_effect_vs_is 필드)
    v_draft <- suppressWarnings(as.numeric(o$oos_effect_vs_is %||% NA))
    if (!is.na(v_draft)) { rets_real <- v_draft; n_real <- 1L; src <- "draft" }
  }
  med <- if (n_real) stats::median(rets_real) else NA_real_
  m <- suppressWarnings(as.numeric(o$oos_months %||% NA))
  months_bonus <- (!is.na(m) && m >= .HURDLE$ext_min_oos_months)
  score <- min(1.0, (if (n_real >= 1) 0.4 else 0) +
                    (if (!is.na(med) && med >= .HURDLE$ext_min_oos_retention) 0.4 else 0) +
                    (if (months_bonus) 0.2 else 0))
  list(score = round(score, 3),
       hurdle_pass = (n_real >= 1 && !is.na(med) && med >= .HURDLE$ext_min_oos_retention),
       n_oos_retention_real = n_real, oos_retention_median = if (is.na(med)) NA_real_ else round(med, 3),
       oos_retention_source = src, oos_months = m, oos_months_bonus = months_bonus,
       reason = sprintf("oos_retention real n=%d/%d (src=%s) median=%s (min %.2f) | months=%s bonus=%s",
         n_real, length(sup), src, if (is.na(med)) "NA" else sprintf("%.3f", med),
         .HURDLE$ext_min_oos_retention, if (is.na(m)) "NA" else m, months_bonus))
}

# ── 축 5: Mechanism ──
.axis_mechanism <- function(candidate) {
  m <- candidate$mechanism_draft %||% list()
  expl <- m$economic_explanation %||% NA
  mtype <- m$mechanism_type %||% "unknown"
  caus <- m$causal_plausibility %||% NA
  has_expl <- !is.na(expl) && nzchar(as.character(expl)) && tolower(as.character(expl)) != "null"
  score <- min(1.0, (if (has_expl) 0.4 else 0) + (if (!is.na(mtype) && mtype != "unknown") 0.3 else 0) +
               (if (!is.na(caus) && caus %in% c("moderate", "moderate_to_high", "high")) 0.3 else 0))
  list(score = round(score, 3), hurdle_pass = (has_expl && mtype != "unknown"),
       mechanism_type = mtype, reason = sprintf("expl=%s type=%s", if (has_expl) "present" else "MISSING", mtype))
}

.weights <- function(type) {
  if (type == "methodological") c(I = 0.15, R = 0.20, F = 0.30, E = 0.15, M = 0.20)
  else c(I = 0.25, R = 0.25, F = 0.20, E = 0.20, M = 0.10)
}

# ── 메인: mode-local 승격 (INV-1/4 + v9 사다리) ──
# verdict 4종 (표준 토큰 — 소비자가 grep 한다):
#   PASS           양성/조건부/혼재 통과 → active/modes/<mode>/AX-<MODE>-NNN.json status=proposed
#   MAP            음성 통과 → 공리 아님. DIST 탐색지도 카드 자동 활성화(INV-7 map)
#   FAIL           hurdle 미달 → review_log AX-PENDING_<cluster_key>.json (history append)
#   SKIP_SINGLETON 단일 L-code — 독립성 축이 원리상 불가(재채점해도 결과가 같다)
#   SKIP_UNKNOWN   polarity 미상 — 사다리 판정 대상 아님
promote_to_axiom <- function(candidate_path, threshold = 0.80, auto_inject = NULL,
                             dry_run = FALSE) {
  if (!file.exists(candidate_path)) stop("candidate not found: ", candidate_path)
  candidate <- fromJSON(candidate_path, simplifyVector = FALSE)
  root <- .px_root()
  cp <- file.path(root, ".cache", "lcode_corpus.json")
  if (!file.exists(cp)) stop("lcode_corpus.json 없음 — harvester 먼저 실행")
  corpus <- fromJSON(cp, simplifyVector = FALSE)

  mode <- candidate$research_mode %||% "qepm_legacy"
  if (!(mode %in% names(.MODE_PREFIX)))
    cat(sprintf("[promote][WARN] research_mode='%s'는 .MODE_PREFIX 미등재 — prefix 'GEN' 폴백 (lcode_schema LCODE_VALID_MODES 정합 확인 필요)\n", mode))
  cand_metric <- candidate$metric_type %||% "estimated"
  tier <- "mode_local"
  cfg <- .TIER[[tier]]
  type <- candidate$type %||% "empirical"
  polarity <- candidate$polarity %||% "unknown"
  sup <- candidate$supporting_l_codes %||% character(0)
  ckey <- .cluster_key_of(candidate)
  cid <- candidate$candidate_id %||% sub("\\.json$", "", basename(candidate_path))
  dry_tag <- if (isTRUE(dry_run)) "[dry-run] " else ""

  # ── 조기 SKIP (재채점 자체가 무의미한 두 부류 — Rscript 스폰·review_log 쓰기 회피) ──
  .skip <- function(tok, why) {
    cat(sprintf("[promote] %s%s (%s/%s mode=%s) %s → %s\n", dry_tag, cid, type, polarity, mode, why, tok))
    invisible(list(candidate_id = cid, cluster_key = ckey, mode = mode, tier = tier,
                   polarity = polarity, verdict = tok, skipped = TRUE, passed = FALSE,
                   dry_run = isTRUE(dry_run), checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  }
  if (polarity %in% cfg$skip_polarity)
    return(.skip("SKIP_UNKNOWN", "polarity 미상 — 방향 없는 클러스터는 사다리 판정 대상 아님"))
  if (length(sup) < 2L)
    return(.skip("SKIP_SINGLETON", sprintf("supporting L-code %d건 — independence 원리상 불가", length(sup))))

  I <- .axis_independence(candidate, corpus, tier)
  R <- .axis_rigor(candidate, corpus, tier)
  Fx <- .axis_falsification(candidate)
  E <- .axis_external(candidate, corpus)
  M <- .axis_mechanism(candidate)

  w <- .weights(type)
  weighted <- round(as.numeric(w["I"] * I$score + w["R"] * R$score + w["F"] * Fx$score + w["E"] * E$score + w["M"] * M$score), 3)
  axes <- list(independence = I, rigor = R, falsification = Fx, external = E, mechanism = M)
  hurdle_names <- cfg$hurdle_axes
  hurdles <- vapply(hurdle_names, function(a) isTRUE(axes[[unname(.AXIS_KEY[a])]]$hurdle_pass),
                    logical(1), USE.NAMES = FALSE)
  all_hurdles <- all(hurdles)
  # v9: passed_rule = "all_hurdles" — weighted 는 랭킹용으로만 남는다(문턱 아님).
  passed <- if (identical(cfg$passed_rule, "all_hurdles")) all_hurdles else (all_hurdles && weighted >= threshold)
  verdict <- if (!passed) "FAIL" else if (identical(polarity, "negative")) "MAP" else "PASS"

  report <- list(candidate_id = cid, cluster_key = ckey, mode = mode, tier = tier, metric_type = cand_metric,
    type = type, polarity = polarity, verdict = verdict, dry_run = isTRUE(dry_run),
    candidate_sha = .candidate_sha(candidate_path, corpus),
    axes = axes,
    hurdle_axes = as.list(hurdle_names),
    hurdle_pass = stats::setNames(as.list(hurdles), hurdle_names),
    weights = as.list(w), weighted_score = weighted, threshold = threshold,
    passed_rule = cfg$passed_rule,
    all_hurdles_pass = all_hurdles, passed = passed, checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

  cat(sprintf("[promote] %s%s (%s/%s mode=%s metric=%s key=%s) weighted=%.3f hurdles[%s]=%s → %s\n",
    dry_tag, cid, type, polarity, mode, cand_metric, ckey, weighted,
    paste(hurdle_names, collapse = "/"), paste(ifelse(hurdles, "P", "F"), collapse = ""), verdict))
  for (an in names(report$axes)) { ax <- report$axes[[an]]
    cat(sprintf("  %-13s %.2f hurdle=%-5s %s\n", an, ax$score, ax$hurdle_pass, ax$reason)) }

  if (identical(verdict, "PASS")) {
    if (isTRUE(dry_run)) {
      # dry-run 도 **정제는 돌린다**(쓰기 0). 그래야 주간 2-pass 회로차단기가 "이번 스윕이
      #   몇 건을 활성화하려 하는가"를 쓰기 전에 셀 수 있다(weekly_cleaner_sweep.R:536).
      rf <- .call_refine_statement(candidate, corpus, root = root)
      report$refine_verdict <- as.character(rf$verdict %||% "HELD")[1]
      report$refine_failing <- rf$failing %||% list()
      report$refine_input_sha <- as.character(rf$refine_input_sha %||% NA_character_)[1]
      report$statement_inject <- as.character(rf$statement_inject %||% "")[1]
      .exists_ck <- length(list.files(file.path(root, "qepm/memory/axioms/active/modes"),
                                      pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)) > 0
      report$would_activate <- identical(report$refine_verdict, "REFINED") &&
        .unattended_enabled() && isTRUE(.cap_ok(mode, file.path(root, "qepm/memory/axioms/active"), root = root)) &&
        is.null(.tombstone_lookup(ckey, root = root))
      cat(sprintf("  (dry-run) 승격 대상 — refine=%s%s · would_activate=%s (미기록)\n",
                  report$refine_verdict,
                  if (length(report$refine_failing)) paste0("(", paste(unlist(report$refine_failing), collapse = ","), ")") else "",
                  report$would_activate))
    } else {
      ap <- .promote_to_active(candidate, report, mode, root = root, corpus = corpus)
      report$active_path <- ap$path
      report$promote_action <- ap$action
      report$axiom_status <- ap$status
      report$refine_verdict <- as.character(ap$refine$verdict %||% "HELD")[1]
      report$refine_failing <- ap$refine$failing %||% list()
      report$refine_input_sha <- as.character(ap$refine$refine_input_sha %||% NA_character_)[1]
      report$cap_ok <- isTRUE(ap$cap_ok)
      # tombstone 소비 = 파일 미생성. verdict 를 바꿔 원장·다이제스트가 그것을 볼 수 있게 한다.
      if (identical(ap$action, "tombstoned")) {
        verdict <- "SKIP_TOMBSTONED"; report$verdict <- verdict
        cat(sprintf("[promote] %s%s → %s\n", dry_tag, cid, verdict))
      } else if (identical(report$refine_verdict, "REFINED") && .unattended_enabled() &&
                 !isTRUE(ap$cap_ok) && !identical(ap$status, "active")) {
        report$cap_verdict <- "FAIL_CAP"
      }
      # ★L-code 역링크(promoted_to_axiom)는 **활성 전환 시점 1회**만 기록한다
      #   (.maybe_write_back_links + backlinks_written 가드). 멱등 무변경 경로에서는 쓰지 않는다.
      do_inject <- if (is.null(auto_inject)) as.integer(Sys.getenv("QVEST_AXIOM_AUTO_INJECT", "0")) == 1 else isTRUE(auto_inject)
      if (do_inject && identical(ap$status, "active") && !is.na(ap$path)) {
        inj <- file.path(root, "02_Infrastructure", "axiom", "inject.R")
        if (file.exists(inj)) { source(inj, local = TRUE); if (exists("inject_axiom", mode = "function")) try(inject_axiom(ap$path)) }
      } else if (!do_inject) {
        cat("[promote] inject.R 생략 (QVEST_AXIOM_AUTO_INJECT != 1) — 주입면 도달은 axiom_context_inject.sh 가 status=active 로 판정한다\n")
      }
    }
  } else if (identical(verdict, "MAP")) {
    # INV-7: 음성은 Law 가 아니라 **탐색지도**다. 공리 파일을 만들지 않는다.
    if (isTRUE(dry_run)) {
      cat(sprintf("  (dry-run) 음성 지도 대상 — DIST(cluster_key=%s) 카드 자동 활성화 미실행\n", ckey))
    } else {
      report$auto_map <- .call_auto_map_negative(ckey, root)
    }
  } else {
    if (isTRUE(dry_run)) cat("  (dry-run) review_log 미기록\n")
    else report$review_log_path <- .log_partial(candidate, report, root = root)
  }
  report
}

# distilled.R::auto_map_negative 호출 래퍼 (fail-soft — 지도 실패가 판정을 무효화하지 않는다)
.call_auto_map_negative <- function(cluster_key, root = .px_root()) {
  ds <- file.path(root, "02_Infrastructure", "axiom", "distilled.R")
  if (!file.exists(ds)) { cat("[promote][WARN] distilled.R 부재 — 음성 지도 생략\n"); return(list(status = "distilled_R_missing")) }
  tryCatch({
    env <- new.env(parent = globalenv())
    suppressWarnings(suppressMessages(sys.source(ds, envir = env)))
    if (!exists("auto_map_negative", envir = env, mode = "function"))
      return(list(status = "auto_map_negative_missing"))
    env$auto_map_negative(cluster_key, root = root)
  }, error = function(e) {
    cat(sprintf("[promote][WARN] 음성 지도 실패(비차단): %s\n", conditionMessage(e)))
    list(status = "error", message = conditionMessage(e))
  })
}

# ── v9.1 커밋13: statement 정제기 호출 래퍼 ─────────────────────────────────
# .call_auto_map_negative(위)와 같은 패턴 — 별도 env 로 sys.source 후 함수 호출.
#   ★.fals_norm_result 를 **인자로 넘긴다**. 정제기가 반증 결산을 자기 판본으로 다시
#     구현하면 result 토큰 정규화가 두 벌이 되고, 한쪽만 고쳐졌을 때 어느 검사에도 안 보인다.
#   fail-soft: 정제 실패는 판정을 무효화하지 않고 verdict="HELD" 로 취급한다(승격 차단 쪽 —
#   INV-4 "불확실은 승격 금지 쪽").
.call_refine_statement <- function(candidate, corpus, root = .px_root(), peers = NULL) {
  rs <- file.path(root, "02_Infrastructure", "axiom", "refine_statement.R")
  if (!file.exists(rs)) {
    cat("[promote][WARN] refine_statement.R 부재 — 정제 생략(HELD 취급)\n")
    return(list(verdict = "HELD", failing = list("refiner_missing"),
                statement = NULL, statement_inject = NULL, refine_input_sha = NA_character_,
                gates = list()))
  }
  tryCatch({
    had <- Sys.getenv("REFINE_SOURCED", NA_character_)
    Sys.setenv(REFINE_SOURCED = "1")
    on.exit(if (is.na(had)) Sys.unsetenv("REFINE_SOURCED") else Sys.setenv(REFINE_SOURCED = had),
            add = TRUE)
    env <- new.env(parent = globalenv())
    suppressWarnings(suppressMessages(sys.source(rs, envir = env)))
    if (!exists("refine_statement", envir = env, mode = "function"))
      return(list(verdict = "HELD", failing = list("refine_statement_missing"), gates = list()))
    env$refine_statement(candidate, corpus = corpus, fals_norm = .fals_norm_result,
                         peers = peers, root = root)
  }, error = function(e) {
    cat(sprintf("[promote][WARN] 정제 실패(비차단, HELD 취급): %s\n", conditionMessage(e)))
    list(verdict = "HELD", failing = list(paste0("refiner_error:", conditionMessage(e))),
         gates = list())
  })
}

# ── v9.1 커밋16: 무인 활성화 kill switch (런타임 — 코드 변경 없이 초 단위 정지) ──
.unattended_enabled <- function() identical(Sys.getenv("QVEST_AXIOM_UNATTENDED", "1"), "1")

# ── v9.1 커밋14: 활성 상한 ──────────────────────────────────────────────────
list_active_axioms <- function(mode = NULL, root = .px_root()) {
  md <- file.path(root, "qepm", "memory", "axioms", "active", "modes")
  if (!dir.exists(md)) return(list())
  out <- list()
  for (f in list.files(md, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)) {
    a <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(a) || !identical(as.character(a$status %||% "")[1], "active")) next
    m <- as.character(a$research_mode %||% "unknown")[1]
    if (!is.null(mode) && !identical(m, mode)) next
    out[[length(out) + 1L]] <- list(axiom_id = as.character(a$axiom_id %||% sub("\\.json$", "", basename(f)))[1],
                                    mode = m, polarity = as.character(a$polarity %||% "?")[1],
                                    refine_verdict = as.character(a$refine_verdict %||% "?")[1],
                                    statement_inject = as.character(a$statement_inject %||% "")[1],
                                    path = f)
  }
  out
}
.cap_ok <- function(mode, active_dir, root = NULL) {
  root <- root %||% dirname(dirname(dirname(dirname(active_dir))))
  act <- tryCatch(list_active_axioms(root = root), error = function(e) list())
  n_tot <- length(act)
  n_mode <- sum(vapply(act, function(a) identical(a$mode, mode), logical(1)))
  ok <- (n_mode < .TIER$mode_local$max_active_per_mode) && (n_tot < .TIER$mode_local$max_active_total)
  attr(ok, "detail") <- sprintf("mode=%s %d/%d · total %d/%d", mode, n_mode,
                                .TIER$mode_local$max_active_per_mode, n_tot,
                                .TIER$mode_local$max_active_total)
  ok
}

# ── v9.1 커밋14: tombstone ──────────────────────────────────────────────────
# 없으면 롤백이 **1주일짜리 임시조치**가 된다: .promote_to_active 의 멱등 검사는
#   active/modes/** 만 스캔하므로, deprecated/ 로 옮겨진 클러스터를 다음 주 스윕이
#   새 번호로 재발급한다(AX-AS-001 롤백 → 다음 주 AX-AS-003 으로 부활).
# INV-7 정신: 영구 금지가 아니다 — clear_tombstone() + revive_condition 이 해제 경로다.
.tombstone_path <- function(root) file.path(root, "qepm", "memory", "axioms", "tombstones.json")
.tombstone_load <- function(root) {
  p <- .tombstone_path(root)
  if (!file.exists(p)) return(list(schema_version = "v1_axiom_tombstone", entries = list()))
  d <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d) || is.null(d$entries)) list(schema_version = "v1_axiom_tombstone", entries = list()) else d
}
.tombstone_lookup <- function(cluster_key, root = .px_root()) {
  ck <- as.character(cluster_key %||% "")[1]
  if (!nzchar(ck)) return(NULL)
  for (e in .tombstone_load(root)$entries) {
    if (identical(as.character(e$cluster_key %||% "")[1], ck) &&
        !isTRUE(e$cleared)) return(e)
  }
  NULL
}
.tombstone_append <- function(root, cluster_key, axiom_id, source_candidate, reason,
                              revive_condition = NULL) {
  d <- .tombstone_load(root)
  d$entries[[length(d$entries) + 1L]] <- list(
    cluster_key = as.character(cluster_key %||% "")[1],
    axiom_id = as.character(axiom_id %||% "")[1],
    rolled_back_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    source_candidate = as.character(source_candidate %||% "")[1],
    reason = as.character(reason)[1],
    revive_condition = if (is.null(revive_condition)) NULL else as.character(revive_condition)[1],
    cleared = FALSE)
  d$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  write_json(d, .tombstone_path(root), pretty = TRUE, auto_unbox = TRUE, null = "null")
  invisible(d)
}
clear_tombstone <- function(cluster_key, reason, root = .px_root()) {
  if (missing(reason) || !nzchar(as.character(reason)[1]))
    stop("clear_tombstone: reason 필수 (해제 사유 없는 해제는 기록이 아니다)")
  d <- .tombstone_load(root); ck <- as.character(cluster_key)[1]; n <- 0L
  for (i in seq_along(d$entries)) {
    if (identical(as.character(d$entries[[i]]$cluster_key %||% "")[1], ck) && !isTRUE(d$entries[[i]]$cleared)) {
      d$entries[[i]]$cleared <- TRUE
      d$entries[[i]]$cleared_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
      d$entries[[i]]$cleared_reason <- as.character(reason)[1]
      n <- n + 1L
    }
  }
  if (n) {
    d$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    write_json(d, .tombstone_path(root), pretty = TRUE, auto_unbox = TRUE, null = "null")
  }
  cat(sprintf("[promote] tombstone 해제 %d건 (cluster_key=%s)\n", n, ck))
  invisible(n)
}

# ★deprecated/ 도 스캔한다(커밋14). 롤백된 AX-AS-001 이 deprecated/AX-AS-001_rollback_*.json
#   으로 옮겨진 뒤에도 그 번호를 다시 쓰면 원장·역링크·다이제스트에서 두 공리가 같은 이름으로
#   충돌한다. 번호는 **재사용하지 않는다**.
.next_axiom_id <- function(active_dir, mode = NULL) {
  dep_dir <- file.path(dirname(active_dir), "deprecated")
  .dep_nums <- function(pat) {
    fs <- if (dir.exists(dep_dir)) list.files(dep_dir, pattern = pat) else character(0)
    if (!length(fs)) return(integer(0))
    m <- regmatches(fs, regexpr(pat, fs, perl = TRUE))
    as.integer(sub(pat, "\\1", m, perl = TRUE))
  }
  if (is.null(mode)) {
    files <- list.files(active_dir, pattern = "^AX-\\d+\\.json$")
    nums <- as.integer(sub("AX-(\\d+)\\.json", "\\1", files)); nums <- nums[!is.na(nums)]
    dn <- .dep_nums("^AX-(\\d+)_.*"); nums <- c(nums, dn[!is.na(dn)])
    return(if (!length(nums)) "AX-003" else sprintf("AX-%03d", max(nums) + 1L))
  }
  prefix <- .mode_prefix(mode)
  md <- file.path(active_dir, "modes", mode)
  files <- if (dir.exists(md)) list.files(md, pattern = sprintf("^AX-%s-\\d+\\.json$", prefix)) else character(0)
  nums <- as.integer(sub(sprintf("AX-%s-(\\d+)\\.json", prefix), "\\1", files)); nums <- nums[!is.na(nums)]
  dn <- .dep_nums(sprintf("^AX-%s-(\\d+)[_.].*", prefix)); nums <- c(nums, dn[!is.na(dn)])
  sprintf("AX-%s-%03d", prefix, if (length(nums)) max(nums) + 1L else 1L)
}

# v9.1 (2026-08-23 커밋13/14/16): 승격 산출물의 status 는 **정제 verdict 가 정한다**.
#   REFINED ∧ QVEST_AXIOM_UNATTENDED=1 ∧ 상한 여유  → status="active"  (무인 활성화)
#   그 외                                            → status="proposed" (HELD — 주입 안 됨)
#   구 v9 는 전건 proposed + 도훈 1줄 confirm 이었다. E-1 이 그 승인을 **품질 게이트로 대체**한다:
#   승인이 하던 일("이 문장이 대전제로 설 자격이 있는가")을 refine_statement.R 의 R0~R6 가 한다.
#   되돌리기 = QVEST_AXIOM_UNATTENDED=0(초) · deactivate_axiom()(분) · rollback_axiom()(영구).
# ★멱등: 같은 cluster_key 의 공리가 이미 있으면 **새 파일을 만들지 않는다**. 없으면 매주 새
#   번호가 발급돼 AX-AS-001..NNN 이 무한 증식한다. 단 기존 파일에 대해서도 **재정제는 돈다** —
#   입력(corpus)이 바뀌면 HELD 가 REFINED 로 뒤집힐 수 있어야 "실패 = 영구 SKIP 없음"(AX-000)이
#   성립한다. 재정제 결과가 직전과 같으면(sha·verdict 동일) **한 바이트도 쓰지 않는다**.
# ★역링크(promoted_to_axiom)는 **활성 전환 시점에 딱 한 번**만 쓴다(backlinks_written 가드).
#   supporting 743 고유 L-code 중 175건이 2개 이상 공리에 중복 소유돼 있고 promoted_to_axiom 은
#   스칼라다 — 주간 무조건 재기록이면 두 공리가 매주 서로를 덮어쓴다.
.promote_to_active <- function(candidate, report, mode, root = .px_root(), corpus = NULL) {
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  out_dir <- file.path(active_dir, "modes", mode)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ckey <- report$cluster_key %||% .cluster_key_of(candidate)
  cid  <- report$candidate_id %||% (candidate$candidate_id %||% "")

  # 정제 verdict 를 status 판정 + 문장 산출의 단일 원천으로 쓴다.
  refine <- .call_refine_statement(candidate, corpus, root = root)
  refined <- identical(as.character(refine$verdict %||% ""), "REFINED")
  cap <- .cap_ok(mode, active_dir, root = root)
  unattended <- .unattended_enabled()
  want_active <- refined && unattended && isTRUE(cap)
  if (refined && unattended && !isTRUE(cap))
    cat(sprintf("[promote][FAIL_CAP] 활성 상한 초과 — %s (자동 축출 없음: deactivate_axiom()/rollback_axiom() 은 사람이 부른다)\n",
                attr(cap, "detail")))

  .apply_refine <- function(ax) {
    prev_sha <- as.character(ax$refine_input_sha %||% "")[1]
    ax$refine_verdict <- as.character(refine$verdict %||% "HELD")[1]
    ax$refine_failing <- refine$failing %||% list()
    ax$refine_gates <- if (length(refine$gates))
      lapply(refine$gates, function(g) isTRUE(g$pass)) else list()
    ax$refine_input_sha <- as.character(refine$refine_input_sha %||% NA_character_)[1]
    ax$refine_attempts <- as.integer(ax$refine_attempts %||% 0L) + 1L
    ax$refined_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    if (!is.null(refine$statement_inject)) ax$statement_inject <- refine$statement_inject
    if (refined && !is.null(refine$statement) && nzchar(refine$statement)) {
      ax$statement <- refine$statement; ax$canonical_statement <- refine$statement
      ax$text <- refine$statement
    }
    # v9 INV-6 표기는 이제 정제 verdict 가 정본이다(구 regex 는 backstop 으로 아래 유지).
    ax$needs_refinement <- !refined
    if (!refined) {
      # 동일 입력으로 8주 연속 HELD = held_stale. **삭제하지 않는다**(AX-000) — 라벨만 바꾼다.
      if (!identical(prev_sha, ax$refine_input_sha) || is.null(ax$refine_held_since))
        ax$refine_held_since <- format(Sys.Date())
      wk <- suppressWarnings(as.numeric(Sys.Date() - as.Date(as.character(ax$refine_held_since)[1]))) / 7
      if (is.finite(wk) && wk >= .TIER$mode_local$held_stale_weeks %||% 8) ax$status <- "held_stale"
    } else ax$refine_held_since <- NULL
    ax
  }

  # ── ① 멱등 스캔 ──
  for (f in list.files(file.path(active_dir, "modes"), pattern = "^AX-.*\\.json$",
                       full.names = TRUE, recursive = TRUE)) {
    a <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(a)) next
    if (identical(as.character(a$cluster_key %||% ""), ckey) ||
        identical(as.character(a$promotion$source_candidate %||% ""), as.character(cid))) {
      before_sha <- as.character(a$refine_input_sha %||% "")[1]
      before_v   <- as.character(a$refine_verdict %||% "")[1]
      before_st  <- as.character(a$status %||% "proposed")[1]
      b <- .apply_refine(a)
      # 활성 전환은 여기서만 일어난다 — proposed/held_stale → active.
      if (want_active && !identical(before_st, "active")) b$status <- "active"
      else if (!identical(before_st, "active") && is.null(b$status)) b$status <- before_st
      after_st <- as.character(b$status %||% before_st)[1]
      changed <- !(identical(before_sha, as.character(b$refine_input_sha %||% "")[1]) &&
                     identical(before_v, as.character(b$refine_verdict %||% "")[1]) &&
                     identical(before_st, after_st))
      if (!changed) {
        cat(sprintf("[promote] 기존 공리 유지(무쓰기 — 정제 입력·판정 불변) → %s [status=%s refine=%s]\n",
                    f, before_st, before_v))
      } else {
        b$confirm_required <- NULL
        write_json(b, f, pretty = TRUE, auto_unbox = TRUE, null = "null")
        cat(sprintf("[promote] 기존 공리 갱신 → %s [status=%s→%s refine=%s%s]\n", f, before_st, after_st,
                    b$refine_verdict,
                    if (length(b$refine_failing)) paste0(" fail=", paste(unlist(b$refine_failing), collapse = ",")) else ""))
        if (identical(after_st, "active") && !identical(before_st, "active"))
          .maybe_write_back_links(b, f, root = root)
      }
      # 자기치유: sot_map 이 뒤처져 있으면(등재 누락/status 불일치) 여기서 맞춘다.
      #   등재 자체가 memory_knowledge_health HARD_3 계약이므로 공리 파일만 있고 map 이
      #   비면 다음 헬스체크가 HARD FAIL 로 선다 — 무쓰기 경로에서도 정합을 지킨다.
      .update_sot_map(as.character(b$axiom_id %||% sub("\\.json$", "", basename(f)))[1],
                      as.character(b$research_mode %||% mode)[1], b, root = root)
      return(list(path = f, action = if (changed) "updated" else "unchanged",
                  status = after_st, refine = refine, cap_ok = isTRUE(cap)))
    }
  }

  # ── ② tombstone 소비 (멱등 스캔 직후 — 롤백된 클러스터의 새 번호 재발급 차단) ──
  ts <- .tombstone_lookup(ckey, root = root)
  if (!is.null(ts)) {
    cat(sprintf("[promote] SKIP_TOMBSTONED — cluster_key=%s 는 %s 에 롤백됨(%s). 파일 미생성.\n",
                ckey, as.character(ts$rolled_back_at %||% "?")[1], as.character(ts$reason %||% "?")[1]))
    cat(sprintf("[promote]   해제: Rscript -e 'source(\"02_Infrastructure/axiom/promote.R\"); clear_tombstone(\"%s\", reason=\"...\")'%s\n",
                ckey, if (!is.null(ts$revive_condition))
                  sprintf(" | 부활 조건: %s", as.character(ts$revive_condition)[1]) else ""))
    return(list(path = NA_character_, action = "tombstoned", status = NA_character_,
                refine = refine, cap_ok = isTRUE(cap)))
  }

  # ── ③ 신규 발행 ──
  ax_id <- .next_axiom_id(active_dir, mode)
  polarity <- candidate$polarity %||% "unknown"
  epistemic <- "research_tier"   # v9: 리서치 층 산출 — 자본 층 Law 아님
  stmt <- candidate$statement_draft %||% ""

  axiom <- list(
    axiom_id = ax_id, memory_id = ax_id, id = ax_id,
    research_mode = mode, tier = "mode_local",
    cluster_key = ckey,
    metric_type = candidate$metric_type %||% "estimated",
    epistemic_status = epistemic,
    type = candidate$type, polarity = polarity,
    statement = stmt, canonical_statement = stmt, text = stmt,
    supporting_l_codes = candidate$supporting_l_codes,
    scope = candidate$scope_draft %||% list(),
    evidence = candidate$evidence_draft %||% list(),
    falsification = candidate$falsification_draft %||% list(),
    mechanism = candidate$mechanism_draft %||% list(),
    oos_validation = candidate$oos_validation_draft %||% list(),
    promotion = list(source_candidate = candidate$candidate_id, weighted_score = report$weighted_score,
      threshold = report$threshold, all_hurdles_pass = report$all_hurdles_pass,
      axis_scores = lapply(report$axes, function(a) a$score),
      promoted_at = format(Sys.Date()), next_review = format(Sys.Date() + 90)),
    enforcement = "", enforcement_mode = "documented",  # INV-2
    status = if (want_active) "active" else "proposed", version = 1L
  )
  axiom <- .apply_refine(axiom)
  # INV-6 backstop — 정제기가 부재/실패해도 초안 마커는 여전히 잡는다(정본은 refine_verdict).
  if (grepl("\\[.*초안.*\\]|확정 필요", as.character(axiom$statement %||% "")[1])) {
    cat(sprintf("[promote][INV-6 backstop] %s statement 가 여전히 cluster 초안 — needs_refinement=TRUE\n", ax_id))
    axiom$needs_refinement <- TRUE
    if (identical(as.character(axiom$status %||% "")[1], "active")) axiom$status <- "proposed"
  }
  nrm <- file.path(root, "02_Infrastructure/memory/memory_metadata_normalize.R")
  if (file.exists(nrm)) { source(nrm, local = TRUE)
    if (exists("normalize_axiom_metadata", mode = "function"))
      axiom <- normalize_axiom_metadata(axiom = axiom, axiom_class = candidate$type %||% "methodological",
        memory_kind = "axiom_active", authority = "high", review_policy = "quarterly",
        enforcement_mode = "documented", write = FALSE) }
  out_path <- file.path(out_dir, paste0(ax_id, ".json"))
  write_json(axiom, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  .st <- as.character(axiom$status %||% "proposed")[1]
  cat(sprintf("[promote] mode-local %s → %s [status=%s · refine=%s%s · %s]\n",
              ax_id, out_path, .st, as.character(axiom$refine_verdict %||% "?")[1],
              if (length(axiom$refine_failing)) paste0("(", paste(unlist(axiom$refine_failing), collapse = ","), ")") else "",
              axiom$metric_type))
  if (identical(.st, "active")) {
    cat(sprintf("[promote] 무인 활성화(R0~R6 통과) — 정지 스위치 QVEST_AXIOM_UNATTENDED=0 · 되돌리기 deactivate_axiom(c(\"%s\"), reason=)\n", ax_id))
    # ★전체 경로를 넘긴다 — 헬퍼가 역링크 기록 후 이 파일에 backlinks_written 플래그를 되쓴다
    #   (basename 만 넘기면 file.exists 가 FALSE 라 플래그가 안 서고, 매주 역링크가 다시 돈다).
    .maybe_write_back_links(axiom, out_path, root = root)
  } else {
    cat(sprintf("[promote] 보류(주입 안 됨) — 수동 해제: Rscript -e 'source(\"02_Infrastructure/axiom/promote.R\"); approve_axiom(c(\"%s\"))'\n", ax_id))
  }
  # sot_map 은 status 를 그대로 싣는다 — 활성화 의미(주입·enforcement)는 status 로 갈린다.
  .update_sot_map(ax_id, mode, axiom, root = root)
  list(path = out_path, action = "created", status = .st, refine = refine, cap_ok = isTRUE(cap))
}

# 역링크는 공리당 **평생 1회**. backlinks_written 이 서 있으면 다시 쓰지 않는다.
#   근거: supporting 743 고유 L-code 중 175건이 2개 이상 공리에 속하는데 promoted_to_axiom 은
#   스칼라다 — 주간 무조건 재기록이면 두 공리가 매주 서로를 덮어쓴다(원장이 진동한다).
#   근본 수리(promoted_to_axiom 스칼라 → 배열)는 별건 태스크(도훈 확인 F-c).
.maybe_write_back_links <- function(axiom, ax_path, root = .px_root()) {
  if (isTRUE(axiom$backlinks_written)) return(invisible(0L))
  res <- .update_lcode_back_links(list(supporting_l_codes = axiom$supporting_l_codes),
                                  basename(ax_path), root = root)
  if (!is.na(ax_path) && file.exists(ax_path)) {
    a <- tryCatch(fromJSON(ax_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(a)) {
      a$backlinks_written <- TRUE
      a$backlink_mode <- attr(res, "backlink_mode") %||% "per_file"
      a$backlinks_n <- as.integer(res)
      write_json(a, ax_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
    }
  }
  invisible(res)
}

# ── v9.1 커밋16: 비활성화(active → proposed, 파일 유지) ──────────────────────
# 되돌리기의 '분 단위' 경로. rollback_axiom() 과 달리 **파일도 sot_map 도 지우지 않는다** —
#   주입면에서만 즉시 내린다(주입 훅이 modes/** 를 status=="active" 로 거르므로).
deactivate_axiom <- function(ids, reason, root = .px_root()) {
  if (missing(reason) || !nzchar(as.character(reason)[1]))
    stop("deactivate_axiom: reason 필수 (사유 없는 비활성화는 다음 주에 왜 내렸는지 알 수 없다)")
  if (is.list(ids)) ids <- vapply(ids, function(z) as.character(z$axiom_id %||% z)[1], character(1))
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  out <- list()
  for (id in as.character(ids)) {
    fs <- list.files(file.path(active_dir, "modes"),
                     pattern = sprintf("^%s\\.json$", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", id)),
                     full.names = TRUE, recursive = TRUE)
    if (!length(fs)) { cat(sprintf("[deactivate][WARN] %s 미발견 — 건너뜀\n", id)); out[[id]] <- list(status = "not_found"); next }
    f <- fs[1]
    ax <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ax)) { out[[id]] <- list(status = "unreadable"); next }
    if (!identical(as.character(ax$status %||% "")[1], "active")) {
      cat(sprintf("[deactivate] %s 이미 비활성(status=%s) — 무변경\n", id, as.character(ax$status %||% "?")[1]))
      out[[id]] <- list(status = "already_inactive", path = f); next
    }
    ax$status <- "proposed"
    ax$deactivated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    ax$deactivated_reason <- as.character(reason)[1]
    write_json(ax, f, pretty = TRUE, auto_unbox = TRUE, null = "null")
    .update_sot_map(id, as.character(ax$research_mode %||% "qepm_legacy")[1], ax, root = root)
    cat(sprintf("[deactivate] %s → status=proposed (주입면에서 제외) | 사유: %s\n", id, as.character(reason)[1]))
    out[[id]] <- list(status = "deactivated", path = f)
  }
  invisible(out)
}

# ── 수동 승인 (v9.1: 상시 관문이 아니라 **예외 경로**) ───────────────────────
# v9.1 커밋16 이후 활성화 정본은 refine_statement.R 의 R0~R6 다(무인). approve_axiom() 은
#   ①롤백 후 재승인 ②HELD 를 사람이 판단해 수동 해제 ③QVEST_AXIOM_UNATTENDED=0 운용 중
#   선별 활성화 — 이 세 경로로 **존치**한다. 삭제하면 되돌린 뒤 되돌아올 길이 없다.
# proposed → active 전환 + sot_map 등재 + L-code 역링크(평생 1회 가드) 기록.
# Usage: Rscript -e 'source("02_Infrastructure/axiom/promote.R"); approve_axiom(c("AX-AS-001"))'
approve_axiom <- function(ids, approved_by = "dohoon", root = .px_root()) {
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  out <- list()
  for (id in as.character(ids)) {
    fs <- list.files(file.path(active_dir, "modes"),
                     pattern = sprintf("^%s\\.json$", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", id)),
                     full.names = TRUE, recursive = TRUE)
    if (!length(fs)) {
      cat(sprintf("[approve][WARN] %s 미발견 (active/modes/**) — 건너뜀\n", id))
      out[[id]] <- list(status = "not_found"); next
    }
    f <- fs[1]
    ax <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ax)) { cat(sprintf("[approve][WARN] %s 파싱 실패 — 건너뜀\n", id)); out[[id]] <- list(status = "unreadable"); next }
    if (identical(as.character(ax$status %||% ""), "active")) {
      cat(sprintf("[approve] %s 이미 active — 무변경\n", id)); out[[id]] <- list(status = "already_active", path = f); next
    }
    ax$status <- "active"
    ax$approved_by <- approved_by
    ax$approved_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    ax$confirm_required <- NULL
    write_json(ax, f, pretty = TRUE, auto_unbox = TRUE, null = "null")
    mode <- as.character(ax$research_mode %||% "qepm_legacy")[1]
    .update_sot_map(id, mode, ax, root = root)
    .maybe_write_back_links(ax, f, root = root)   # 평생 1회 가드 경유 (스칼라 상호 덮어쓰기 차단)
    cat(sprintf("[approve] %s → status=active (%s) | sot_map 등재 + L-code 역링크 기록\n", id, f))
    if (!identical(as.character(ax$refine_verdict %||% "")[1], "REFINED"))
      cat(sprintf("[approve][WARN] %s 는 refine_verdict=%s — 수동 활성화이므로 memory_knowledge_health HARD_8 이 발화한다(의도라면 refine 입력을 고치거나 다시 비활성화할 것)\n",
                  id, as.character(ax$refine_verdict %||% "미기록")[1]))
    out[[id]] <- list(status = "approved", path = f)
  }
  invisible(out)
}

# proposed 목록 (다이제스트·모닝 승인큐 소비 — 읽기 전용)
list_proposed_axioms <- function(root = .px_root()) {
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active", "modes")
  res <- list()
  for (f in list.files(active_dir, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)) {
    a <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(a) || !identical(as.character(a$status %||% ""), "proposed")) next
    stmt <- as.character(a$statement %||% "")[1]
    res[[length(res) + 1L]] <- list(
      axiom_id = as.character(a$axiom_id %||% sub("\\.json$", "", basename(f)))[1],
      mode = as.character(a$research_mode %||% "unknown")[1],
      polarity = as.character(a$polarity %||% "unknown")[1],
      statement = substr(gsub("[\r\n]+", " ", stmt), 1, 120),
      n_support = length(a$supporting_l_codes %||% list()),
      path = f,
      approve_cmd = sprintf("Rscript -e 'source(\"02_Infrastructure/axiom/promote.R\"); approve_axiom(c(\"%s\"))'",
                            as.character(a$axiom_id %||% "")[1]))
  }
  res
}

# v9 (2026-08-23): `status` 를 함께 싣고, 이미 있는 항목은 **skip 이 아니라 갱신**한다.
#   ★왜 proposed 도 등재하는가 — `memory_knowledge_health.R` HARD_3 이
#     "active/** 아래 JSON 은 전부 sot_map 에 있어야 한다"를 강제한다(그 파일은 수정 대상 아님).
#     그래서 등재 자체는 proposal 시점에 하되 `documented_active = FALSE` +
#     `status = "proposed"` 로 **정본이 아님을 명시**한다. 활성화 의미(주입·enforcement)는
#     status 로 갈리고, 주입 훅(axiom_context_inject.sh)이 modes/** 를 status=="active" 로
#     필터하므로 INV-6 안전속성(무인 텍스트의 주입 도달 금지)은 그대로 보존된다.
#     approve_axiom() 이 같은 함수를 다시 불러 status 를 active 로 올린다.
# ★root 는 **인자**로 받는다 (2026-08-23). 내부에서 .px_root() 를 다시 부르면 호출자가
#   다른 루트(샌드박스·워크트리)를 지정해도 무시하고 정본 저장소를 건드린다 — 실측 사고:
#   샌드박스로 approve_axiom(root=임시) 를 돌렸는데 **정본 axiom_sot_map.json 에**
#   시험용 AX 항목이 등재됐다. 격리의 이음매는 환경변수가 아니라 함수 인자다.
.update_sot_map <- function(ax_id, mode, axiom, root = .px_root()) {
  sp <- file.path(root, "qepm", "memory", "axioms", "axiom_sot_map.json")
  if (!file.exists(sp)) return(invisible())
  sot <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(sot) || is.null(sot$axioms)) return(invisible())
  # global tier(promote_global.R 경유)는 modes/ 하위가 아닌 active/ 직속 — 경로/namespace 분기
  is_global <- identical(mode, "global")
  ns <- if (is_global) "GLOBAL" else .mode_prefix(mode)
  st <- as.character(axiom$status %||% "proposed")[1]
  sync <- if (is_global) "GLOBAL" else if (identical(st, "active")) "MODE_LOCAL" else "MODE_LOCAL_PROPOSED"
  ids <- vapply(sot$axioms, function(a) a$axiom_id %||% "", character(1))
  if (ax_id %in% ids) {
    i <- which(ids == ax_id)[1]
    if (identical(as.character(sot$axioms[[i]]$status %||% ""), st)) return(invisible())
    sot$axioms[[i]]$status <- st
    sot$axioms[[i]]$sync_status <- sync
    write_json(sot, sp, pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat(sprintf("[promote] sot_map 갱신 %s → status=%s\n", ax_id, st))
    return(invisible())
  }
  sot$axioms[[length(sot$axioms) + 1]] <- list(axiom_id = ax_id, name = ax_id,
    documented_active = FALSE,
    status = st,
    active_json_path = if (is_global) sprintf("qepm/memory/axioms/active/%s.json", ax_id)
                       else sprintf("qepm/memory/axioms/active/modes/%s/%s.json", mode, ax_id),
    namespace = ns, axiom_class = axiom$axiom_class %||% "methodological",
    authority = "high", review_policy = "quarterly", enforcement_mode = "documented",
    sync_status = sync, cache_core_present = FALSE)
  write_json(sot, sp, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] sot_map += %s (namespace=%s, status=%s)\n", ax_id, ns, st))
}

# 2026-08-23 v9: L-code 1건당 stage_artifacts 전수(33k 엔트리) 재스캔 + 전 파일 재파싱이던
#   구조를 **1회 색인**으로 바꿨다. 판정 의미는 불변(같은 list.files 순서에서 첫 일치 파일).
#   근거: supporting 507건 클러스터가 승인되면 구 구조는 507 × 전수스캔 = 실행 불가.
#   ★멱등: 이미 같은 axiom_id 가 새겨져 있으면 쓰지 않는다(주간 재실행 diff 방지).
.update_lcode_back_links <- function(candidate, ax_filename, root = .px_root()) {
  ax_id <- sub("\\.json$", "", ax_filename)
  want <- unique(as.character(candidate$supporting_l_codes %||% character(0)))
  if (!length(want)) return(invisible(0L))
  files <- list.files(file.path(root, "stage_artifacts"), pattern = "^l_code_.*\\.json$",
                      full.names = TRUE, recursive = TRUE)
  idx <- list(); n <- 0L
  for (f in files) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    k <- as.character(d$l_code %||% "")[1]
    if (!nzchar(k) || !is.null(idx[[k]])) next      # 첫 일치만 (구 동작의 break 와 동일)
    idx[[k]] <- list(path = f, doc = d)
  }
  # v9.1 커밋16 — 역링크 폭증 대책. 18건 전부 활성화 시 stage_artifacts 515 파일 재작성이고
  #   AX-AS-001 단독으로 184건이다. 상한 초과분은 개별 파일 대신 **역인덱스 1파일**에 적는다
  #   (원장 진동·diff 폭증 억제. promoted_to_axiom 스칼라 충돌 175건도 같이 피한다).
  hits <- Filter(function(lc) !is.null(idx[[lc]]), want)
  if (length(hits) > (.TIER$mode_local$backlink_max_files %||% 60L)) {
    bd <- file.path(root, "qepm", "memory", "axioms", "backlinks")
    dir.create(bd, recursive = TRUE, showWarnings = FALSE)
    bp <- file.path(bd, paste0(ax_id, ".json"))
    write_json(list(axiom_id = ax_id, mode = "index",
                    reason = sprintf("supporting %d건 > BACKLINK_MAX_FILES %d — 개별 L-code 파일 미수정",
                                     length(hits), .TIER$mode_local$backlink_max_files %||% 60L),
                    written_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                    l_codes = as.list(hits)),
               bp, pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat(sprintf("[promote] L-code 역링크 = 역인덱스 1파일 (%d건 > 상한 %d) → %s\n",
                length(hits), .TIER$mode_local$backlink_max_files %||% 60L, bp))
    return(invisible(structure(length(hits), backlink_mode = "index")))
  }
  for (lc in want) {
    e <- idx[[lc]]
    if (is.null(e)) next
    if (identical(as.character(e$doc$promoted_to_axiom %||% ""), ax_id)) next   # 무쓰기
    d <- e$doc
    d$promoted_to_axiom <- ax_id
    d$promoted_at <- format(Sys.Date())
    write_json(d, e$path, pretty = TRUE, auto_unbox = TRUE, null = "null")
    n <- n + 1L
  }
  cat(sprintf("[promote] L-code 역링크 기록: %d건 (대상 %d / 색인 %d)\n", n, length(want), length(idx)))
  invisible(structure(n, backlink_mode = "per_file"))
}

# v9 (2026-08-23): review_log = **클러스터당 1파일** + history[].
#   구 규약은 파일명이 `AX-PENDING_<candidate_id>_<날짜>.json` 이라 ① 매주 날짜만 바뀐
#   같은 채점이 새 파일로 쌓였고(728건 적체) ② candidate_id 가 길어 MAX_PATH 초과로
#   쓰기가 무음 crash 했다. 파일명을 12-hex cluster_key 로 고정하면 둘 다 사라진다.
# ★무쓰기 규약: candidate_sha 와 최근 채점(weighted_score·failing_hurdles)이 모두 같으면
#   **파일을 건드리지 않는다**. 같은 입력에 대한 재채점은 새 정보가 아니므로 기록도 아니다
#   (이 조항이 없으면 매주 logged_at 만 바뀐 diff 가 무한히 생긴다).
.log_partial <- function(candidate, report, root = .px_root()) {
  ld <- file.path(root, "qepm", "memory", "axioms", "review_log")
  dir.create(ld, recursive = TRUE, showWarnings = FALSE)
  ckey <- report$cluster_key %||% .cluster_key_of(candidate)
  op <- file.path(ld, sprintf("AX-PENDING_%s.json", ckey))
  failing <- names(report$hurdle_pass)[!unlist(report$hurdle_pass)]
  csha <- as.character(report$candidate_sha %||% NA)

  prev <- if (file.exists(op)) tryCatch(fromJSON(op, simplifyVector = FALSE), error = function(e) NULL) else NULL
  hist <- prev$history %||% list()
  last <- if (length(hist)) hist[[length(hist)]] else NULL
  same_sha   <- !is.null(prev) && identical(as.character(prev$candidate_sha %||% ""), csha)
  same_score <- !is.null(last) && isTRUE(suppressWarnings(
                  as.numeric(last$weighted_score %||% NA)) == as.numeric(report$weighted_score))
  same_fail  <- !is.null(last) && identical(
                  sort(as.character(unlist(last$failing_hurdles %||% character(0)))),
                  sort(as.character(failing)))
  if (same_sha && same_score && same_fail) {
    cat(sprintf("[promote] 부분통과 — 입력·채점 불변, review_log 무쓰기 (%s)\n", basename(op)))
    return(op)
  }

  hist[[length(hist) + 1L]] <- list(
    logged_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    weighted_score = report$weighted_score,
    failing_hurdles = as.list(failing))
  if (length(hist) > 10L) hist <- hist[(length(hist) - 9L):length(hist)]   # cap 10

  write_json(list(
    candidate_id = report$candidate_id %||% candidate$candidate_id,
    cluster_key = ckey, mode = report$mode, tier = report$tier %||% "mode_local",
    candidate_sha = csha,
    hurdle_axes = report$hurdle_axes %||% list(),
    weighted_score = report$weighted_score, threshold = report$threshold,
    passed_rule = report$passed_rule %||% "all_hurdles",
    all_hurdles_pass = report$all_hurdles_pass, failing_hurdles = as.list(failing),
    axes = report$axes,
    logged_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    history = hist,
    note = "v9 mode-local: hurdle_axes 동시 충족이 통과(weighted 는 랭킹용). 파일 = 클러스터당 1건, history 최대 10회."),
    op, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] 부분통과(hurdle 미달: %s) → %s\n", paste(failing, collapse = ","), op)); op
}

if (!interactive() && Sys.getenv("PROMOTE_SOURCED") != "1" && length(commandArgs(trailingOnly = TRUE)) > 0) {
  .cli <- commandArgs(trailingOnly = TRUE)
  .dry <- any(.cli %in% c("--dry-run", "--dryrun"))
  .paths <- .cli[!startsWith(.cli, "--")]
  if (length(.paths)) invisible(promote_to_axiom(.paths[1], dry_run = .dry))
  else cat("[promote] 후보 경로 인자 없음 — usage: Rscript promote.R [--dry-run] <candidate.json>\n")
}
cat(sprintf("[promote] Loaded (v9.1 사다리 + 정제기 R0~R6 + 무인 활성화). unattended=%s | promote_to_axiom(path, dry_run=) / list_active_axioms(mode=) / deactivate_axiom(ids, reason=) / approve_axiom(ids) / clear_tombstone(key, reason=)\n",
            if (.unattended_enabled()) "ON" else "OFF (QVEST_AXIOM_UNATTENDED=0)"))
