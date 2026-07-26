#==============================================================================
# Measurement Basis Audit — v1.2 Charter §10 Health Score Module
# 02_Infrastructure/portfolio/measurement_basis_audit.R
#
# Purpose: active book의 measurement_basis 일관성을 0-100 점수로 산출.
#   bootstrap.sh + monitoring agent 양쪽에서 호출 가능.
#
# Health Score 계산식 (per STR_id, max 100):
#   sr_provenance_certificate 보유:                 +30
#   measurement_basis_primary == 'forge_realized':  +20
#   schedule_density_ratio >= 0.95:                 +20
#   factor_engine vs realized divergence < 0.3pp:   +20
#   governor_concord_certificate 보유:              +10
#
# Tier:
#   Healthy >= 90 / Warning 70-89 / Drifted < 70
#
# v1.8 (2026-05-11): sleeve_aliases + cash_role_exempt
#   - 5/9 S4 v2 admit (TSMOM_8_ETF + CASH_KRW_PG2_S4) NO_WT 해소
#   - sleeve naming evolution (e.g., PG2 → PG2_v2_alpha_2026_04 / _8_ETF / _no_KR_bond_overlap) lineage inherit
#   - cash_allocation role (CASH_ prefix) audit 면제 (v55 정책)
#
# v1.9 (2026-05-12): inherit_pointer.json recognition + per-field forge_package inherit
#   - re-certification WT (deployment_promotion_re_certification class) inherit_pointer.json
#     의 inherit_certs + inherit_forge_package_fields를 정식 audit 입력으로 인식
#   - sr_provenance / measurement_basis_primary / schedule_density / divergence 각각
#     primary WT forge_pkg에 없을 시 inherit_pointer 명시 source → lineage_wts 순서로 채움
#   - STR_1715_AR_on_M4_PG2 (Session 79 re-certify single sleeve) HEALTHY 회복
#
# v1.10/v1.11 (2026-07-18/24): STR_1715 오버레이 부품 교체(Layer4 제거 / m4→M4∩AE D3 swap)로
#   book_state 수동 mutate 시마다 별칭 손수 추가 (.SLEEVE_ALIASES). → v1.12에서 근절.
#
# v1.12 (2026-07-24): pattern-based lineage resolver (별칭 자동화 대체). find_latest_wt/
#   find_lineage_wts의 str_id_root 절단 substring(첫 "_M"에서 잘려 오버레이 스왑마다 오매칭)을
#   .lineage_anchor(선두 STR_<digits>) + .lineage_related(토큰 경계 계보 매칭)으로 교체.
#   STR_1715 계열 하드코딩 별칭 4종 제거(정규화 대체 — 아래 .SLEEVE_ALIASES 근거 주석).
#   비-STR/CASH/COMPOSITE 회귀 0 실측(test_resolver.R 16-id). 오버레이 부품 교체마다 별칭
#   손수 추가할 필요 없음. STR_1715 != STR_17150 / "EQUITY_1715" 오매칭 없음(경계 규정).
#
# Reference: STR_1715 OVERRIDE_006 사후 — measurement_basis 미명시 산출물이 PG2 통과한 사고.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

