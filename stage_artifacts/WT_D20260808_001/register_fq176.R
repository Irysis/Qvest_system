## FQ-176 등재 — 유동성 자(ruler) 이원화: 계약 구현이 헌법 정의와 다르다
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
ids <- suppressWarnings(as.integer(sub("^FQ-", "", sapply(E, function(x) if (is.null(x$id)) NA_character_ else x$id))))
nid <- sprintf("FQ-%03d", max(ids, na.rm=TRUE) + 1L)
E[[length(E)+1]] <- list(
  id = nid,
  lane = "measurement_trust_infra",
  title = "유동성 자 이원화 — 계약 함수가 헌법 정의(20일 평균)와 달리 월말 1일치 거래대금을 쓴다",
  hypothesis = paste(
    "★확정 결함(가설 아님). `02_Infrastructure/ramp/factor_validation.R:46-47` 의 build_monthly_forward_returns() 가",
    "주석('20d ADV at t-1')과 달리 `adv = Vol0 * Close0`(월말 당일 1일치)로 계산한다 — 주석 자신이",
    "'(사용은 단순 Vol0*Close0)' 라고 자백. 헌법(CLAUDE.md·pit.md) 정의 = **20일 평균 거래대금 >= 2e8 (LIQ_THRESHOLD)**.",
    "두 자의 상관 0.929 · 판정 불일치 2.61%. 파급 실측(verification_followup): WT-001 판정 유니버스(eligible_set)",
    "자체가 20일-자로 395행(0.478%) 미달이고, **실제 선별된 top-25 중 224~225 종-월(3.04%)이 2e8 미만**",
    "(92~96개월 분포, 미달 adv20 중앙 1.14e8, 최다 월 2003-03 16종 — 초기 표본 편중).",
    "이 계약 함수는 canonical 측정 다수가 경유하므로 결함이 WT-001 에 국한되지 않는다."),
  ev_rationale = "측정 신뢰 범주(CLAUDE.md 즉시수리 기준 ②). 헌법이 자를 이미 정의하므로 '어느 자인가'는 결정 사항이 아니다 — 구현이 헌법을 따르면 된다. 과거 판정 재실행 여부만 도훈 판단 대상.",
  wall_check = "자본 주장 아님. ★최신월 alpha_vector 류 현행 선별은 두 검사 모두 청정(min 5.50e9) — 위반은 초기 표본(2003년대) 편중. 완화 제안 아님(자를 헌법 정의로 조이는 방향).",
  data_gate = "없음",
  status = "in_flight",
  owner = "Q-Lead session cee0bdd0 (2026-08-09) — 서브에이전트 배분",
  in_flight_since = "2026-08-09",
  next_action = paste(
    "①factor_validation.R 의 adv 를 20일 평균(frollmean(Vol*Close, 20) t-1 기준)으로 교정 + 주석 정합",
    "②위반 주입 테스트(1일치 판본 주입 시 검사 발화) + 양성 대조(교정판 자기일치) — 배터리 등재",
    "③하류 소비자 census: build_monthly_forward_returns 호출부 전수에서 liq 판정 경유 여부 확인",
    "④과거 판정 영향 정량(판정 불일치 2.61% 가 게이트 판정을 뒤집은 사례가 있는지 — 있으면 목록만, 재판정은 도훈)",
    "⑤production 현행 북 보유 스팟체크(20일-자 기준) — 청정 예상이나 실측으로 확정"),
  parent = "FQ-122 verification_followup_20260809 상신 (2026-08-09)",
  registered = "2026-08-09",
  registered_by = "Q-Lead session cee0bdd0"
)
q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[reg]", nid, "등재 + 잠금 완료\n")
