# P1R04 이정표 1통(prep_send · 1계층 표제 · 푸시) — 측정 셸(tools/p1r04_measure.sh)과 세션(등록 직후)이 부른다. P1R03 이정표를 본떴다.
#   인자: <단계 키 registered | measured | stale | input_changed | failed> <운영 상태 줄>...
#   문체(도훈 11-13 "프로페셔널한 퀀트톤 · 어떤 아이디어로 전략을 강화 중인지 드러나게"):
#     가설 → 검증 설계 → 판정 기준 → 강화 아이디어를 먼저 쓰고, 운영 상태는 맨 뒤에 짧게. 표준 퀀트 용어(내부 약어 금지).
#   measured 면 IS 판정 파일 두 개(results/evaluation_visible.json · results/pair_reading_visible.json)의 기계 요약을 '해석 전'으로 싣는다.
#     자격은 역할로 나눠 쓴다 — IC 가중 엔진(변형 15) · 같은 날 재측정한 등가중 기준(15 · 짝 기준 보고 열) — 코어 v3 요약은 역할을 안 가린다(격리 점검 v2 R-5).
#     OOS 수치 · 차트 · 독립 감사(판단 · 투자철학)는 세션의 정식 보고가 싣는다.
args <- commandArgs(trailingOnly = TRUE)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
key <- args[1] %||% "?"; ops <- as.list(args[-1])
RD <- "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"

stage <- switch(key, registered = "사전등록 완료 · 측정 대기", measured = "측정 · 평가 완료(해석 전)",
                stale = "입력 자료 지연 — 측정 대기", input_changed = "측정 중 입력 데이터 변경 — 재측정",
                failed = "측정 실패 — 원인 확인", key)
nxt <- switch(key,
  registered = "데이터가 직전 거래일까지 갱신된 것을 확인한 뒤 30개 측정 → 사전등록 규칙으로 판정 → 독립 감사(판단 · 투자철학) → 정식 보고",
  measured = "판정 해석(등가중 기준과 짝 비교) → 독립 감사(판단 · 투자철학) → 정식 보고(차트) → 사전등록 해석 규칙대로 다음 결합기 단계",
  stale = "자료 복구 뒤 측정 · 판정",
  input_changed = "입력 데이터(팩터 점수 · 정보계수 이력)가 바뀐 원인을 확인한 뒤 30개 재측정(신호 캐시까지 비운다)",
  failed = "측정 로그로 원인 확인 → 수리 → 재측정", "세션 확인")

idea <- paste(
  "직전 라운드(카테고리 등가중 합성 15 엔진)에서 8개가 수익 엔진 자격을 얻었지만, 등가중은 카테고리 안의 약한 · 역방향 팩터가 신호를 희석한다(수급 · 기술적 카테고리는 IS 알파가 음수).",
  "이번 라운드는 같은 334개 팩터 · 같은 14개 카테고리 · 같은 포트폴리오 구성을 그대로 두고 결합 가중만 바꾼다 — 각 팩터를 그 시점까지 관측된 정보계수의 정보비율(ICIR · 최근 120개월 · 최소 36개월)로 가중하고,",
  "등록부 기대수익 방향과 반대로 움직여 온 팩터는 뒤집지 않고 가중 0 으로 뺀다(시계열 팩터 모멘텀과 같은 원리). 카테고리 사이는 카테고리 평균 ICIR 로 가중해 균형을 유지한다.",
  "정보계수 이력이 36개월 이상이고 모두 같으면 등가중 결합과 같은 점수가 되므로, 두 결합의 차이는 시점별 정보계수 가중 하나다(이력 36개월 미만 팩터 = 가중 0 · 카테고리 전체가 가중 0 이면 그 달은 등가중 점수).")
