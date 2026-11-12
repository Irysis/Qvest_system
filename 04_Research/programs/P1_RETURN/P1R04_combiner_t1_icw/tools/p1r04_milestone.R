# P1R04 이정표 1통(prep_send · 1계층 표제 · 푸시) — 측정 셸(tools/p1r04_measure.sh)과 세션(등록 직후)이 부른다. P1R03 이정표를 본떴다.
#   인자: <단계 키 registered | measured | stale | input_changed | failed> <운영 상태 줄>...
#   문체(도훈 11-13 "프로페셔널한 퀀트톤 · 어떤 아이디어로 전략을 강화 중인지 드러나게"):
#     가설 → 검증 설계 → 판정 기준 → 강화 아이디어를 먼저 쓰고, 운영 상태는 맨 뒤에 짧게. 표준 퀀트 용어(내부 약어 금지).
#   measured 면 판정 단일 출처(results/verdict.json)의 기계 요약을 '해석 전'으로 싣는다. 정식 보고(독립 감사 · 철학 판독 포함)는 세션이 낸다.
args <- commandArgs(trailingOnly = TRUE)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
key <- args[1] %||% "?"; ops <- as.list(args[-1])
RD <- "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"

stage <- switch(key, registered = "사전등록 완료 · 측정 대기", measured = "측정 · 평가 완료(해석 전)",
                stale = "입력 자료 지연 — 측정 대기", input_changed = "측정 중 입력 판본 변경 — 재측정",
                failed = "측정 실패 — 원인 확인", key)
nxt <- switch(key,
  registered = "자료 신선(직전 거래일까지) 확인 뒤 15 엔진 측정 → 사전등록 규칙으로 판정 → 독립 감사(판단 · 투자철학) → 정식 보고",
  measured = "판정 해석(같은 계보 등가중 판과 짝 비교) → 독립 감사(판단 · 투자철학) → 정식 보고 → 사전등록 '읽는 법'대로 다음 결합기 단계",
  stale = "자료 복구 뒤 측정 · 판정",
  input_changed = "입력(팩터 결합용 뷰 · IC 원장) 판본이 바뀐 원인을 확인한 뒤 15 엔진 재측정(기저 신호 캐시까지 비운다)",
  failed = "측정 로그로 원인 확인 → 수리 → 재측정", "세션 확인")

idea <- paste(
  "등가중 카테고리 합성(직전 라운드)은 카테고리 안의 약한 · 역방향 팩터가 신호를 희석한다.",
  "이번 라운드는 같은 334개 팩터 · 같은 14개 카테고리를 그대로 두고 결합 가중만 바꾼다 — 각 팩터를 그 시점까지 관측된 정보계수의 정보비율(ICIR, 최근 120개월 · 최소 36개월)로 가중하고,",
  "등록부 기대수익 방향과 반대로 움직여 온 팩터는 뒤집지 않고 가중 0 으로 뺀다(양의 부분만 · 시계열 팩터 모멘텀과 같은 원리).",
  "카테고리 점수 사이는 카테고리 평균 ICIR 로 가중해 카테고리 균형을 유지한다. ICIR 이 모두 같으면 등가중 판과 같은 점수가 되므로, 두 라운드의 차이는 시점별(as-of) 정보계수 정보 하나다.")
design <- list(
  "유니버스 · 기간: 전 종목(관리 · 거래정지 · 불성실공시 · 수정 종가 1,000원 미만 제외) · 2000-01 ~ 자료 끝",
  "구성: 롱온리 · 최대 25종 등가중 · 월말 신호 · 거래비용 15bp · 20일 평균 거래대금 2억 원 이상(직전 라운드와 같다)",
  "엔진 15: 카테고리 내 IC 가중 14 + 카테고리 균형 IC 가중 토탈 1 · 정보계수는 공개 시점(다음 달 말) 이후에만 사용 · 미래참조 검사(절단 불변 + 돌연변이 대조) 통과",
  "판정(사전등록): in-sample 2000~2022 β-통제 알파 t ≥ 2.0 ∧ 상승 포착 ≥ 0.55 · out-of-sample 2023~ 은 보고 전용",
  "다중검정: 계보(카테고리 · 토탈)마다 등가중 1 + IC 가중 1 = 2 시행 — 통과 엔진을 기저로 쓰는 강화 사슬이 두 라운드 30칸을 모두 시행으로 센다")
roadmap <- list(
  "① 횡단면 회귀 결합 — 카테고리 점수 14개에 대한 과거 기울기로 기대수익 적합(상관 구조 반영)",
  "② 상태 조건부 결합 — 위기 · 강세 국면에 따라 카테고리 가중을 바꾸는 시변 결합(as-of 조건부 IC)",
  "③ 상위 꼬리 표적 — 상위 25종 성과를 직접 표적으로 하는 순위 학습",
  "④ 통과 엔진 → 강화 사슬: 방어 오버레이 · 구성(낙폭 제약 아래 복리)")

vl <- NULL
if (key %in% c("measured", "failed", "input_changed")) {
  dl <- tryCatch(format(max(arrow::read_parquet(".cache/RAWDATA.parquet", col_select = "Date")$Date)), error = function(e) "?")
  ops <- c(ops, list(sprintf("자료 끝(RAWDATA 최신일) = %s", dl)))
}
if (identical(key, "measured")) {
  vf <- file.path(RD, "results", "verdict.json")
  if (file.exists(vf)) { V <- tryCatch(rc_json_read(vf), error = function(e) NULL)
    s <- V$summary; if (is.character(s) && length(s)) vl <- paste0("기계 판정(해석 전): ", paste(s, collapse = " · "))
  } else ops <- c(ops, list("판정 파일 없음 — 평가 연쇄 확인 필요"))
}
if (length(ops) < 2L) ops <- c(ops, list("상태 파일 = .cache/scheduler_logs/p1r04_measure_state.txt"))
r <- prep_send(program = "수익 엔진", target = sprintf("P1R04 카테고리 결합기 T1(시점별 IC 가중) 자격 심사 — %s", stage),
               status = list(stage = stage, position = "1계층 수익 엔진(P1) · 자체 사양 엔진 15 · 결합기 사다리 1단", previous = "P1R03 카테고리 등가중 합성 15칸 판정(11-13)"),
               verdict_line = vl, next_step = nxt,
               extra = list(list(heading = "리서치 아이디어", type = "text", body = idea),
                            list(heading = "검증 설계", type = "bullet", items = design),
                            list(heading = "다음 결합기 단계", type = "bullet", items = roadmap),
                            list(heading = "운영 상태", type = "bullet", items = ops)),
               artifact = file.path(RD, "DESIGN.md"), push = TRUE, root = ROOT)
cat(sprintf("[p1r04_milestone] %s ok=%s\n", key, isTRUE((r %||% list())$ok) || identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1")))
