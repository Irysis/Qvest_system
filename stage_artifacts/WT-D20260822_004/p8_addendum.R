## WT-D20260822_004 · P8 — 적대검증 실측(P7)을 산출물 2종에 추가 반영 (비파괴 addendum)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260822_004"; MB <- "qepm/mailbox/worktask/WT-D20260822_004"

add <- list(
  source = "stage_artifacts/WT-D20260822_004/p7_adversarial.R (Self-Adversarial Challenge 중 신규 실측)",
  note = "적대검증에서 제기된 반론 3건이 근거를 요구했고, 방어 대신 재측정했다. 결과가 arm 별 증거력을 갈랐다.",
  top25_overlap = list(
    definition = "월별 top-25 명단의 Jaccard (C0 대비). '처치가 포트폴리오를 실제로 바꿨는가' 의 직접 측정.",
    C0_vs_C1 = list(jaccard_median = 0.4706, overlap_names_median = 16, replaced_names_median = 9),
    C0_vs_C2 = list(jaccard_median = 0.7857, overlap_names_median = 22, replaced_names_median = 3),
    C0_vs_C3 = list(jaccard_median = 0.3889, overlap_names_median = 14, replaced_names_median = 11),
    verdict = "★C1 은 매월 25종 중 9종(36%)을 교체하고도 성과 차이 -0.41%p/yr(t -0.24) — 실질 개입에 대한 무반응이므로 강한 null. C2 는 3종 교체로 개입이라 부르기 어려워 약한 null. 두 arm 의 null 을 같은 무게로 읽지 말 것."),
  material_threshold_sensitivity = list(
    prereg_threshold = 8.2228,
    C1 = list(ci95_hi = 3.0138, excludes = list(`8.2228` = TRUE, `4.1114` = TRUE, `3.0` = FALSE, `2.0` = FALSE)),
    C2 = list(ci95_hi = 1.4872, excludes = list(`8.2228` = TRUE, `4.1114` = TRUE, `3.0` = TRUE, `2.0` = TRUE)),
    verdict = "문턱을 절반(4.11)으로 낮춰도 두 arm 모두 powered null 유지. ★정직한 한계: C1 은 +3.0%p/yr 수준의 미세 효과까지는 배제하지 못한다. 다만 벽 도달에 8.22%p 가 필요하므로 라운드 결론은 그 한계에 종속되지 않는다."),
  c2_clip_coverage = list(
    share_abs_z_gt_2 = list(median = 0.0339, mean = 0.0459), monthly_max_abs_z_median = 4.08,
    verdict = "★clip(±2.0)이 건드린 관측은 전체 셀의 3.4% — C2 의 매개 미이동(solo-advocate 0.938배)·스코어 rank cor 0.992·명단 3종 교체의 직접 원인. 사전등록 시점에 이 비율을 확인했어야 했다는 절차 결함을 기록한다."),
  clean_window_recheck = list(
    window = "2015-07 ~ (n=133, universe_exit_unrecorded_pre201512 미해당 구간)",
    C1 = list(annual_pct = 0.975, t_nw3 = 0.483, mde_annual_pct = 4.039),
    C2 = list(annual_pct = 0.672, t_nw3 = 0.546, mde_annual_pct = 2.464),
    verdict = "청정창 단독으로도 powered null (MDE 4.04 / 2.46 < MATERIAL 8.22). 부호는 오염창(음수)→청정창(양수)으로 뒤집히나 어느 쪽도 유의하지 않다. 유니버스 결함창 포함이 처치를 부당하게 불리하게 만들지 않았다 — 승계 편향 방향(하방/중립, 생존자 편향 아님)과 정합."),
  positive_control_failure_disclosed = "사전등록 C0_LEAK1 (t >= +2.0) 미통과: t +0.667. 창-도달가능성 의무는 사전등록이 같은 절에서 ORACLE_FWD 소관으로 규정했고 그것으로 충족했다. 실패 사실을 3곳에 기록하며 은폐하지 않는다.",
  ax008 = list(self_adversarial = "PASS (7건 — ACCEPT 1 / PARTIAL 2 / REBUTTAL 4, 3건은 신규 실측 근거)",
    forge = "미수행 — NO_TRANSITION(자본 후보 미제출)", architect = "미호출",
    sources_passed = 1, requirement = 2,
    verdict = "2/3 미충족이나 결함 아님 — 본 라운드는 graduation triangulation 대상이 아니다(자본 후보 부재). 자본 경로 진입 시 forge + architect 2 source 추가 요구됨을 명시."),
  challenge_note = "qepm/mailbox/worktask/WT-D20260822_004/challenge_note.md")

for (f in c(file.path(OUT,"alpha_validation.json"), file.path(MB,"alpha_package.json"))) {
  d <- fromJSON(f, simplifyVector = FALSE)
  d$adversarial_addendum <- add
  write_json(d, f, pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
  cat("[patched]", f, "\n")
}
cat("OK\n")