design <- list(
  "유니버스 · 기간: 전 종목(관리 · 거래정지 · 불성실공시 · 수정 종가 1,000원 미만 제외) · 2000-01 ~ 자료 끝",
  "구성: 롱온리 · 최대 25종 등가중 · 월말 리밸런싱 · 거래비용 15bp · 20일 평균 거래대금 2억 원 이상(직전 라운드와 같다)",
  "엔진 15(IC 가중) + 같은 날 다시 잰 등가중 기준 15 — 같은 데이터 버전에서 짝 비교 · 정보계수는 공개 시점(다음 달 말) 이후에만 사용 · 미래참조 검사(절단 불변 + 돌연변이 대조) 통과",
  "판정(사전등록): 엔진 자격 = IS(신호 이력이 보유 기간의 두 배 이상 쌓인 첫 달 ~ 2022-12) β-통제 알파 t ≥ 2.0 ∧ 상승 포착률 ≥ 0.55 · OOS(2023-01 ~)는 보고 전용",
  "결합 개선 판정: 짝마다 월 수익 차(IC 가중 − 등가중)의 β-통제 알파 t(IS) ≥ 2.0 인 짝이 2개 이상 또는 토탈 짝 통과 — 단 상승 포착률이 기준의 80% 아래로 떨어지거나 하락노출이 나빠지거나 소형주 쪽 이동(크기 성분 ↑ · 선택 성분 ↓)이면 개선으로 세지 않는다",
  "다중검정: 카테고리마다 등가중 1 + IC 가중 1 = 2 시행 — 이 엔진들을 기저로 쓰는 강화 사슬은 두 라운드의 측정을 모두 시행으로 센다")
roadmap <- list(
  "① 횡단면 회귀 결합 — 카테고리 점수 14개에 대한 과거 기울기로 기대수익 적합(카테고리 사이 상관 반영)",
  "② 상태 조건부 결합 — 위기 · 강세 국면에 따라 카테고리 가중을 바꾸는 시변 결합(시점별 조건부 정보계수)",
  "③ 상위 꼬리 표적 — 상위 25종 성과를 직접 표적으로 하는 순위 학습",
  "④ 자격 엔진 → 강화 사슬: 방어 오버레이 · 구성(낙폭 제약 아래 복리) — 첫 사슬은 직전 라운드 자격 엔진(저위험 보류 제외)으로 시작")