# v1.8: sleeve naming evolution alias map — admit 시 governor_admission.json
# 신규 발급 없이 book_state.json만 mutate되는 case 대응. ga_str_id ↔ str_id 매칭용.
# 신규 alias 추가 시 lineage source WT의 governor_admission.json str_id 명시.
.SLEEVE_ALIASES <- list(
  # 비-STR cross-family rename — lineage anchor(STR_<digits>)로 표현 불가하므로 명시 별칭 유지.
  # TSMOM_8_ETF_rotation_PG2_no_KR_bond_overlap 는 base id(TSMOM_ETF_rotation_PG2)와 stem 자체가
  # 다르므로(8_/_no_KR_bond_overlap) anchor 정규화 대상 아님 → 하드코딩 별칭으로 남긴다.
  "TSMOM_8_ETF_rotation_PG2_no_KR_bond_overlap"        = "TSMOM_ETF_rotation_PG2"
)
# v1.12 (2026-07-24) — STR_1715 계열 하드코딩 별칭 4종 제거 근거 (pattern-based resolver 대체):
#   제거된 entries (모두 STR_1715 anchor 공유 · 오버레이 접미 변주만 다름):
#     STR_1715_AR_threshold_overlay_PG2_v2_alpha_2026_04 -> STR_1715_AR_threshold_overlay_PG2  (v1.8)
#     STR_1715_AR_on_M4_PG2                              -> STR_1715_AR_threshold_overlay_PG2  (v1.9)
#     STR_1715_on_M4_R05_noLayer4_PG2                    -> STR_1715_AR_on_M4_R05_overlay_PG2  (v1.10)
#     STR_1715_on_M4gAE_R05_noLayer4_PG2                 -> STR_1715_AR_on_M4_R05_overlay_PG2  (v1.11)
#   → .lineage_anchor/.lineage_related 가 접미 변주를 STR_1715 계보로 정규화하므로, 별칭 없이도
#     동일 WT(또는 cert 보유 lineage WT)로 resolve 된다. test_resolver.R 실측: 4 id 전부
#     100/HEALTHY 유지, 비-STR/CASH/COMPOSITE 회귀 0. 앞으로 오버레이 부품 교체(m4→M4gAE·R05·
#     noLayer4·FaithTrend 등)마다 손으로 별칭 추가할 필요 없음(v1.10/v1.11 재발 원천 차단).
#   ※ 신규 별칭은 '비-STR cross-family rename' 인 경우에만 위 list에 추가.

# v1.8: cash_allocation role audit 면제 prefix (v55 lawbook + Charter §10 Role Card)
.CASH_ROLE_PREFIXES <- c("CASH_")

#------------------------------------------------------------------------------
# v1.12 (2026-07-24): pattern-based lineage resolver — 하드코딩 별칭 자동화 대체.
#
# 문제: STR_1715 오버레이 부품 교체(m4→M4gAE·R05·noLayer4·threshold·FaithTrend 등 접미
#   변주)로 book_state.admitted_id가 바뀔 때마다, 아래 find_latest_wt/find_lineage_wts 의
#   str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$","",str_id) 가 첫 "_M"에서 절단돼
#   "STR_1715_on" / "STR_1715_AR_on" 이 되고, terminal ga str_id
#   "STR_1715_AR_on_M4_R05_overlay_PG2" 와 substring 불일치 → NO_WT(0/100 DRIFTED).
#   그래서 매 오버레이 스왑마다 .SLEEVE_ALIASES 에 손으로 신 id를 추가해야 했다(v1.10/v1.11).
#
# 해법: STR-family는 lineage anchor(선두 STR_<digits>)를 계보 키로 정규화 매칭.
#   비-STR sleeve(TSMOM/KR_10y/COMPOSITE/S4/CASH 등)는 anchor=NA → 기존 substring 동작
#   그대로 보존(오매칭 방지). anchor는 '토큰 경계' 매칭이라 STR_1715 가 STR_17150 이나
#   "EQUITY_1715"(COMPOSITE_KR_EQUITY_1715_NEW_...)에 오매칭되지 않는다.
#------------------------------------------------------------------------------

# STR-family lineage anchor: 선두 STR_<digits> (예: STR_1715_on_M4gAE_R05... → "STR_1715").
# 비-STR id는 NA 반환 → anchor 정규화 미적용, legacy substring fallback.
.lineage_anchor <- function(id) {
  id <- as.character(id)
  if (length(id) == 0L || is.na(id)) return(NA_character_)
  m <- regmatches(id, regexpr("^STR_[0-9]+", id))
  if (length(m) == 1L && nzchar(m)) m else NA_character_
}

