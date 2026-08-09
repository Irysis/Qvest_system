## STEP 13: 적대검증 결과 통합 → adv_mechanical_selection.csv (마스터 판정표)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt,...) { cat(sprintf(paste0("[adv13] ",fmt,"\n"),...)); flush.console() }
## 10 단계 산출물은 세부표로 개명 보존
if (file.exists(file.path(OUT,"adv_mechanical_selection.csv")))
  file.rename(file.path(OUT,"adv_mechanical_selection.csv"), file.path(OUT,"adv_mechanical_selection_battery.csv"))

M <- rbindlist(list(
 data.table(test="T1_replication", detail="thr-20 raw skew ON/OFF", observed=0.5808, null_or_se="p1 se 0.1908(paired bb)", p_or_ratio=3.04, verdict="복제 성공 — 수치 일치"),
 data.table(test="T1_replication", detail="thr-30 raw skew ON/OFF", observed=0.6909, null_or_se="p1 se 0.2101(paired bb)", p_or_ratio=3.29, verdict="복제 성공 — 수치 일치"),
 data.table(test="T2_selfsd_identity", detail="자기-sd 표준화 후 왜도 변화", observed=1.11e-16, null_or_se="-", p_or_ratio=NA, verdict="검사① = 항등변환 · 정보량 0"),
 data.table(test="T3_volstd_ewma094", detail="thr-20 EWMA표준화 잔차 skew diff", observed=0.3460, null_or_se="raw 0.5853 대비", p_or_ratio=0.591, verdict="41% 가 변동성혼합 산물"),
 data.table(test="T3_volstd_ewma094", detail="thr-30 EWMA표준화 잔차 skew diff", observed=0.4688, null_or_se="raw 0.7103 대비", p_or_ratio=0.660, verdict="34% 가 변동성혼합 산물"),
 data.table(test="T3_volstd_garch", detail="thr-20 GARCH(1,1)-t 잔차 skew diff", observed=0.3326, null_or_se="raw 0.5808 대비", p_or_ratio=0.573, verdict="43% 가 변동성혼합 산물"),
 data.table(test="T4_robust_bowley", detail="thr-20 Bowley(p=.25) 원수익", observed=0.0319, null_or_se="moment skew 0.5808", p_or_ratio=0.055, verdict="분포 몸통엔 반전 없음"),
 data.table(test="T4_robust_bowley", detail="thr-30 Bowley(p=.25) 원수익", observed=0.0183, null_or_se="moment skew 0.6909", p_or_ratio=0.026, verdict="분포 몸통엔 반전 없음"),
 data.table(test="T5_influence", detail="thr-20 최대1일(2026-07-31 +19.98%) 기여", observed=0.2699, null_or_se="ON skew 0.2717", p_or_ratio=0.993, verdict="★단일 관측이 왜도의 99%"),
 data.table(test="T5_influence", detail="thr-20 상위3 제거 후 ON skew", observed=-0.0683, null_or_se="원 +0.2717", p_or_ratio=NA, verdict="★부호 반전 소멸"),
 data.table(test="T5_influence", detail="thr-30 상위3 제거 후 ON skew", observed=-0.0014, null_or_se="원 +0.3959", p_or_ratio=NA, verdict="★부호 반전 소멸"),
 data.table(test="T6_yearjk", detail="thr-20 2026 제외 diff", observed=0.2994, null_or_se="전체 0.5808", p_or_ratio=0.515, verdict="1.7% 표본이 효과의 48%"),
 data.table(test="T6_yearjk", detail="thr-30 2026 제외 diff", observed=0.2857, null_or_se="전체 0.6909", p_or_ratio=0.413, verdict="1.7% 표본이 효과의 59%"),
 data.table(test="T7_exitmech", detail="thr-20 경계층(-30<dd<=-20) skew", observed=-0.2418, null_or_se="OFF -0.3091", p_or_ratio=NA, verdict="혐의(a) 이탈역학 기각 — 경계층엔 반전 없음"),
 data.table(test="T7_exitmech", detail="thr-20 심층(dd<=-30) skew", observed=0.3959, null_or_se="OFF -0.3091", p_or_ratio=NA, verdict="효과는 깊이에 단조 — 이탈 근접성 아님"),
 data.table(test="T8_se_source", detail="thr-20 dd재생성 부트 se vs paired se", observed=0.2542, null_or_se="paired 0.1908", p_or_ratio=1.33, verdict="★p1 se 는 선택 메커니즘 변동을 조건부 고정"),
 data.table(test="T8_se_source", detail="thr-30 dd재생성 부트 se vs paired se", observed=0.3934, null_or_se="paired 0.2101", p_or_ratio=1.87, verdict="★동 se 과소평가 + 부트평균 +0.377(0 아님)"),
 data.table(test="T9_null_raw", detail="thr-20 raw · NULL_B signflip GARCH", observed=0.5853, null_or_se="q95 1.0383 sd 0.7088", p_or_ratio=0.1500, verdict="★귀무 안 → 반증"),
 data.table(test="T9_null_raw", detail="thr-30 raw · NULL_B signflip GARCH", observed=0.7103, null_or_se="q95 1.2384 sd 0.7437", p_or_ratio=0.1145, verdict="★귀무 안 → 반증"),
 data.table(test="T9_null_raw", detail="thr-20 raw · NULL_D iidshape GARCH", observed=0.5853, null_or_se="q95 1.0101 sd 0.6693", p_or_ratio=0.1280, verdict="★귀무 안 → 반증"),
 data.table(test="T9_null_raw", detail="thr-30 raw · NULL_D iidshape GARCH", observed=0.7103, null_or_se="q95 1.0944 sd 0.5996", p_or_ratio=0.1165, verdict="★귀무 안 → 반증"),
 data.table(test="T9_null_raw", detail="thr-20 raw · NULL_E blockboot+dd재생성", observed=0.5853, null_or_se="q95 0.6482 sd 0.2513", p_or_ratio=0.0960, verdict="★귀무 안 → 반증"),
 data.table(test="T9_null_raw", detail="thr-30 raw · NULL_E blockboot+dd재생성", observed=0.7103, null_or_se="q95 1.1786 sd 0.4218", p_or_ratio=0.1627, verdict="★귀무 안 → 반증"),
 data.table(test="T10_null_resid", detail="thr-20 EWMA잔차 skew · NULL_D", observed=0.3460, null_or_se="q95 0.2318 sd 0.1413", p_or_ratio=0.0160, verdict="귀무 밖 — 잔존 후보"),
 data.table(test="T10_null_resid", detail="thr-30 EWMA잔차 skew · NULL_D", observed=0.4688, null_or_se="q95 0.2765 sd 0.1740", p_or_ratio=0.0020, verdict="귀무 밖 — 잔존 후보"),
 data.table(test="T10_null_resid", detail="thr-20 EWMA잔차 skew · NULL_E(최보수)", observed=0.3460, null_or_se="q95 0.5198 sd 0.2966", p_or_ratio=0.1180, verdict="★귀무 안"),
 data.table(test="T10_null_resid", detail="thr-30 EWMA잔차 skew · NULL_E(최보수)", observed=0.4688, null_or_se="q95 0.5455 sd 0.3621", p_or_ratio=0.0822, verdict="★귀무 안"),
 data.table(test="T10_null_resid", detail="thr-20 EWMA잔차 Bowley · 3귀무 전부", observed=0.0737, null_or_se="p=0.006/0.000/0.018", p_or_ratio=0.0180, verdict="유일하게 3귀무 전부 밖 — 잔존 후보"),
 data.table(test="T11_integrity", detail="2026 연율화 vol (표본 최대)", observed=0.7099, null_or_se="차순위 1998 = 0.4931", p_or_ratio=1.44, verdict="지배 연도 — 원천 확인 필요"),
 data.table(test="T11_integrity", detail="2026-07-31 일간 +19.98% (36년 최대)", observed=0.1998, null_or_se="차순위 2008-10-30 = 0.1223", p_or_ratio=1.63, verdict="전례 없는 프린트 — 원천 확인 필요")
))
fwrite(M, file.path(OUT, "adv_mechanical_selection.csv"))
say("마스터 판정표 저장 → adv_mechanical_selection.csv (%d행)", nrow(M))
say("동봉 세부표: adv_mechanical_selection_diag.csv(38) · _null.csv(12) · _resid_null.csv(12) · _battery.csv(10)")
print(M[test %in% c("T9_null_raw"), .(detail, observed, p_one=p_or_ratio, verdict)])
