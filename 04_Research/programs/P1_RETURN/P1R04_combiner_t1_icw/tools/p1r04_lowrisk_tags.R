## P1R04 저위험 기계 꼬리표 → 코어 v4 기저 풀 입력(results/lowrisk_tags.json) — 측정 · 사이드카 뒤 한 번(판정 아님 · 성과 무참조)
##   입력 = 사이드카 산출 results/lowrisk_share_visible.json 의 tags(카테고리 → 참 · 거짓 · NA — tools/p1r04_lowrisk_share.R)
##   출력 = {"engines": {"<T1 엔진 경로(저장소 상대)>": 논리값 1개}} — 코어 v4 p4.R .rcp4_lowrisk_tagfile 이 원천 라운드 꼬리표로 읽는다
##     (참 = 영수증 없이도 lowrisk_confirm_pending · 판독 불가 = 꼬리표 · fail-closed — 변경분 점검 2 R-D · 판단 T4 C-20261113-037).
##   매핑: 카테고리 f → 04_Research/strategies/FC_FAM_<f>_ICW/engine.R · total → FC_TOTAL_ICW/engine.R.
##     사이드카 tag NA(방어 · 위험 · 국면 = 이미 저위험 묶음 · 기록만) = 참으로 적는다(저위험 엔진 — 코어의 가족 관문과 같은 뜻 · 풀림은 엔진 단위 도훈 결정).
##   T0 엔진(FC_FAM_<f> · FC_TOTAL_EW)은 적지 않는다 — 그 저위험 판독은 P1R03 영수증(LOWBETA-ENGINES-BASE-USE-20261113)이 맡는다.
## 실행(저장소 루트): Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_lowrisk_tags.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
RD <- "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"
src <- file.path(RD, "results", "lowrisk_share_visible.json")
if (!file.exists(src)) stop("[lowrisk_tags] 사이드카 산출 없음: ", src)
S <- rc_json_read(src)
if (!identical(S$schema, "p1r04_lowrisk_share_visible_v1") || !is.list(S$tags) || !length(S$tags)) stop("[lowrisk_tags] 사이드카 형식 불일치")
eng <- list(); miss <- character(0)
for (f in names(S$tags)) {
  p <- if (identical(f, "total")) "04_Research/strategies/FC_TOTAL_ICW/engine.R" else sprintf("04_Research/strategies/FC_FAM_%s_ICW/engine.R", f)
  if (!file.exists(file.path(ROOT, p))) { miss <- c(miss, p); next }
  v <- S$tags[[f]]
  eng[[p]] <- if (is.null(v) || (length(v) == 1L && is.na(v))) TRUE else isTRUE(v)
}
if (length(miss)) stop("[lowrisk_tags] 엔진 파일 없음: ", paste(miss, collapse = ", "))
if (length(eng) != 15L) stop("[lowrisk_tags] T1 엔진 수 ", length(eng), " ≠ 15")
out <- list(schema = "rc_lowrisk_tags_v1", round_id = "P1R04_combiner_t1_icw", written_at = rc_now(),
            source = src, source_md5 = rc_md5(src),
            rule = "사이드카 tags(카테고리) → T1 엔진 경로 · NA(이미 저위험 묶음) = TRUE · 참 = 기저 풀 lowrisk_confirm_pending(엔진 단위 release_decision 전까지)",
            engines = eng)
f_out <- file.path(RD, "results", "lowrisk_tags.json")
rc_json_write(out, f_out)
cat(sprintf("[lowrisk_tags] %s · 엔진 %d · 참 %d(%s)\n", f_out, length(eng), sum(unlist(eng)),
            paste(basename(dirname(names(eng)[unlist(eng)])), collapse = ",")))