# str_id(book)와 후보 문자열(단일 ga_str_id 또는 discovery_of/lineage blob)의 계보 일치.
#   - STR-family(anchor 존재): anchor가 후보에 '토큰 경계'로 등장하면 동일 계보.
#       경계 = (시작|비영숫자) anchor (비숫자|끝) → STR_1715 != STR_17150, != EQUITY_1715.
#       이로써 오버레이 접미 변주(_on_M4gAE_R05_noLayer4_PG2 등)를 무시하고 계보로만 매칭.
#   - 비-STR: 기존 full-id / legacy_root substring 동작 보존(회귀 방지).
# legacy_root = 기존 sub("(_WT|_Iter|_M|_S|_v).*$","") 절단 root — 비-STR fallback 전용.
.lineage_related <- function(str_id, candidate, legacy_root) {
  candidate <- as.character(candidate)
  if (length(candidate) == 0L || !nzchar(candidate)) return(FALSE)
  anchor <- .lineage_anchor(str_id)
  if (!is.na(anchor)) {
    return(grepl(paste0("(^|[^A-Za-z0-9])", anchor, "([^0-9]|$)"), candidate))
  }
  grepl(str_id, candidate, fixed = TRUE) ||
    (nzchar(legacy_root) && grepl(legacy_root, candidate, fixed = TRUE))
}