vl <- NULL
if (key %in% c("measured", "failed", "input_changed")) {
  dl <- tryCatch(format(max(arrow::read_parquet(".cache/RAWDATA.parquet", col_select = "Date")$Date)), error = function(e) "?")
  ops <- c(ops, list(sprintf("자료 끝(RAWDATA 최신일) = %s", dl)))
}
if (identical(key, "measured")) {
  CAT <- c(ACCR = "발생액", CONS = "컨센서스", CROW = "쏠림", DEFE = "방어", GROW = "성장", INVE = "수급", LEVE = "레버리지", LIQU = "유동성",
           MOME = "모멘텀", QUAL = "퀄리티", REGI = "국면", RISK = "위험", TECH = "기술적", VALU = "밸류", TOTAL = "토탈")   # P1R03 차트와 같은 표시 이름
  nm <- function(code) { k <- sub("^P1R04_[IF]?", "", sub("_(C0|R0)$", "", code)); unname(ifelse(k %in% names(CAT), CAT[k], k)) }
  S <- tryCatch(rc_json_read(file.path(RD, "round_spec.json")), error = function(e) NULL)
  role <- setNames(vapply(S$cells, function(c) as.character(c$role %||% "?"), ""), vapply(S$cells, function(c) as.character(c$code), ""))
  V <- tryCatch(rc_json_read(file.path(RD, "results", "evaluation_visible.json")), error = function(e) NULL)
  if (!is.null(V) && length(V$table)) {
    cd <- vapply(V$table, function(r) as.character(r$code %||% ""), ""); qq <- vapply(V$table, function(r) isTRUE(r$qualify), TRUE)
    ok <- vapply(V$table, function(r) identical(r$status, "evaluated"), TRUE)
    one <- function(rl, lab) { i <- unname(role[cd]) %in% rl
      sprintf("%s 자격 %d/%d(평가 %d)%s", lab, sum(qq[i]), sum(i), sum(ok[i]), if (any(qq[i])) paste0(" — ", paste(nm(cd[i & qq]), collapse = " · ")) else "") }
    vl <- paste0("기계 판정(해석 전 · IS): ", one("variant", "IC 가중 엔진"), " / ", one("reference", "등가중 기준(같은 날 재측정)"), " · 직전 라운드 측정의 등가중 자격 8")
  } else ops <- c(ops, list("IS 판정 파일 없음 — 평가 연쇄 확인 필요"))
  PR <- tryCatch(rc_json_read(file.path(RD, "results", "pair_reading_visible.json")), error = function(e) NULL)
  if (!is.null(PR)) {
    vv <- switch(as.character(PR$verdict %||% "?"), support = "지지(결합 개선)", falsified = "반증(개선 없음)", untested = "미시험(측정 안 된 짝 있음)", "판독 불가")
    tb <- PR$table; gap <- if (length(tb)) sum(vapply(tb, function(r) identical(r$status, "evaluated") &&
      !all(is.finite(suppressWarnings(as.numeric(c(r$d_t_vis %||% NA, r$uc_t1 %||% NA, r$uc_t0 %||% NA))))), TRUE)) else 0L
    nt <- PR$n_tag %||% list()
    pl <- sprintf("결합 개선 판정(해석 전 · IS · 사전등록 규칙): %s — IC 가중 − 등가중 월 수익 차의 β-통제 알파 t ≥ %.1f 인 짝 %d/%d · 상승 포착률 손실(%d) · 위기 하락노출 악화(%d) · 소형주 쪽 이동(%d) 제외 뒤 %d · 토탈 짝 %s · t > 0 인 짝 %d/%d%s",
                  vv, as.numeric(PR$threshold %||% NA), as.integer(PR$n_pass_t %||% 0L), as.integer(PR$n_lineages %||% 0L),
                  as.integer(nt$strength_loss %||% 0L), as.integer(nt$crisis_worse %||% 0L), as.integer(nt$size_tilt %||% 0L),
                  as.integer(PR$n_counted %||% 0L), if (isTRUE(PR$total_counted)) "통과" else "미통과", as.integer(PR$n_positive %||% 0L),
                  as.integer(PR$n_lineages %||% 0L),
                  if (gap > 0L) sprintf(" · 값이 빈 짝 %d — 등록 전 정정 기록(빈 짝 = 미시험)대로 세션이 다시 읽는다", gap) else "")
    vl <- if (is.null(vl)) pl else paste(vl, pl, sep = " / ")
  } else ops <- c(ops, list("결합 개선 판정 파일 없음 — 세션 확인"))
}
if (length(ops) < 2L) ops <- c(ops, list("상태 파일 = .cache/scheduler_logs/p1r04_measure_state.txt"))
r <- prep_send(program = "수익 엔진", target = sprintf("P1R04 카테고리 결합기 T1(시점별 IC 가중) 자격 심사 — %s", stage),
               status = list(stage = stage, position = "1계층 수익 엔진(P1) · 자체 설계 엔진 15 + 등가중 기준 15 · 결합기 단계 1", previous = "P1R03 카테고리 등가중 합성 15 엔진 판정(11-13 · 자격 8)"),
               verdict_line = vl, next_step = nxt,
               extra = list(list(heading = "리서치 아이디어", type = "text", body = idea),
                            list(heading = "검증 설계", type = "bullet", items = design),
                            list(heading = "다음 결합기 단계", type = "bullet", items = roadmap),
                            list(heading = "운영 상태", type = "bullet", items = ops)),
               artifact = file.path(RD, "DESIGN.md"), push = TRUE, root = ROOT)
cat(sprintf("[p1r04_milestone] %s ok=%s\n", key, isTRUE((r %||% list())$ok) || identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1")))
