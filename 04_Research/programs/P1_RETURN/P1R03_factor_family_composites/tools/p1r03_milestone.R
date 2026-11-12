# P1R03 이정표 1통(prep_send · 1계층 표제 · 푸시) — 측정 셸(p1r03_measure_asof_1110.sh · p1r03_dawn_measure.sh)이 부른다.
#   인자: <단계 키 registered | measured | stale | view_changed | failed> <운영 상태 줄>...
#   문체(도훈 11-13 "프로페셔널한 퀀트톤 · 어떤 아이디어로 전략을 강화 중인지 드러나게"):
#     가설 → 검증 설계 → 판정 기준 → 강화 로드맵을 먼저 쓰고, 운영 상태는 맨 뒤에 짧게 둔다. 표준 퀀트 용어로 쓴다(내부 약어 금지).
#   measured 면 판정 단일 출처(results/verdict.json)의 기계 요약을 '해석 전'으로 싣는다. 정식 보고(독립 감사 · 철학 판독 포함)는 세션이 낸다.
args <- commandArgs(trailingOnly = TRUE)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
key <- args[1] %||% "?"; ops <- as.list(args[-1])
RD <- "04_Research/programs/P1_RETURN/P1R03_factor_family_composites"

stage <- switch(key, status = "진행 상황", registered = "사전등록 완료 · 측정 대기", measured = "측정 · 평가 완료(해석 전)",
                stale = "입력 자료 지연 — 측정 대기", view_changed = "측정 중 입력 판본 변경 — 재측정",
                failed = "측정 실패 — 원인 확인", key)
nxt <- switch(key,
  status = "측정 완료 즉시 판정 해석 · 정식 보고 → 사전등록 읽는 법대로 다음 라운드 착수(설계 준비 중)",
  registered = "측정(자료 11-10 기준) → 사전등록 규칙으로 판정 → 독립 감사(판단 · 투자철학) → 정식 보고",
  measured = "판정 해석 → 독립 감사(판단 · 투자철학) → 정식 보고(차트 포함) → 통과 엔진은 기저 풀에 올려 아래 강화 로드맵 ①부터 한 걸음씩",
  stale = "자료 복구(별도 세션 · 오전 마감) 뒤 측정 · 판정",
  view_changed = "입력 판본이 바뀐 원인을 확인한 뒤 15 엔진 재측정(기저 신호 캐시까지 비운다)",
  failed = "측정 로그로 원인 확인 → 수리 → 재측정", "세션 확인")

idea <- paste(
  "팩터 DB 의 334개 팩터를 경제적 카테고리 14개(퀄리티 · 밸류 · 모멘텀 · 성장 · 발생액 · 레버리지 · 수급 · 컨센서스 · 기술적 · 쏠림 + 저위험 계열 4개 — 방어 · 위험 · 유동성 · 국면)로 묶어 카테고리별로 등가중 합성하면,",
  "표준 롱온리 구성에서도 시장 β 를 통제한 알파와 상승 포착률을 함께 내는가를 검증한다.",
  "논문 복제 레인이 아직 기저 엔진을 공급하지 못해(기저 풀 0) 자체 사양 엔진으로 강화의 출발점을 먼저 확보하는 단계다.")
design <- list(
  "유니버스 · 기간: 전 종목(관리 · 거래정지 · 불성실공시 · 수정 종가 1,000원 미만 제외) · 2000-01 ~ 자료 끝",
  "구성: 롱온리 · 최대 25종 등가중 · 월말 신호 · 거래비용 15bp · 20일 평균 거래대금 2억 원 이상",
  "엔진 15: 카테고리 합성 14 + 토탈(카테고리 점수 평균) 1 · 팩터 방향 = 등록부 기대수익 방향 · 구성원 = 정적 규칙(성과 무참조)",
  "판정(사전등록): in-sample 2000~2022 β-통제 알파 t ≥ 2.0 ∧ 상승 포착률 ≥ 0.55 · out-of-sample 2023~ 은 보고 전용",
  "다중검정: 15 시행(카테고리당 1 · 튜닝 없음) — 통과 엔진을 기저로 쓰는 강화 사슬이 15를 모두 시행으로 센다")
roadmap <- list(
  "① 카테고리 블렌딩 — as-of IC 가중 결합: 등가중 대비 정보비율 개선 여부",
  "② 방어 오버레이 — 시변 노출(현금 비중)로 하락노출 축소: 같은 β 의 현금 사본을 이겨야 인정",
  "③ 비대칭 표적 — 하방 꼬리를 표적으로 한 분포 학습: 평균 예측기와 구분",
  "④ 구성 — 낙폭 제약 아래 복리 극대화(비중 · 집중 · 회전)")

vl <- NULL
## 자료 끝 날짜는 RAWDATA 에서 직접 읽는다(11-13 정정: 측정 자료 끝 = 11-11 · 셸 문구의 '11-10' 은 옛 판독 — 수리 세션 확인)
ops <- lapply(ops, function(x) gsub("자료 11-10 기준", "자료 끝 기준(아래)", x, fixed = TRUE))
if (key %in% c("measured", "failed", "view_changed")) {
  dl <- tryCatch(format(max(arrow::read_parquet(".cache/RAWDATA.parquet", col_select = "Date")$Date)), error = function(e) "?")
  ops <- c(ops, list(sprintf("자료 끝(RAWDATA 최신일) = %s · 빠진 거래일은 판정 창(≤ 2022-12-31) 밖", dl)))
}
if (identical(key, "measured")) {
  vf <- file.path(RD, "results", "verdict.json")
  if (file.exists(vf)) { V <- tryCatch(rc_json_read(vf), error = function(e) NULL)
    s <- V$summary; if (is.character(s) && length(s)) vl <- paste0("기계 판정(해석 전): ", paste(s, collapse = " · "))
  } else ops <- c(ops, list("판정 파일 없음 — 평가 연쇄 확인 필요"))
}
if (length(ops) < 2L) ops <- c(ops, list("상태 파일 = .cache/scheduler_logs/p1r03_dawn_measure_state.txt"))
r <- prep_send(program = "수익 엔진", target = sprintf("P1R03 팩터 카테고리 합성 엔진 자격 심사 — %s", stage),
               status = list(stage = stage, position = "1계층 수익 엔진(P1) · 자체 사양 엔진 15 · 기저 풀 공급", previous = "사전등록 11-13 00:21(독립 점검 3회 · PIT 값 검사 통과)"),
               verdict_line = vl, next_step = nxt,
               extra = list(list(heading = "리서치 아이디어", type = "text", body = idea),
                            list(heading = "검증 설계", type = "bullet", items = design),
                            list(heading = "강화 로드맵(통과 엔진)", type = "bullet", items = roadmap),
                            list(heading = if (identical(key, "status")) "지금 진행 상황" else "운영 상태", type = "bullet", items = ops)),
               artifact = file.path(RD, "DESIGN.md"), push = TRUE, root = ROOT)
cat(sprintf("[p1r03_milestone] %s ok=%s\n", key, isTRUE((r %||% list())$ok) || identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1")))
