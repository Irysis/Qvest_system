suppressPackageStartupMessages({library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(gsub("\\\\","/",ROOT))
OUT <- "stage_artifacts/infra/fq223_rollover_downstream_20260810"
f <- file.path(OUT,"fq223_findings.json")
F <- fromJSON(f, simplifyVector=FALSE)
E <- readRDS(file.path(OUT,"e1_results.rds"))
F$n_arms <- 6
F$selection_type <- "chain_diagnostic_prereg_battery (DSR 부적용 — argmax pick 없음, 판정은 min over RA arms)"
F$robustness <- list(
  block_bootstrap = list(B=2000, block=12,
    delta_t_q05=unname(E$boot_d_q05), delta_t_q95=unname(E$boot_d_q95),
    delta_t_pos_frac=E$boot_pos,
    t_RA_ge2_frac=E$tRA_ge2, t_plain_ge2_frac=E$tplain_ge2,
    real_beats_fake_frac=0.4825,
    reading="Δt 90% 구간이 0 포함 · 진짜가 가짜를 이기는 비율 0.4825 ⇒ 개선 크기·롤오버 귀속 주장 철회. 판정(양 arm 문턱 위)은 유지"),
  leave_one_year_out = list(n_years=nrow(E$loo), delta_t_positive_years=sum(E$loo$d>0),
    min_delta_t=min(E$loo$d), min_t_RA=min(E$loo$t_RA), min_t_plain=min(E$loo$t_plain),
    reading="24/24 해에서 Δt>0 · t_RA 최소 2.696 · t_plain 최소 2.053 — 연도 강건"),
  month_drop = list(
    drop_apr_t_plain=1.8500, drop_apr_t_RA=2.6497,
    drop_aprmay_t_plain_recon279=1.9577, drop_aprmay_t_RA_recon279=2.2679,
    drop_aprmay_t_DB283=2.2222,
    reading="★원(오염) M26 은 4월 제외 시 1.850 으로 문턱 미달 · 수리판은 2.650 유지. 1.958(재구성/279m) vs 2.222(DB/283m) 는 basis·창이 함께 달라 나란히 읽지 말 것"))
F$verdict_basis <- "REAFFIRM 은 방법 B(사전등록 결정적 반증)에 근거한다. 방법 A 는 M01 대조 실패로 달력 계절성과 교락되어 증거로 쓰지 않는다."
F$headline_numbers <- list(
  primary="공통 279개월 재구성 basis: t_plain +2.4783 → t_RA +3.1281 (사전등록 arm) / 최솟값 arm +2.8101",
  secondary_extrapolation="DB basis 이식 t_B = +3.2050 (Δt basis 불변 가정 위의 외삽 — 1급 아님)",
  method_A="t_A = +2.2222 (DB basis 283→235개월) · 기대 +2.3285 · Δ -0.1063")
write_json(F, f, auto_unbox=TRUE, pretty=TRUE, digits=NA)
cat(sprintf("[f1] findings 갱신 완료 — 최상위 필드 %d\n", length(F)))
chk <- fromJSON(f, simplifyVector=FALSE)
cat(sprintf("[f1] 재읽기 검증: verdict=%s · n_arms=%s · robustness 존재=%s\n",
            chk$verdict, chk$n_arms, !is.null(chk$robustness)))
