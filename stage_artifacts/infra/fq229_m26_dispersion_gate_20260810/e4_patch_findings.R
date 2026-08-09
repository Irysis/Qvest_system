## FQ-229 (E4) — findings.json 에 e3 자기정정 반영 (np1_sizing 결론 방향 + 억제변수 재산출)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(gsub("\\\\", "/", ROOT))
OUT <- file.path(getwd(), "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) cat(sprintf(paste0("[e4] ", fmt, "\n"), ...))
F <- fromJSON(file.path(OUT, "fq229_findings.json"), simplifyVector = FALSE)
E3 <- readRDS(file.path(OUT, "e3_results.rds"))

F$np1_sizing$verdict <- paste0(
  "★자기정정: 최초 가설('감쇠 = 분산 축소')은 실측으로 기각. 분산은 현대에 **증가**했다(비 1.057)이므로 ",
  "분산은 감쇠를 설명하지 않는다(설명분 −9.0%). 대신 **억제변수**로 작동한다.")
F$suppressor_recomputation <- list(
  source = "FQ-225 nested 표(disp_t 통제 시 시간계수 잔존율 1.963)를 본 라운드에서 직접 재산출",
  trend_uncontrolled = list(c_tau = E3$unctrl$est, se = E3$unctrl$se, t = E3$unctrl$t),
  trend_disp_controlled = list(c_tau = E3$ctrl$est, se = E3$ctrl$se, t = E3$ctrl$t),
  suppression_multiple = as.numeric(E3$ctrl$est / E3$unctrl$est),
  required_months_uncontrolled = E3$n_req_unctrl,
  required_months_disp_controlled = E3$n_req_ctrl,
  required_months_disp_controlled_power80 = E3$n_req_ctrl_80,
  fq225_reference_months = 501.784053684996,
  horizon_reduction_pct = 100*(1 - E3$n_req_ctrl/E3$n_req_unctrl),
  caveat = paste0("분산통제 추세도 |t| ", sprintf("%.3f", abs(E3$ctrl$t)),
                  " < 2.0 — **지평 단축이지 판정 역전이 아니다**. 필요표본은 관측 효과 지속 가정(FQ-225 A4 동일 규약). ",
                  "잔존율 1.963 셀은 FQ-225 가 A1 미검출로 N/A 처리한 미등록 관측 — 사전등록 없이 판정 인용 금지."),
  routed_to = "FQ-230")
F$injection_false_positive_averted <- list(
  what_happened = "c2 위반 주입이 p 0.016~0.048 로 나와 스크립트가 '개선이 분산 연결에 귀속'을 출력했다",
  why_wrong = "귀무 중앙이 음수 — 월별 가중을 임의로 흔드는 것 자체가 해롭다. 높은 백분위가 '덜 해롭다'를 뜻할 수 있다",
  decisive_check = "무게이트(Δ=0)의 귀무 백분위 = G1 91.6% · G4 80.4%",
  corrected_reading = "분산 연결의 순증 백분위는 +5.6%p(G1) / +18.0%p(G4). 구속력 있는 무게이트 대비 paired t 는 +0.117 / +1.013 로 문턱 2.0 미달. 확립된 것은 '임의 가중보다 덜 해롭다'이지 '무게이트보다 낫다'가 아니다",
  note = "c2 자동 판정 문구는 c3 판정으로 대체한다")
F$next_probes <- list(
  list(id = "FQ-230", title = "분산 통제 하 M26 시간추세 — 억제변수 재산출로 FQ-225 판정 지평 502→345개월",
       why = "신규 데이터 없이 사양 변경만으로 지평 31% 단축. 단 |t| 1.485 로 현 표본 판정 아님"),
  list(id = "FQ-231", title = "스칼라 시계열 예측자의 소비면 라우팅 규칙 등재",
       why = "단일 팩터 게이팅 = 랭킹 불변 no-op(|Δ|=0.00e+00) 실측 확정. 국면라벨·vol·crowding 이 같은 벽 재발견하는 것 차단"),
  list(id = "FQ-232", title = "canonical_screen_bt 헌법 유동성 자 복원 (adv1_sameday_DEGRADED)",
       why = "이 경로 PORT_t 절대수준(FQ-161 +1.544 포함)이 헌법 자 기준이 아니다 — 측정 신뢰 축"),
  list(id = "(미등재)", title = "lag 형태만 바꾸는 재시도",
       why = "e1 precheck 로 **등재하지 않음** — ma3/ma6/ma12 전부 80% 검정력 비율 0.38~0.45, 최대가 lag1 의 0.702"))
write_json(F, file.path(OUT, "fq229_findings.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("patch 완료 (%d bytes) · 최상위 키 %d개", file.info(file.path(OUT, "fq229_findings.json"))$size, length(F))
chk <- fromJSON(file.path(OUT, "fq229_findings.json"), simplifyVector = FALSE)
say("★재읽기: suppressor_recomputation 존재 %s · next_probes %d건",
    !is.null(chk$suppressor_recomputation), length(chk$next_probes))
