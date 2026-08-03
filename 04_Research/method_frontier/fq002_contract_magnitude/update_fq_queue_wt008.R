# update_fq_queue_wt008.R — FQ-125 판정 반영 + next_probe 큐 등재 (registry staleness 방지)
# ★원칙: 기존 필드 삭제 없음(추가·갱신만). status 전환은 사실 기록 범위 내에서만.
suppressPackageStartupMessages({ library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
setwd(.rt())
P <- "06_Registry/alpha_frontier_queue.json"
file.copy(P, paste0(P, ".bak_wt008"), overwrite = TRUE)
Q <- fromJSON(P, simplifyVector = FALSE)

# queue 배열 위치 탐색 (스키마 형태 가정 금지 — 실제 구조에서 찾는다)
find_list <- function(node, path = character()) {
  if (is.list(node) && is.null(names(node))) {
    if (length(node) && is.list(node[[1]]) && !is.null(node[[1]]$id) &&
        grepl("^FQ-", node[[1]]$id)) return(path)
  }
  if (is.list(node) && !is.null(names(node)))
    for (nm in names(node)) { r <- find_list(node[[nm]], c(path, nm)); if (!is.null(r)) return(r) }
  NULL
}
qpath <- find_list(Q)
if (is.null(qpath)) stop("FQ 배열 미발견 — 스키마 확인 필요")
cat("[fq] 배열 경로:", paste(qpath, collapse = "/"), "\n")
arr <- Reduce(`[[`, qpath, Q)
ids <- vapply(arr, function(e) if (is.null(e$id)) NA_character_ else e$id, character(1))
i125 <- which(ids == "FQ-125")
stopifnot(length(i125) == 1L)

e <- arr[[i125]]
e$status <- "dohoon_decision"
e$owner <- "alpha-research (WT-D20260803_008 1단계 판정 완료 2026-08-03)"
e$stage1_result <- paste(
  "★1단계 interim 게이트 **PASS** (WT-D20260803_008, 2026-08-03).",
  "합산 79 IC월(2019-12~2026-06) 평균 rank-IC +0.05652, t_NW(lag3) **+1.9942** (>=1.5 충족),",
  "ICIR 0.234, 양수월 59.5%. 신규 55개월 단독 평균 IC **+0.04602** (>0 충족, t_NW 1.294).",
  "국면 분해 수행(3번째 조건 충족). 파일럿 parity 정확 재현(mean_ic 0.080559 / t_plain 1.972226).",
  "섭동 120 draws q05 t_NW **+1.7553** (파일럿 1.4405 대비 개선, min +1.674).",
  "★감쇠의 정체 = 벤치 방향이 아니라 **횡단면 저변(mega-cap 주도 여부)**. 파일럿 corr(IC,BM_Ret) -0.2545 는",
  "n=79 에서 **-0.0297 로 소멸**(표본 아티팩트로 정정). 실측 축 corr(IC, mega_spread) = **-0.3459**.",
  "사전관측 t-1 상태 분할: 저변주도 27M IC +0.1445(t_NW 5.17) vs 대형주주도 52M +0.0108(t_NW 0.32),",
  "격차 +0.1337 / 라벨 순열 p=0.0082 / 문턱 스윕 q0.2~0.5 안정 / 신규 구간 단독 재현(+0.1032).",
  "단 국면 축 선택은 **사후(3-way look)** — 확정 아님, NP-1 사전등록 재판정 대상.",
  "사이즈 틸트 대안 기각: 순수 1/Size 평균 IC +0.0151(t_NW 0.63), size-잔차화 후 신호 98.8% 보존(t_NW 2.005),",
  "score~1/Size 단면상관 평균 -0.012.",
  "전이 벽: 무조건 canonical cap-w PORT_t **+0.511**(p 0.61) / EW-uni +1.604 — HARD 2.95 미달 불변.",
  "조건부(저변주도 27M) PORT_t +2.198·net_SR 1.318 이나 월 선택 사후·n=27·turnover 해석불가.",
  sep = " ")
e$boundary_correction_stage2 <- paste(
  "★★잔여 구간 지불 전제 정정: **2008~2018 확장은 현행 파서로 불가**.",
  "이미 크롤된 2017-03~2018-12 체크포인트 1,199행 실측 = OK **29행(2.4%)**, PARSER_ERROR 620, UNZIP_FAIL 527.",
  "큐 data_gate 의 '원문은 2008-01까지 존재'는 **문서 존재**에 대한 참인 진술이나 **파싱 가능성이 아니다**.",
  "존재 / 가용 / 파싱가능 세 층을 구분하지 않으면 지불 오판이 된다.",
  sep = " ")
e$dohoon_decision_pending <- list(
  question = "잔여 구간 크롤 2단계 지불 여부 — ★단 파서 조건부 게이트 선행 권고",
  status_note = "1단계(2019-01~2023-07) 지불·완주·판정 완료 = PASS. 본 항목은 그 다음 결정이다.",
  recommendation = "잔여 구간 지불 **보류** — NP-3(파서 샘플 150 호출) 선행 후 재판단",
  precondition = "2010/2012/2014/2016/2017 각 연도 무작위 30건(총 150 호출, 전액 22,533 대비 0.7%) 파싱 성공률 >= 90%",
  then_stage2_scope = "2015-01~2018-12 (48개월, ~4,000 호출) 우선 — 연속성 확보가 2008 점프보다 통계 가치 높음",
  stage2_gate = "합산 n>=127 에서 t_NW >= 2.0 AND 신규 48개월 mean IC > 0",
  abort = "샘플 성공률 < 90% 이면 파서 수리가 선행 과제 — 크롤 지불 없음",
  registered = "2026-08-03 (WT-D20260803_008)")
e$revival_conditions <- c(
  "NP-1 사전등록 재판정에서 조건부 PORT_t 가 무조건 대비 유의 개선을 재현하면 → 오버레이/필터 lane 승격 검토",
  "NP-2 에서 기관 후속 유입 경로(A6_investor_flow) 가 기각되면 → 국면 의존을 다른 기전으로 재서술 후 재설계",
  "파서 샘플 성공률 >= 90% 확인 시 → 2015-2018 확장으로 n>=127 재측정",
  "mega-cap 집중도가 2024 이전 수준으로 정상화된 국면 6개월 지속 → trailing 24개월 무조건 재측정")
arr[[i125]] <- e

newq <- list(
  list(id = "FQ-138", lane = "non_return",
       title = "★계약수주 국면 조건부 알파 — 사전등록 재판정 (사후 발견의 승격 시도)",
       hypothesis = paste("WT-D20260803_008 실측: 사전관측 가능한 t-1 mega_spread<=0 국면에서 계약 신호 IC +0.1445(t_NW 5.17),",
                          "대형주주도 국면 +0.0108(t_NW 0.32), 격차 +0.1337 (라벨 순열 p=0.0082, 문턱 q0.2~0.5 안정, era 분할 재현).",
                          "★그러나 동월/t-1/trailing3 3-way look 후 선택이라 **사후**다. 사전등록으로 재판정하면 살아남는가."),
       ev_rationale = "본 라운드 최강 신호이며 재크롤 0(패널·그리드 재사용). 확정되면 계약 재료가 오버레이/필터 lane 으로 진입한다.",
       wall_check = "조건부 canonical PORT_t +2.198(n=27) 은 무조건 +0.511 의 4.3배이나 HARD 2.95 미달. 사전등록 라운드는 개선폭 자체를 판정 대상으로.",
       data_gate = "없음 — panelx_A.parquet + gridx_* 재사용",
       owner = "미배정", status = "frontier_open",
       registered = "2026-08-03 alpha-research (WT-D20260803_008 NP-1)",
       precheck_measured = paste("문턱을 단일값(0)으로 쓰지 말 것 — 이미 스윕 실측이 있다: q0.2 격차 +0.128 / q0.3 +0.144 / q0.4 +0.134 /",
                                 "q0.5 +0.101 / q0.6 +0.012 / q0.7 +0.043. 제로컷은 분포의 34분위. q0.6 붕괴가 실재하므로",
                                 "사전등록은 **분위 구간(q0.2~0.5)** 을 명시하고 판정은 분포 q05 로(FQ-109 규약).")),
  list(id = "FQ-139", lane = "non_return",
       title = "계약수주 메커니즘 직접 반증 — 기관 후속 순매수 경로가 실재하는가",
       hypothesis = paste("alpha_package.falsification 1번 항목이 미측정이다. score 상위분위 종목의 t+1~t+3 기관 순매수",
                          "(A6_investor_flow_stock_daily) 가 하위분위 대비 유의하게 증가하지 않으면 mechanism.path('기관 후속 매수로 가격 반영')가",
                          "기각되고, 그러면 국면 의존은 다른 기전(소형주 유동성 사이클 등)으로 재서술해야 한다."),
       ev_rationale = "성과가 아닌 **부수 관측**으로 기전을 시험하는 유일한 항목(성과 동어반복 회피). 저비용 — investor_wide.parquet 재사용.",
       wall_check = "해당 없음(기전 검증 라운드). 결과가 negative 면 가설 재서술로 환류.",
       data_gate = "없음 — .cache/investor_stock/investor_wide.parquet + panelx_A.parquet",
       owner = "미배정", status = "frontier_open",
       registered = "2026-08-03 alpha-research (WT-D20260803_008 NP-2)"),
  list(id = "FQ-140", lane = "measurement_integrity",
       title = "★DART 계약 공시 파서 era 경계 실측 — 잔여 크롤 지불의 전제 확인",
       hypothesis = paste("FQ-125 잔여 구간 지불의 전제는 '2008~2018 원문 파싱 가능'인데, 이미 크롤된 2017-03~2018-12 에서",
                          "OK 29/1199 = **2.4%** (PARSER_ERROR 620 + UNZIP_FAIL 527) 로 실측됐다. 2010/2012/2014/2016/2017 각 30건",
                          "샘플(총 150 호출)로 연도별 파싱 성공률을 재고, >=90% 인 구간만 지불 대상으로 삼는다."),
       ev_rationale = paste("착수 전 사전 확인이 라운드 설계를 바꾼 실측 선례(feedback-precheck-before-round-changes-design 4/4 적중).",
                            "150 호출 = 전액 22,533 의 0.7% 로 ~14,500 호출 지불 결정을 판별한다."),
       wall_check = "해당 없음(데이터 게이트 census). 성공률 미달 시 파서 수리가 선행 과제로 전환된다.",
       data_gate = "DART API 150 호출 (캐시 .cache/dart/contract_docs 존재분 우선 — 재파싱 무료)",
       owner = "미배정", status = "frontier_open",
       registered = "2026-08-03 alpha-research (WT-D20260803_008 NP-3)",
       precheck_measured = "파서 v3 의 실패는 서식이 아니라 인코딩 하드코딩이었다(FQ-125 data_gate 기록). pre-2019 UNZIP_FAIL 527 은 그와 다른 층 — 압축 응답 자체를 못 여는 것이므로 인코딩 수리로 해결되지 않을 수 있다. 샘플 측정 시 UNZIP_FAIL 과 PARSER_ERROR 를 분리 집계할 것.")
)
arr <- c(arr, newq)

assign_at <- function(obj, path, value) {
  if (length(path) == 1L) { obj[[path]] <- value; return(obj) }
  obj[[path[1]]] <- assign_at(obj[[path[1]]], path[-1], value); obj
}
Q <- assign_at(Q, qpath, arr)
write_json(Q, P, pretty = TRUE, auto_unbox = TRUE, null = "null")
chk <- fromJSON(P, simplifyVector = FALSE)
arr2 <- Reduce(`[[`, qpath, chk)
ids2 <- vapply(arr2, function(e) if (is.null(e$id)) NA_character_ else e$id, character(1))
cat(sprintf("[fq] 항목 %d → %d | FQ-125 stage1_result 기록 %s | 신규 %s\n",
            length(ids), length(ids2),
            ifelse(!is.null(arr2[[which(ids2 == "FQ-125")]]$stage1_result), "OK", "FAIL"),
            paste(setdiff(ids2, ids), collapse = ",")))
