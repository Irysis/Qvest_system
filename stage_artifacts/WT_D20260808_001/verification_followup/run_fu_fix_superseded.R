# =============================================================================
# run_fu_fix_superseded.R — run_fu_finalize.R 의 자기덮어쓰기 버그 수리
#
# 버그: F2/F3 에서
#     val$X$superseded_20260808 <- val$X      # ① 하위필드로 구 객체 보존
#     val$X <- list(...)                      # ② 객체 **전체**를 교체 → ①이 사라짐
#   ②가 ①을 삼켰다. run_fu_verify.R 의 superseded 존재 검사가 FALSE 로 검거.
#   ★"보존했다" 는 주장을 검사기가 반증한 사례 — 주장만 있고 값은 없었다.
# 복원 출처: alpha_validation_pre_followup_20260809.json (finalize 직전 백업)
# =============================================================================
suppressPackageStartupMessages({library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001")
say <- function(f,...) cat(sprintf(paste0("[fixsup] ",f,"\n"),...))

BK <- file.path(OUT,"alpha_validation_pre_followup_20260809.json")
stopifnot(file.exists(BK))
old <- fromJSON(BK, simplifyVector=FALSE)
val <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)

o_f2 <- old$falsification_observables$F2_agent_individual_flow
o_f3 <- old$falsification_observables$F3_beta_drag
stopifnot(!is.null(o_f2), !is.null(o_f3))
say("백업에서 복원할 구 값: F2 D03_t=%s Q01_t=%s · F3 D03 Q5_beta=%s univ=%s",
    o_f2$D03_t, o_f2$Q01_t, o_f3$D03$Q5_beta_med, o_f3$D03$univ_med)

val$falsification_observables$F2_agent_individual_flow$superseded_20260808 <- o_f2
val$falsification_observables$F3_beta_drag$superseded_20260808 <- o_f3
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, null="null")

v <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
a <- v$falsification_observables$F2_agent_individual_flow$superseded_20260808
b <- v$falsification_observables$F3_beta_drag$superseded_20260808
say("재읽기 검증: F2 superseded 존재 %s (D03_t=%s) · F3 superseded 존재 %s (D03 Q5_beta=%s)",
    !is.null(a), if (is.null(a)) NA else a$D03_t, !is.null(b), if (is.null(b)) NA else b$D03$Q5_beta_med)
say("정본 값 유지 확인: F2 D03_turnover_ctl_t=%s · F3 D03 t_nw_lag60=%s",
    v$falsification_observables$F2_agent_individual_flow$D03_turnover_ctl_t,
    v$falsification_observables$F3_beta_drag$D03$t_nw_lag60)
stopifnot(!is.null(a), !is.null(b))
say("=== superseded 복원 완료 ===")