audit_book_measurement_coherence <- function(book_state_path,
                                             wt_root = "qepm/mailbox/worktask",
                                             governor_dir = NULL) {
  if (!file.exists(book_state_path)) {
    return(list(
      score = NA, tier = "BOOK_STATE_MISSING",
      details = list(), error = "book_state.json not found"
    ))
  }

  bs <- tryCatch(fromJSON(book_state_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs)) {
    return(list(
      score = NA, tier = "BOOK_STATE_PARSE_FAIL",
      details = list(), error = "JSON parse fail"
    ))
  }

  admitted_ids <- bs$admitted_ids
  if (is.null(admitted_ids) || length(admitted_ids) == 0) {
    return(list(score = NA, tier = "NO_ADMITTED_IDS", details = list()))
  }

  # governor mailbox dir 추론
  if (is.null(governor_dir)) {
    governor_dir <- dirname(book_state_path)
  }

  # v1.7 lineage-aware: generated_at timestamp 정렬 + lineage chain 추적
  find_latest_wt <- function(str_id, wt_root) {
    if (!dir.exists(wt_root)) return(NULL)
    str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id)

    primary <- list()
    lineage <- list()
    for (wd in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
      ga_path <- file.path(wd, "governor_admission.json")
      if (!file.exists(ga_path)) next
      ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE),
                     error = function(e) NULL)
      if (is.null(ga)) next

      ga_str_id <- as.character(ga$str_id %||% "")
      gen_at <- as.character(ga$generated_at %||% "")
      discovery_of <- paste(as.character(ga$discovery_of %||% ""),
                            as.character(ga$wt_lifecycle$discovery_of %||% ""))

      if (identical(ga_str_id, str_id)) {
        primary[[length(primary) + 1]] <- list(wt_dir = wd, generated_at = gen_at)
      } else if (.lineage_related(str_id, ga_str_id, str_id_root) ||
                 .lineage_related(str_id, discovery_of, str_id_root)) {
        # v1.12: str_id_root substring(절단 버그) → .lineage_related 로 교체.
        # STR-family는 anchor 계보 매칭, 비-STR은 legacy substring 보존.
        lineage[[length(lineage) + 1]] <- list(wt_dir = wd, generated_at = gen_at)
      }
    }
    # primary 우선, 없으면 lineage. 동일 카테고리 내 generated_at 정렬 (latest 우선)
    sort_by_gen_at <- function(lst) {
      if (length(lst) <= 1) return(lst)
      gens <- sapply(lst, function(x) x$generated_at)
      lst[order(gens, decreasing = TRUE)]
    }
    primary <- sort_by_gen_at(primary)
    lineage <- sort_by_gen_at(lineage)

    if (length(primary) > 0) return(primary[[1]]$wt_dir)
    if (length(lineage) > 0) return(lineage[[1]]$wt_dir)
    NULL
  }

  # v1.7: lineage WT의 cert도 점수에 inherit (deployment alpha_discovery / sizing_only sr_provenance 등)
  find_lineage_wts <- function(str_id, wt_root) {
    if (!dir.exists(wt_root)) return(character(0))
    str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id)
    out <- character(0)
    for (wd in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
      ga_path <- file.path(wd, "governor_admission.json")
      fp_path <- file.path(wd, "forge_package.json")
      if (!file.exists(ga_path) && !file.exists(fp_path)) next
      hit <- FALSE
      if (file.exists(ga_path)) {
        ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE),
                       error = function(e) NULL)
        if (!is.null(ga)) {
          ga_str <- as.character(ga$str_id %||% "")
          dof <- paste(as.character(ga$discovery_of %||% ""),
                       as.character(ga$wt_lifecycle$discovery_of %||% ""))
          # v7.2.2 — promotion_wt cross-strategy lineage (L-283)
          allocation <- ga$allocation_decided %||% list()
          alloc_names <- names(allocation)
          if (is.null(alloc_names)) alloc_names <- character(0)
          # v1.12: allocation key도 STR-family는 anchor 계보로 매칭(exact %in% 유지 + anchor OR).
          #   비-STR은 exact %in% 만(legacy 동작 보존 — allocation 오매칭 방지).
          anchor <- .lineage_anchor(str_id)
          alloc_match <- (str_id %in% alloc_names) ||
            (!is.na(anchor) && any(vapply(alloc_names,
                function(k) .lineage_related(str_id, k, ""), logical(1))))
          if (.lineage_related(str_id, ga_str, str_id_root) ||
              .lineage_related(str_id, dof, str_id_root) ||
              alloc_match) {
            hit <- TRUE
          }
        }
      }
      if (!hit && file.exists(fp_path)) {
        fp <- tryCatch(fromJSON(fp_path, simplifyVector = FALSE),
                        error = function(e) NULL)
        if (!is.null(fp)) {
          dl <- paste(unlist(fp$deployment_lineage %||% list()),
                      unlist(fp$alpha_lineage_chain %||% list()), collapse = " ")
          if (.lineage_related(str_id, dl, str_id_root)) {  # v1.12
            hit <- TRUE
          }
        }
      }
      if (hit) out <- c(out, wd)
    }
    unique(out)
  }

  per_str <- list()
  total_score <- 0
  for (str_id in admitted_ids) {
    # v1.8: cash_allocation role 사전 exempt (v55 lawbook 정책 — forge_realized_share_based 면제)
    is_cash <- any(vapply(.CASH_ROLE_PREFIXES,
                          function(p) startsWith(str_id, p), logical(1)))
    if (is_cash) {
      per_str[[str_id]] <- list(
        score = 100, tier = "EXEMPT_CASH_ROLE",
        components = list(cash_allocation_role_exempt = 100),
        wt_dir = NULL,
        audit_metadata = list(
          role = "cash_allocation",
          exempt_reason = "v55 cash_allocation role — forge_realized_share_based 면제 (lawbook v55_consensus_addendum)",
          exempt_basis = "v1.8 cash_role_prefixes match",
          original_str_id = str_id
        ),
        note = "EXEMPT — cash sleeve audit 면제 (점수 100 EXEMPT_CASH_ROLE)"
      )
      total_score <- total_score + 100
      next
    }

    # v1.8: sleeve naming evolution alias resolve (admit 시 신규 ga 미발급 case 대응)
    resolved_id <- if (str_id %in% names(.SLEEVE_ALIASES)) {
      .SLEEVE_ALIASES[[str_id]]
    } else {
      str_id
    }

    wt_dir <- find_latest_wt(resolved_id, wt_root)
    score <- 0
    components <- list()
    inherited_from <- list()
    alias_applied <- if (str_id != resolved_id) {
      list(book_str_id = str_id, resolved_to = resolved_id,
           reason = "v1.8 sleeve_aliases map")
    } else NULL

    if (is.null(wt_dir)) {
      per_str[[str_id]] <- list(
        score = 0, tier = "NO_WT", components = list(),
        alias_applied = alias_applied,
        note = "governor_admission.json with this str_id not found"
      )
      next
    }

    # v1.7 lineage WT 후보 (본 WT 외) — 누락 cert/field inherit fallback
    lineage_wts <- setdiff(find_lineage_wts(resolved_id, wt_root), wt_dir)

    # v1.9: inherit_pointer.json 인식 — re-cert WT가 lineage_origin_wt 명시 시 즉시
    # lineage_wts에 prepend (str_id 매칭 우회). inherit_certs / inherit_forge_package_fields도 파싱.
    inherit_pointer <- NULL
    inherit_pointer_path <- file.path(wt_dir, "inherit_pointer.json")
    if (file.exists(inherit_pointer_path)) {
      inherit_pointer <- tryCatch(fromJSON(inherit_pointer_path, simplifyVector = FALSE),
                                   error = function(e) NULL)
      if (!is.null(inherit_pointer)) {
        # lineage_origin_wt 직접 추가 (str_id 매칭 우회)
        if (!is.null(inherit_pointer$lineage_origin_wt)) {
          origin_dir <- file.path(wt_root, inherit_pointer$lineage_origin_wt)
          if (dir.exists(origin_dir) && origin_dir != wt_dir) {
            lineage_wts <- unique(c(origin_dir, lineage_wts))
          }
        }
        # inherit_certs declared paths — directory 추출해서 lineage_wts에 추가
        ic <- inherit_pointer$inherit_certs %||% list()
        for (cert_name in names(ic)) {
          ic_val <- as.character(ic[[cert_name]])
          # path 추출: "qepm/mailbox/worktask/WT-XXX/..." 패턴
          m <- regmatches(ic_val, regexpr("qepm/mailbox/worktask/[^/[:space:]]+", ic_val))
          if (length(m) > 0 && nchar(m) > 0) {
            cand <- file.path(getwd(), m)
            if (!dir.exists(cand)) cand <- m  # relative
            if (dir.exists(cand) && cand != wt_dir) {
              lineage_wts <- unique(c(cand, lineage_wts))
            }
          }
        }
        # inherit_forge_package_fields source_wt — forge_package source 우선 추가
        fp_inherit <- inherit_pointer$inherit_forge_package_fields %||% list()
        if (!is.null(fp_inherit$source_wt)) {
          src_dir <- file.path(wt_root, fp_inherit$source_wt)
          if (dir.exists(src_dir) && src_dir != wt_dir) {
            lineage_wts <- unique(c(src_dir, lineage_wts))
          }
        }
      }
    }

    # 1. sr_provenance_certificate (+30) — 본 WT 우선, 없으면 lineage WT inherit
    sr_cert_path <- file.path(wt_dir, "sr_provenance_certificate.json")
    if (file.exists(sr_cert_path)) {
      score <- score + 30
      components$sr_provenance_certificate <- 30
    } else {
      sr_inherit_wt <- NULL
      for (lw in lineage_wts) {
        if (file.exists(file.path(lw, "sr_provenance_certificate.json"))) {
          sr_inherit_wt <- basename(lw); break
        }
      }
      if (!is.null(sr_inherit_wt)) {
        score <- score + 30
        components$sr_provenance_certificate <- 30
        inherited_from$sr_provenance_certificate <- sr_inherit_wt
      } else {
        components$sr_provenance_certificate <- 0
      }
    }

    # 2~4: forge_package fields — 본 WT 우선, 없으면 lineage WT 내 forge_package에서 inherit
    forge_path <- file.path(wt_dir, "forge_package.json")
    forge_pkg <- if (file.exists(forge_path)) {
      tryCatch(fromJSON(forge_path, simplifyVector = FALSE),
               error = function(e) NULL)
    } else NULL
    forge_inherit_wt <- NULL
    if (is.null(forge_pkg)) {
      for (lw in lineage_wts) {
        lp <- file.path(lw, "forge_package.json")
        if (file.exists(lp)) {
          forge_pkg <- tryCatch(fromJSON(lp, simplifyVector = FALSE),
                                error = function(e) NULL)
          if (!is.null(forge_pkg)) { forge_inherit_wt <- basename(lw); break }
        }
      }
    }

    # v1.9: per-field inherit helper — primary 부재 시 lineage_wts forge_package +
    # inherit_pointer.inherit_forge_package_fields.values_inherited 순서로 탐색
    inherit_field <- function(field_name, predicate) {
      # 1. inherit_pointer values_inherited 우선 (재현 가능한 explicit declaration)
      if (!is.null(inherit_pointer)) {
        vi <- inherit_pointer$inherit_forge_package_fields$values_inherited %||% list()
        if (!is.null(vi[[field_name]]) && predicate(vi[[field_name]])) {
          return(list(hit = TRUE, source = paste0(
            inherit_pointer$inherit_forge_package_fields$source_wt %||% "inherit_pointer",
            "_values_inherited")))
        }
      }
      # 2. lineage_wts forge_package 탐색
      for (lw in lineage_wts) {
        lp <- file.path(lw, "forge_package.json")
        if (!file.exists(lp)) next
        lpkg <- tryCatch(fromJSON(lp, simplifyVector = FALSE),
                          error = function(e) NULL)
        if (is.null(lpkg)) next
        v <- lpkg[[field_name]]
        # divergence는 nested vs_factor_engine 경유 가능
        if (field_name == "divergence_factor_engine_vs_realized_pp" && is.null(v)) {
          v <- lpkg$vs_factor_engine$divergence_pp
        }
        if (!is.null(v) && predicate(v)) {
          return(list(hit = TRUE, source = basename(lw)))
        }
      }
      list(hit = FALSE, source = NULL)
    }

    # 2. measurement_basis_primary (+20)
    mbp_primary_ok <- !is.null(forge_pkg) &&
      isTRUE(forge_pkg$measurement_basis_primary == "forge_realized_share_based")
    if (mbp_primary_ok) {
      score <- score + 20
      components$measurement_basis_primary <- 20
      if (!is.null(forge_inherit_wt)) {
        inherited_from$measurement_basis_primary <- forge_inherit_wt
      }
    } else {
      mbp_inherit <- inherit_field(
        "measurement_basis_primary",
        function(v) isTRUE(as.character(v) == "forge_realized_share_based")
      )
      if (mbp_inherit$hit) {
        score <- score + 20
        components$measurement_basis_primary <- 20
        inherited_from$measurement_basis_primary <- mbp_inherit$source
      } else {
        components$measurement_basis_primary <- 0
      }
    }

    # 3. schedule_density_ratio (+20)
    density_primary_ok <- !is.null(forge_pkg) &&
      !is.null(forge_pkg$schedule_density_ratio) &&
      isTRUE(forge_pkg$schedule_density_ratio >= 0.95)
    if (density_primary_ok) {
      score <- score + 20
      components$schedule_density <- 20
      if (!is.null(forge_inherit_wt)) {
        inherited_from$schedule_density <- forge_inherit_wt
      }
    } else {
      density_inherit <- inherit_field(
        "schedule_density_ratio",
        function(v) {
          vn <- suppressWarnings(as.numeric(v))
          !is.na(vn) && vn >= 0.95
        }
      )
      if (density_inherit$hit) {
        score <- score + 20
        components$schedule_density <- 20
        inherited_from$schedule_density <- density_inherit$source
      } else {
        components$schedule_density <- 0
      }
    }

    # 4. divergence < 0.3pp (+20)
    diverg <- forge_pkg$divergence_factor_engine_vs_realized_pp %||%
              forge_pkg$vs_factor_engine$divergence_pp %||% NA
    # 방어적 수치 강제: divergence가 문자열 "NA"(JSON string) 등 비-수치로 저장된 경우
    # is.na("NA")==FALSE → abs("NA") 에러. inherit_field predicate와 동일하게 coercion 후 판정.
    # coercion 실패("NA"/"unavailable" 등) = divergence 미가용 → 해당 component 0점.
    diverg <- suppressWarnings(as.numeric(diverg))
    if (!is.na(diverg) && abs(diverg) < 0.3) {
      score <- score + 20
      components$divergence_low <- 20
      if (!is.null(forge_inherit_wt)) {
        inherited_from$divergence_low <- forge_inherit_wt
      }
    } else {
      div_inherit <- inherit_field(
        "divergence_factor_engine_vs_realized_pp",
        function(v) {
          vn <- suppressWarnings(as.numeric(v))
          !is.na(vn) && abs(vn) < 0.3
        }
      )
      if (div_inherit$hit) {
        score <- score + 20
        components$divergence_low <- 20
        inherited_from$divergence_low <- div_inherit$source
      } else {
        components$divergence_low <- 0
      }
    }

    # 5. governor_concord_certificate (+10)
    concord_path <- file.path(governor_dir, "governor_concord_certificate.json")
    waiver_path <- file.path(governor_dir,
                             "governor_concord_with_waiver_certificate.json")
    if (file.exists(concord_path) || file.exists(waiver_path)) {
      score <- score + 10
      components$governor_concord <- 10
    } else {
      components$governor_concord <- 0
    }

    tier <- if (score >= 90) "HEALTHY" else if (score >= 70) "WARNING" else "DRIFTED"
    per_str[[str_id]] <- list(
      score = score, tier = tier,
      components = components, wt_dir = wt_dir,
      alias_applied = alias_applied,
      lineage_inherited_from = if (length(inherited_from) > 0) inherited_from else NULL,
      lineage_wts_audited = if (length(lineage_wts) > 0) basename(lineage_wts) else NULL
    )
    total_score <- total_score + score
  }

  # Book-level mean
  book_score <- if (length(per_str) > 0) total_score / length(per_str) else NA
  book_tier <- if (is.na(book_score)) "UNKNOWN" else
               if (book_score >= 90) "HEALTHY" else
               if (book_score >= 70) "WARNING" else "DRIFTED"

  list(
    score = round(book_score, 1),
    tier = book_tier,
    n_admitted = length(admitted_ids),
    per_str = per_str,
    audited_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    charter_ref = "v1.2 §10 Measurement Coherence Health Score"
  )
}

# Defensive %||%
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# CLI entrypoint (Rscript 호출용)
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  args <- commandArgs(trailingOnly = TRUE)
  bs_path <- args[1]
  wt_root_arg <- if (length(args) >= 2) args[2] else "qepm/mailbox/worktask"
  result <- audit_book_measurement_coherence(bs_path, wt_root = wt_root_arg)
  cat(sprintf("=== Measurement Coherence Health ===\n"))
  cat(sprintf("Book score: %s / 100\n", result$score))
  cat(sprintf("Tier: %s\n", result$tier))
  cat(sprintf("N admitted: %s\n", result$n_admitted))
  for (sid in names(result$per_str)) {
    s <- result$per_str[[sid]]
    cat(sprintf("  %s: %d/100 [%s]\n", sid, s$score, s$tier))
  }
  log_path <- "/tmp/measurement_coherence_health.log"
  writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE), log_path)
  cat(sprintf("Log: %s\n", log_path))
}
