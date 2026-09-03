# ── R12 — 스킬 결손 수리분을 risk_package 에 반영 (idempotent: 문자열 append 없이 전량 대체)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005")
TID <- "WT-R20260829_005"
R4<-readRDS(file.path(OUT,"risk_r4.rds")); R5<-readRDS(file.path(OUT,"risk_r5.rds"))
A <-readRDS(file.path(OUT,"risk_r7_adversarial.rds")); W<-readRDS(file.path(OUT,"risk_r11.rds"))
pkg <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector = FALSE)
KR <- W$KR; WF <- W$WF; S <- W$wf_summary

## ── (1) KR_Bear 스트레스 등재 ───────────────────────────────────────────────
for (i in seq_len(nrow(KR)))
  pkg$risk_summary$stress_tests[[paste0("hist_", tolower(KR$scenario[i]))]] <- round(KR$strat_cum[i], 6)
pkg$risk_summary$stress_test_detail$kr_bear <- list(
  definition = "벤치(KOSPI200) 월별 낙폭이 -20% 이하를 찍은 낙폭 에피소드. 손으로 고른 구간이 아니라 벤치 계열에서 도출했다(에피소드 = 낙폭 이탈~복귀).",
  why_added = "스킬 필수 6종(GFC/EuDebt/China2015/COVID/RateHike2022/KR_Bear) 중 KR_Bear 가 strategy_analyzer 의 def_stress_periods 에 없어 1차 산출에서 누락됐다. 사후 보완분.",
  episodes = lapply(seq_len(nrow(KR)), function(i) as.list(KR[i])),
  finding = paste0(
    "★글로벌 에피소드 목록이 놓친 것을 이 축이 잡는다. 개별 글로벌 구간의 초과손익은 작거나(GFC -5.4%p) ",
    "오히려 양(+)이었는데(Rate Hike +8.3%p), **KR 낙폭 상태 전체**(125개월)로 묶으면 전략 ",
    round(100*KR[scenario=="KR_Bear_ALL", strat_cum],1), "% vs 벤치 ",
    round(100*KR[scenario=="KR_Bear_ALL", bench_cum],1), "% = 초과 ",
    round(100*KR[scenario=="KR_Bear_ALL", active_cum],1), "%p 다. ",
    "최악은 KR_Bear_2(2018-02~2020-11, 34개월): 벤치가 본전(+0.3%)인 동안 전략은 ",
    round(100*KR[scenario=="KR_Bear_2", strat_cum],1), "% 로 초과 ",
    round(100*KR[scenario=="KR_Bear_2", active_cum],1), "%p. ",
    "즉 이 전략의 초과손실은 급락 순간이 아니라 **낙폭 상태의 지속 구간**에 쌓인다. ",
    "MDD -53.03% 를 시장베타로만 귀속한 앞의 서술은 이 축에서 보완돼야 한다 — ",
    "베타가 낙폭의 크기를 설명하지만, 낙폭 **상태에서의 초과손실**은 베타 밖에 있다."))

## ── (2) walk-forward 판정 (Cycle 2 교훈 — as-of 단일단면 금지) ──────────────
pkg$risk_summary$walk_forward_validation <- list(
  rationale = "Cycle 2 교훈: as_of 단일 횡단면 노출/베타는 아티팩트일 수 있다. RF-R1 과 beta 는 walk-forward 평균으로 판정한다.",
  design = paste0("월말 m 마다 그 달 신호의 상위 25종(alpha_scores read-only)을 균등으로 잡고, ",
                  "Omega/D 를 m 이전 756거래일로 재추정해 분산 귀속과 모형 beta 를 계산. n=", nrow(WF),
                  "개월 (", as.character(min(WF$Date)), " ~ ", as.character(max(WF$Date)), ")."),
  market_variance_share = S$mkt_var_share,
  specific_variance_share = S$spec_var_share,
  model_beta_vs_k200 = S$beta_model,
  residual_vol_exposure = S$x_RVOL,
  realized_rolling36m_beta = S$beta_realized_roll36,
  findings = c(
    paste0("as-of 단일단면의 시장 분산비중 ", round(S$mkt_var_share$as_of,4),
           " 는 walk-forward 평균 ", round(S$mkt_var_share$mean,4), " 보다 ",
           round(100*(S$mkt_var_share$as_of - S$mkt_var_share$mean),1),
           "%p 낮다 — 단일단면이 시장 지배도를 **과소**표시했다(과대가 아니라)."),
    paste0("개별위험 비중도 as-of ", round(S$spec_var_share$as_of,4), " vs walk-forward 평균 ",
           round(S$spec_var_share$mean,4), " 로 as-of 가 낮다. 분산 가능한 몫의 실제 상한은 약 ",
           round(100*S$spec_var_share$mean,1), "% 다."),
    paste0("★잔차변동성 노출의 **부호가 뒤집힌다**: as-of ", round(S$x_RVOL$as_of,4),
           " vs walk-forward 평균 ", round(S$x_RVOL$mean,4), " (범위 ", round(S$x_RVOL$min,3),
           " ~ ", round(S$x_RVOL$max,3), "). as-of 값은 관측 범위의 최댓값이다. ",
           "따라서 '이 후보가 고변동성으로 기운다'는 as-of 기반 서술은 성립하지 않는다 — ",
           "역사적으로는 오히려 저변동성 쪽이다(Cycle 2 vol-centric 점검 항목)."),
    paste0("모형 beta walk-forward 평균 ", round(S$beta_model$mean,4), " (범위 ",
           round(S$beta_model$min,3), "~", round(S$beta_model$max,3), ")."),
    paste0("실현 롤링 36개월 beta 평균 ", round(S$beta_realized_roll36$mean,4), " (범위 ",
           round(S$beta_realized_roll36$min,3), "~", round(S$beta_realized_roll36$max,3),
           "), 1 미만인 창은 ", round(100*S$beta_realized_roll36$pct_below_1,1),
           "% 뿐이다. 최근 12개월 평균은 ", round(S$beta_realized_roll36$last12_mean,4), ".")))

