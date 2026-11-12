## P1R04 저위험 몫 사이드카(철학 P1 C-20261113-027 수용 · 판정 아님 · 측정 전 고정 · 사양 pins 에 든다)
##   T1 은 저위험 몫을 정적 비율이 아니라 달마다 바뀌는 as-of 무게로 바꾼다. 엔진과 같은 식으로 보는 창 달마다 가중을 다시 내어 몫을 기록하고
##   꼬리표를 단다. 성과를 읽지 않는다(입력 = T1 엔진 사양의 구성원 · 부호 · 정본 IC 접근자 · 결합용 뷰 부호표의 방어 방향).
##   가중(엔진과 같은 식 — 생성기 fc_combiner_gen.R fcc_rule_t1_v0): w_i = max(s_reg_i × ICIR_i(as-of), 0) · ICIR = compute_rolling_ic_all(as-of, 36, 120)
##   몫(그 달 결합용 뷰에 있는 구성원만):
##     방어 부호 몫 — 카테고리마다 Σ w(s_reg = s_def 인 구성원) / Σ w · T0 기준 = 같은 구성원의 개수 비율(등가중이면 무게 = 개수)
##     저위험 쌍둥이 몫 — 비저위험 카테고리 안 저위험 구성원과 같은 식의 구성원(P1R03 결론 범위 쌍 셈 · 아래 표) Σ w / Σ w · T0 기준 = 개수 비율
##     토탈 저위험 몫 — 저위험 4 카테고리 가중 W_f(그 달 카테고리 구성원 가중의 평균)의 합 / 전체 W_f 합 · T0 기준 = 그 달 있는 카테고리 수 비율
##     유효 구성원 수 — (Σw)² / Σw²(카테고리마다 · 기록)
##   꼬리표: 몫 > T0 기준인 보는 창 달의 비율 > behavior_card.json::majority_share 이면 '저위험 쏠림' — 유동성(방어 부호 몫) · 비저위험 카테고리(쌍둥이 몫) ·
##     토탈(저위험 몫)에 단다. 방어 · 위험 · 국면은 이미 저위험 묶음이라 기록만 한다. 꼬리표 = 짝 읽기의 원천 셈(저위험 묶음에 넣는다) · P4 부품 전 도훈 확인 범위.
##   출력 = results/lowrisk_share_visible.json(보는 창 달만 · 몫 요약 · 꼬리표) — 짝 읽기 도구(tools/p1r04_pair_reading.R)가 읽는다.
## 쓰기(저장소 루트 · 측정 뒤 짝 읽기 전): Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_lowrisk_share.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
suppressPackageStartupMessages(library(data.table))
RD <- commandArgs(trailingOnly = TRUE)[1] %||% "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"
RDA <- if (grepl("^([A-Za-z]:|/)", RD)) RD else file.path(ROOT, RD)
TAU <- as.Date(rc_ref_value("06_Registry/behavior_card.json::tau_d", ROOT))
MAJ <- as.numeric(rc_ref_value("06_Registry/behavior_card.json::majority_share", ROOT))
START <- as.Date(local({ e <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R"), envir = e, keep.source = FALSE); e$ma_epoch(root = ROOT)$start_date }))   # 측정 축 정본 활성 epoch 시작일(엔진과 같은 출처)
if (length(START) != 1L || is.na(START)) stop("[lowrisk] 측정 축 시작일을 읽지 못했다")
LOWRISK <- c("defense", "risk", "liquidity", "regime")
TWINS <- list(value = "V19_Debt_to_Market", quality = c("Q15_Debt_to_Equity", "Q16_Debt_to_Assets"), technical = "T14_HLRange")   # P1R03 결론 범위 쌍 셈의 저위험 쌍둥이
sp <- rc_json_read(file.path(ROOT, "04_Research/strategies/FC_TOTAL_ICW/own_spec.json"))
M <- rbindlist(lapply(sp$core$members, as.data.table)); FAMS <- unlist(sp$core$families)
if (!identical(as.integer(sp$core$ic$min_months), 36L) || !identical(as.integer(sp$core$ic$max_months), 120L)) stop("[lowrisk] T1 사양의 IC 창이 이 도구와 다르다")
FC <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/factor_db/factor_combinable.R"), envir = FC, keep.source = FALSE)
IC <- new.env(parent = globalenv())
local({ owd <- setwd(file.path(ROOT, "02_Infrastructure")); on.exit(setwd(owd), add = TRUE)
  invisible(utils::capture.output(suppressMessages({ sys.source(file.path(ROOT, "02_Infrastructure", "config.R"), envir = IC, keep.source = FALSE)
    sys.source(file.path(ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"), envir = IC, keep.source = FALSE) }))) })
meta <- jsonlite::fromJSON(file.path(ROOT, FC$fc_config(ROOT)$storage$dir, FC$fc_config(ROOT)$storage$meta_file), simplifyVector = TRUE)
MM <- as.data.table(meta$months)[, asof := as.Date(asof)][asof >= START & asof <= TAU]
if (!nrow(MM)) stop("[lowrisk] 보는 창 달이 없다")
rows <- list()
for (i in seq_len(nrow(MM))) {
  d <- MM$asof[i]
  r <- NULL; invisible(utils::capture.output(r <- FC$fc_load_month(d, direction = "registry", factors = M$id, missing = "na", dedup = FALSE, family = FALSE)))
  m <- as.data.table(r$meta)[, .(id = Factor_Name, s_reg_v = s_reg, s_def)]
  icr <- NULL; invisible(utils::capture.output(icr <- IC$compute_rolling_ic_all(d, 36L, 120L)))
  X <- merge(M, m, by = "id")                                              # 그 달 뷰에 있는 구성원
  if (any(X$s_reg != X$s_reg_v)) stop("[lowrisk] 뷰 부호 ≠ 사양 부호: ", format(d))
  X[, a := s_reg * icr$ICIR[match(id, icr$Factor_Name)]][, w := fifelse(is.finite(a) & a > 0, a, 0)]
  X[, defsign := !is.na(s_def) & s_def == s_reg]
  fam <- X[, .(n = .N, sw = sum(w), def_w = sum(w[defsign]), def_n = sum(defsign), effn = if (sum(w) > 0) sum(w)^2 / sum(w^2) else NA_real_,
               W = mean(w)), by = family]
  tw <- rbindlist(lapply(names(TWINS), function(f) { Y <- X[family == f]; data.table(family = f, tw_w = sum(Y[id %in% TWINS[[f]]]$w), tw_n = sum(Y$id %in% TWINS[[f]])) }))
  fam <- merge(fam, tw, by = "family", all.x = TRUE)
  fam[, `:=`(date = d, def_share = fifelse(sw > 0, def_w / sw, NA_real_), def_base = def_n / n,
             twin_share = fifelse(sw > 0 & !is.na(tw_w), tw_w / sw, NA_real_), twin_base = fifelse(!is.na(tw_n), tw_n / n, NA_real_))]
  tot <- data.table(family = "total", date = d, lr_share = if (sum(fam$W) > 0) sum(fam[family %in% LOWRISK]$W) / sum(fam$W) else NA_real_,
                    lr_base = sum(fam$family %in% LOWRISK) / nrow(fam))
  rows[[i]] <- list(fam = fam, tot = tot)
}
F <- rbindlist(lapply(rows, `[[`, "fam"), fill = TRUE); TT <- rbindlist(lapply(rows, `[[`, "tot"))
above <- function(s, b) { ok <- is.finite(s) & is.finite(b); if (!any(ok)) NA_real_ else mean(s[ok] > b[ok]) }
summ <- list(); tags <- list()
for (f in FAMS) {
  Z <- F[family == f]
  rec <- list(n_months = nrow(Z), eff_n_median = stats::median(Z$effn, na.rm = TRUE),
              def_share_median = stats::median(Z$def_share, na.rm = TRUE), def_base_median = stats::median(Z$def_base, na.rm = TRUE),
              def_above_share = above(Z$def_share, Z$def_base))
  if (f %in% names(TWINS)) rec <- c(rec, list(twin_share_median = stats::median(Z$twin_share, na.rm = TRUE), twin_base_median = stats::median(Z$twin_base, na.rm = TRUE),
                                             twin_above_share = above(Z$twin_share, Z$twin_base)))
  tag <- if (f == "liquidity") isTRUE(rec$def_above_share > MAJ) else if (f %in% names(TWINS)) isTRUE(rec$twin_above_share > MAJ) else if (f %in% LOWRISK) NA else FALSE
  rec$tag <- tag; summ[[f]] <- rec; tags[[f]] <- tag
}
summ$total <- list(n_months = nrow(TT), lr_share_median = stats::median(TT$lr_share, na.rm = TRUE), lr_base_median = stats::median(TT$lr_base, na.rm = TRUE),
                   lr_above_share = above(TT$lr_share, TT$lr_base))
tags$total <- isTRUE(summ$total$lr_above_share > MAJ); summ$total$tag <- tags$total
out <- list(schema = "p1r04_lowrisk_share_visible_v1", audience = "보는 창(τ_D 이전)만 · 성과 아님(as-of IC 가중 몫)", window = c(format(min(MM$asof)), format(max(MM$asof))),
            majority_share = MAJ, majority_ref = "06_Registry/behavior_card.json::majority_share", twins = TWINS,
            rule = "몫 > T0 기준(개수 비율)인 보는 창 달의 비율 > majority_share 이면 '저위험 쏠림' — 유동성 = 방어 부호 몫 · 비저위험 = 쌍둥이 몫 · 토탈 = 저위험 카테고리 몫 · 방어 · 위험 · 국면 = 기록만(NA)",
            tags = tags, summary = summ)
lk <- rc_after_tau_leaks(out, TAU); if (length(lk)) stop("[lowrisk] 출력에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
dir.create(file.path(RDA, "results"), showWarnings = FALSE, recursive = TRUE)
rc_json_write(out, file.path(RDA, "results", "lowrisk_share_visible.json"))
cat(sprintf("[lowrisk] 보는 창 %s ~ %s · %d달 · 저위험 쏠림 꼬리표 = %s\n", out$window[1], out$window[2], nrow(MM),
            if (any(vapply(tags, isTRUE, TRUE))) paste(names(tags)[vapply(tags, isTRUE, TRUE)], collapse = ",") else "없음"))
