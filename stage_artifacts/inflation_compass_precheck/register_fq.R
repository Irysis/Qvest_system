## 인플레이션 나침반 — FQ 등재 + owner 잠금 (배분 전 등재 규약)
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
## ID 충돌 방지: 실측 최대 +1
ids <- suppressWarnings(as.integer(sub("^FQ-", "", sapply(E, function(x) if (is.null(x$id)) NA_character_ else x$id))))
next_id <- sprintf("FQ-%03d", max(ids, na.rm=TRUE) + 1L)
cat("[reg] 신규 ID:", next_id, "\n")

E[[length(E)+1]] <- list(
  id = next_id,
  lane = "macro_conditioned_selection",
  title = "인플레이션 나침반 KR — 합성 인플레 지수 x 섹터 민감도 틸트 x 섹터 내 이익성장 선택 (도훈 아이디어)",
  hypothesis = paste(
    "합성 인플레 지수(4성분 동일가중: z(T5YIE-2.0) + z(T5YIE 60d 모멘텀) + z(KR_CPI YoY) + z(Copper YoY),",
    "expanding z, 전 성분 기 캐시)로 섹터 편입비중을 **연속 틸트**하고(w_s ∝ base x exp(lambda x beta_s x infl)),",
    "각 섹터 내에서 이익성장 스코어(C01_SUE·C02_EPS_Chg_1m·M26_Revenue_Mom 중 사전 고정) 상위를 뽑아",
    "최대 25종목을 편입한다. 참조: cssanalytics 'The Inflation Compass Model'(2026-07-27) —",
    "단 논문의 4국면 이산 분할·고정 섹터 매핑·단일 포지션은 채택하지 않는다(아래 wall_check).",
    "★도훈 승인 2026-08-09: 합성 지표 사용."),
  ev_rationale = paste(
    "①인플레/breakeven/T5YIE 축은 hypothesis_index·큐 전수 0건 = 실질 미탐색(양성 대조 통과).",
    "②NP-A(FQ-171) 실측이 종목선택 층의 형태 전제를 정당화 — book 등급 신호의 상단은 중간을 유의하게 이긴다",
    "(pooled +2.61%/yr, NW t +3.31) ⇒ '섹터 내 상위 선택'은 혹(hump) 함정 형태가 아니다.",
    "③M26 은 D10 연초과 +6.550%(t 2.822) 실측 재료."),
  wall_check = paste(
    "★사전 확인 3건이 설계를 논문에서 이탈시켰다:",
    "(1) 4국면 분할 = 구조적 저검정력(국면 25% 시 필요 연 16.31%, 5% 시 32.41% — 2026-08-08 3회 재현 계통)",
    "⇒ 이산 국면 금지, 연속 틸트만.",
    "(2) 업종-레벨 신호는 월수익 분산의 12~22%만 겨냥(FQ-069c2 실측, BSI 는 oracle 천장의 4.8%)",
    "⇒ 섹터 틸트는 보조, 알파 몸통은 섹터 내 종목선택.",
    "(3) 논문 자인 = 1일 집행 지연에 CAGR -480bp ⇒ lag1 스트레스가 1급 반증 조건.",
    "★인접 negative 구별(INV-7): regime-conditional 교차결합 settled-negative(07-05)는 **이산 국면** 교차결합이다.",
    "본 설계는 연속 틸트라 동일 config 아님 — 연속형도 무효면 그것이 더 강한 지식이 된다.",
    "★T5YIE 는 미국 자산 거래가 아니라 조건화 변수(FRED = 헌법 허용 인프라). 크로스마켓 금지 저촉 없음.",
    "★25종 제약 하 섹터 27종 ⇒ 평균 0.93종목/섹터 — 부드러운 섹터 비중은 표현 불가, 유효 섹터 5~10.",
    "고정 축이며 완화 제안 없음."),
  data_gate = "없음 — 전 성분 기 캐시(.cache/fred_macro.parquet T5YIE 2003-01~ · ecos KR_CPI · Copper · rawdata Sector 27종)",
  design_doc = "stage_artifacts/inflation_compass_precheck/design_v0.md (사전등록 골격·반증 F1~F4·판정 규칙 포함)",
  status = "in_flight",
  owner = "Q-Lead session cee0bdd0 (2026-08-09)",
  in_flight_since = "2026-08-09",
  in_flight_note = paste(
    "서브에이전트 배분 예정. 측정 순서 = ①검정력 바 ②사전등록 고정 ③층 분해 F3",
    "(틸트 단독 vs 종목선택 단독 vs 결합 — 틸트 무효 ∧ 결합 유효면 이득은 종목선택 귀속) ④결합.",
    "기간 = 2003~(T5YIE 시작 제약, 헌법 고정창 2005~ 와 다름 명시)."),
  next_action = "설계문서의 사전등록 골격대로 착수. lambda ∈ {0, 0.5, 1.0} 소수 고정 전량 보고(argmax 금지).",
  registered = "2026-08-09",
  registered_by = "Q-Lead session cee0bdd0 (도훈 아이디어 + 합성 지표 승인)"
)
q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[reg]", next_id, "등재 + 잠금 완료\n")
