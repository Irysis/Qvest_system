# wp3_card_calibration.R — DIST 음성 카드의 보정도 (사전등록 §4-①)
#
# 질문: 음성 카드가 "이 경로는 죽었다"고 적은 뒤, 같은 경로를 쓴 **후속** 칸들이 실제로 열위였나.
# 방법: 카드 → supporting_l_codes → 근거 칸(원장 attempt) → 그 칸의 팩터 id 집합(= 경로)
#       → 카드 이후에 그 팩터를 하나라도 쓴 칸(same_path) 대 안 쓴 칸(other) 의 PORT_t·등급 대조.
# ★INV-7: 카드는 경로 단위이지 계열(family) 판결이 아니다. 그래서 family 가 아니라 **팩터 id** 로 맞춘다.
# ★근거 L-code 가 강화 원장 밖(alpha_search 등)이면 그 카드는 여기서 잴 수 없다 — 세어서 보고한다.

source("R/build_world.R")

.cc_root <- ar_root()

cc_load_negative_cards <- function() {
  fs <- list.files(file.path(.cc_root, "qepm/memory/axioms/distilled"), pattern = "json$", full.names = TRUE)
  cs <- lapply(fs, function(f) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL))
  cs <- Filter(function(c) !is.null(c) && identical(c$polarity, "negative"), cs)
  cs
}

# 스펙에서 팩터 id 집합
.cc_factor_ids <- function(spec_path) {
  sp <- .bw_load_spec(spec_path)
  if (is.null(sp) || !length(sp)) return(character(0))
  fs <- sp$factors
  if (is.null(fs) || !length(fs)) {
    fs <- list()
    for (k in c("factor2", "factor3")) if (!is.null(sp[[k]]) && !identical(sp[[k]]$kind %||% "", "none")) fs <- c(fs, list(sp[[k]]))
  }
  ids <- vapply(fs, function(f) as.character(f$id %||% f$name %||% ""), character(1))
  ids[nzchar(ids)]
}

#' 카드 1장의 보정도
cc_card_calibration <- function(card, att) {
  lcs <- as.character(unlist(card$supporting_l_codes %||% list()))
  ev  <- att[!is.na(att$l_code) & att$l_code %in% lcs, , drop = FALSE]
  created <- .ar_ts(card$created_at %||% card$drafted_at)
  out <- list(dist_id = as.character(card$dist_id %||% NA), status = as.character(card$status %||% NA),
              family = as.character(card$scope_draft$factor_family %||% card$scope$factor_family %||% NA),
              n_lcodes = length(lcs), n_evidence_cells = nrow(ev), created = created,
              path = character(0), n_same_later = 0L, n_other_later = 0L,
              same_med = NA_real_, other_med = NA_real_, same_f = NA_real_, other_f = NA_real_,
              verdict = "evidence_outside_ledger")
  if (!nrow(ev)) return(out)
  path <- unique(unlist(lapply(ev$spec, .cc_factor_ids)))
  out$path <- path
  if (!length(path)) { out$verdict <- "evidence_has_no_spec"; return(out) }
  cut <- max(c(created, ev$closed_at), na.rm = TRUE)
  later <- att[att$measured & !is.na(att$closed_at) & att$closed_at > cut &
                 !(att$base_id %in% ev$base_id), , drop = FALSE]      # 같은 entry 는 제외(자기참조)
  if (!nrow(later)) { out$verdict <- "no_later_cells"; return(out) }
  later_ids <- lapply(later$spec, .cc_factor_ids)
  same <- vapply(later_ids, function(ids) length(intersect(ids, path)) > 0, logical(1))
  out$n_same_later <- sum(same); out$n_other_later <- sum(!same)
  if (sum(same) < 3 || sum(!same) < 3) { out$verdict <- "too_few_later_same_path"; return(out) }
  out$same_med  <- median(later$port_t[same]);  out$other_med <- median(later$port_t[!same])
  out$same_f    <- mean(later$grade[same] %in% "F");  out$other_f <- mean(later$grade[!same] %in% "F")
  out$verdict <- if (out$same_med < out$other_med) "held" else "not_held"
  out
}

cc_run <- function(att, cards = cc_load_negative_cards()) {
  res <- lapply(cards, cc_card_calibration, att = att)
  d <- do.call(rbind, lapply(res, function(r) data.frame(
    dist_id = r$dist_id, status = r$status, family = r$family, n_lcodes = r$n_lcodes,
    n_evidence = r$n_evidence_cells, n_path = length(r$path),
    n_same = r$n_same_later, n_other = r$n_other_later,
    same_med = r$same_med, other_med = r$other_med, diff = r$same_med - r$other_med,
    same_f = r$same_f, other_f = r$other_f, verdict = r$verdict, stringsAsFactors = FALSE)))
  d
}