## ── (3) RF-R1 을 walk-forward 로 재판정 (detail 전량 대체 = idempotent) ─────
pkg$red_flags[[1]]$value <- round(100*S$mkt_var_share$mean, 2)
pkg$red_flags[[1]]$judgement_basis <- "walk_forward_mean (Cycle 2: single-snapshot 판정 금지)"
pkg$red_flags[[1]]$detail <- paste0(
  "walk-forward 평균 시장 분산비중 ", round(100*S$mkt_var_share$mean,1), "% > 40% (n=", nrow(WF),
  "개월, 월별 발화율 ", round(100*S$mkt_var_share$pct_months_above_40,1), "%, 범위 ",
  round(100*S$mkt_var_share$min,1), "~", round(100*S$mkt_var_share$max,1), "%). ",
  "as-of 단일단면은 ", round(100*S$mkt_var_share$as_of,1), "% 로 오히려 **과소**표시했다. ",
  "롱온리·Sigma w=1·25종 제약 아래에서 이 지배는 구조적이다. ",
  "무신호 대조(as-of 기준, 무작위 25종 균등 500개) 시장 분산비중 ", round(A$sc6$random_mean,3),
  " vs 기준바스켓 ", round(A$sc6$ew_top25,3), " — 같은 시점 기준으로는 본 후보가 무신호선보다 낮다. ",
  "★단 그 대조는 as-of 1개월분이므로 walk-forward 로 확장되지 않았다(미측정). ",
  "노출 상한 조정은 optimizer scope — 여기서는 측정·통보만 한다.")
pkg$risk_summary$no_signal_control$scope_caveat <-
  "본 대조는 as-of(2026-07-31) 단일 시점이다. walk-forward 확장은 미측정 — RF-R1 원인 귀속을 전 구간으로 일반화하지 말 것."

## ── (4) RISK-2 재작성 — walk-forward 가 앞의 두 초안을 모두 정정한다 ────────
pkg$challenge_flags[[2]]$claim <-
  "beta 는 단일 추정으로 인용할 수 없을 만큼 불안정하다. 특히 alpha 의 거울상 논거가 의존하는 beta<1 은 walk-forward 평균에서 성립하지 않는다."
pkg$challenge_flags[[2]]$evidence <- paste0(
  "실현 롤링 36개월 beta: 평균 ", round(S$beta_realized_roll36$mean,4), ", 범위 ",
  round(S$beta_realized_roll36$min,3), "~", round(S$beta_realized_roll36$max,3),
  ", 1 미만인 창 ", round(100*S$beta_realized_roll36$pct_below_1,1), "% (n=",
  S$beta_realized_roll36$n_windows, "). 전기간 단일 추정은 0.8688(alpha), 최근 12개월 평균은 ",
  round(S$beta_realized_roll36$last12_mean,4), ", 2023-08~2026-07 일별 창은 0.700. ",
  "★본 항목은 자기적대검증에서 **두 번** 정정됐다. 초안 '현재 beta 는 1 근처'는 일별 창 실측 0.700 에 반증됐고, ",
  "1차 정정 '실측이 더 낮으므로 alpha 논거를 강화한다'는 walk-forward 평균 ",
  round(S$beta_realized_roll36$mean,4), " > 1 에 다시 반증됐다. ",
  "두 정정 모두 **단일 창을 근거로 일반화한 것**이 원인이다. ",
  "정확한 진술: beta 는 창에 따라 0.54~1.48 로 흩어지며 평균은 1 위, 전기간 점추정은 1 아래다. ",
  "따라서 'beta<1 이므로 PORT_t 가 알파를 과소표시한다'는 보정은 창 선택이 부호를 만든다.")
pkg$challenge_flags[[2]]$severity <- "MEDIUM"
pkg$challenge_flags[[2]]$action <- paste0(
  "alpha_vector 는 수정하지 않는다(read-only). 하류가 beta 기반 보정을 적용할 때는 ",
  "walk-forward 분포를 함께 볼 것을 권고한다. 단일 점추정으로 부호를 확정하지 말 것.")

## ── (5) 자기적대검증에 SC-7 추가 (스킬 준수 결손 — ACCEPT) ─────────────────
pkg$self_adversarial_challenge$n_self_concerns <- 7L
pkg$self_adversarial_challenge$concerns[[7]] <- list(
  id = "SC-7",
  concern = "스킬(qvest-risk-style)이 명시한 필수 스트레스 6종 중 KR_Bear 를 빠뜨렸고, Cycle 2 교훈('as-of 단일 단면으로 RF-R1/beta 판정 금지')을 정확히 위반한 채 판정했다.",
  classification = "ACCEPT",
  basis = paste0("인정. 두 결손 모두 실질적 결과를 바꿨다. ",
    "(i) KR_Bear 를 넣자 낙폭 상태 125개월 초과손익 ",
    round(100*KR[scenario=="KR_Bear_ALL", active_cum],1), "%p 가 드러났다 — 글로벌 에피소드 목록만으로는 안 보이던 축이다. ",
    "(ii) walk-forward 로 재판정하니 시장 분산비중이 as-of ", round(S$mkt_var_share$as_of,3),
    " -> 평균 ", round(S$mkt_var_share$mean,3), " 로 올라갔고, 잔차변동성 노출은 부호가 뒤집혔다(",
    round(S$x_RVOL$as_of,3), " -> ", round(S$x_RVOL$mean,3), "). ",
    "as-of 단일단면은 과대평가가 아니라 **과소평가** 방향으로 틀렸다."),
  fix = "risk_summary.walk_forward_validation + stress_test_detail.kr_bear 신설 · RF-R1 판정근거를 walk_forward_mean 으로 교체 · RISK-2 재작성 · walk_forward_risk.parquet 발행")
pkg$self_adversarial_challenge$self_rationalization_scan$note <- paste0(
  pkg$self_adversarial_challenge$self_rationalization_scan$note,
  " SC-7 은 자기비평이 아니라 **스킬 재확인**에서 나왔다 — 자기적대검증 6건이 방법론 내부만 훑고 ",
  "'요구된 항목을 다 했는가'는 묻지 않았다는 뜻이다. 체크리스트 대조를 자기비평의 첫 축으로 둘 것.")
pkg$self_adversarial_challenge$escalation$detail <- paste0(
  "HIGH 발화 1건(RF-R1, 구조적) / PIT 위반 0 / Sigma PD 위반 0(min_eig 5.4e-3 > 0). escalate 조건 미충족. ",
  "SC-7(ACCEPT)은 산출물 결손이었고 사후 보완으로 해소 — 재측정 결과가 판정을 뒤집지 않았다(RF-R1 여전히 발화).")

pkg$risk_summary$stress_test_detail$required_scenarios_checklist <- list(
  source = "qvest-risk-style skill",
  GFC = "OK", EuDebt = "OK", China2015 = "OK", COVID = "OK", RateHike2022 = "OK",
  KR_Bear = "OK (R12 사후 보완)",
  extras = c("Terror_9_11 (coverage 0 -> UNRELIABLE)", "US_China_Trade", "Iran_War",
             "factor shock 7종", "historical replay 59개월"))
pkg$walk_forward_risk_ref <- "stage_artifacts/WT_R20260829_005/walk_forward_risk.parquet"

write_json(pkg, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=10, na="null")
cat(sprintf("[R12] risk_package.json patched (%.1f KB)\n", file.size(file.path(MB,"risk_package.json"))/1024))
source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
invisible(tryCatch(record_package_lineage(task_id=TID, package_type="risk_package",
  method_selected="factor_bwb_d", input_file_paths=c(file.path(MB,"alpha_package.json")),
  windows=list(list(name="skill_gap_repair_walkforward_krbear",
                    from=as.character(min(WF$Date)), to=as.character(max(WF$Date))))),
  error=function(e) message("lineage: ", conditionMessage(e))))
cat("[R12] done\n")
