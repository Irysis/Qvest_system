#!/usr/bin/env Rscript
#==============================================================================
# rf_weight_arms.R — B2(비중) 셀을 **카탈로그에서 선정** (도훈 지시 2026-08-30)
#
# ★왜 바꾸나 — 같은 병을 내가 한 번 더 밟았다:
#   `weight_catalog.R`(2026-08-24 신설) 헤더가 이미 진단해 뒀다 —
#   "세 갈래는 계약이 달라서 안 붙은 게 아니라 **다리가 없어서** 안 붙었다.
#    R1 lean 23종 · R2 QEPM 14종 · R3 어댑터. 7개월간 R2 실호출 1건. 이유는 계약 충돌이 아니라
#    **아무도 한 줄을 안 썼기 때문**이다."
#   그런데 2026-08-30 무인 격자를 짜면서 나는 **카탈로그를 안 쓰고 5종을 새로 구현**했다.
#   등록 52종 중 5종만 쓴 셈이고, 안 건드린 축이 tail_aware·entropy·risk_parity·optimizer 전부다.
#   ★그리고 B1 계열이 낙폭 55~62%에 갇혀 있었는데 **꼬리·엔트로피 계열이 정확히 그 축을 겨눈다.**
#
# 이 파일이 하는 일: 카탈로그에서 arm 을 뽑아 **계열 다양성**을 강제하며 B2 5칸을 고른다.
#   판단이 아니라 규칙이다 — probe_ok 통과분에서 계열당 1개씩, 미측정 우선.
#
# 사용: rf_pick_weight_arms(n = 5) → list(cells = [...])  (격자 B2 cells 형식)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFW_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

#' 카탈로그에서 B2 비중 arm n개 선정
#' @param n 뽑을 개수 (격자 B2 칸 수)
#' @param exclude 이미 측정한 label (중복 회피)
jlog_wa <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "weight_arms"), list(...))
  try(cat(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null"), "
", sep = "",
          file = file.path(.RFW_ROOT, ".cache/reinforce_auto_log.jsonl"), append = TRUE), silent = TRUE)
}

rf_pick_weight_arms <- function(n = 5L, exclude = character(0)) {
  suppressMessages(source(file.path(.RFW_ROOT, "02_Infrastructure/portfolio/weight_catalog.R")))
  A <- tryCatch(as.data.table(weight_catalog_arms()), error = function(e) NULL)
  if (is.null(A) || !nrow(A)) return(NULL)

  # ① 실행 가능한 것만 — probe 가 실패한 arm 은 셀이 통째로 죽는다
  if ("probe_ok" %in% names(A)) A <- A[probe_ok %in% c(TRUE, NA)]
  if ("status" %in% names(A))   A <- A[!status %in% c("retracted", "withdrawn", "failed")]
  A <- A[!(label %in% exclude)]
  if (!nrow(A)) return(NULL)

  # ② EW 는 기준선이라 격자에 넣지 않는다(B1 이 이미 EW 다)
  A <- A[!label %in% c("equal", "ew", "equal_weight")]

  # ③ ★계열 다양성 강제 — 한 계열에서 여러 개 뽑으면 같은 축을 반복 측정한다.
  #    2026-08-30 실측 근거: 내가 고른 5종 중 3종이 score_blend 계열이었고
  #    셋 다 EW 대비 열화하는 같은 결론을 냈다(1.441/1.411/1.396). 정보량 중복이다.
  setorderv(A, c("family", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  picked <- A[, .SD[1L], by = family]              # 계열당 1개
  # 낙폭 축을 겨누는 계열을 앞세운다 — B1 이 MDD 55~62%에 갇힌 것이 실측 구속축이다
  prio <- c("tail_aware" = 1, "entropy" = 2, "risk_parity" = 3, "risk_based" = 4,
            "optimizer" = 5, "classical" = 6, "score_blend" = 7)
  picked[, .prio := prio[family] %||% 9]
  picked[is.na(.prio), .prio := 9]
  ## ★미측정 계열 우선 — 이 파일 헤더가 이미 "계열당 1개씩, **미측정 우선**" 이라 적어 뒀는데
  ##   코드는 고정 prio 로만 정렬해 그 약속을 안 지켰다. 실측 2026-09-05: 전 이력 418 셀 중
  ##   generated_shrinkage_lift(Ledoit-Wolf 등 9종) 측정 0건 — 표에 없는 계열이라 항상 prio 9 로
  ##   밀려 11계열 중 8위였고, 명시된 7계열이 5칸을 다 채워 **원리상 도달 불가**였다.
  ##   같은 날 B2 가 "공분산 추정오차가 비중을 왜곡한다"(minvar·hrp 열위)를 실측했는데,
  ##   그 처방인 shrinkage 가 한 번도 안 걸린 상태였다.
  ##   ★prio 표는 건드리지 않는다 — 낙폭 축 우선이라는 연구 판단은 그대로 두고, **한 번도 안 잰
  ##     계열을 한 바퀴 먼저** 돌린다. 측정되면 다음부터는 원래 prio 순서로 돌아간다(자기제한적).
  ## ★"측정됨" 은 **등급이 난 칸**이다 — spec 파일 존재로 세면 안 된다.
  ##   실측 2026-09-05: gen:lean_score_tilt__shr_lw_nls 는 spec 이 있지만 그 칸은 "카탈로그 arm 부재" 로
  ##   죽어 essence 가 없다. spec 기준으로 세면 한 번도 안 잰 계열이 "측정됨" 으로 읽힌다
  ##   (이 저장소가 반복해 적은 다운로드≠적재 계열). 원장의 essence 있는 attempt 만 센다.
  .measured_fams <- tryCatch({
    L <- jsonlite::fromJSON(file.path(.RFW_ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
    sp <- unlist(lapply(L$entries %||% list(), function(e)
      unlist(lapply(e$attempts %||% list(), function(a) {
        es <- a$essence
        if (is.null(es) || !is.finite(suppressWarnings(as.numeric(es$port_t %||% NA)))) return(NULL)
        as.character(es$spec %||% "")
      }))))
    sp <- unique(sp[nzchar(sp)])
    ids <- unlist(lapply(sp, function(f) {
      if (!file.exists(f)) return(NULL)
      d <- tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(d)) return(NULL)
      as.character((d$weighting %||% list())$catalog_id %||% "")
    }))
    ids <- ids[nzchar(ids)]
    unique(A[catalog_id %in% ids, family])
  }, error = function(e) character(0))
  picked[, .unmeasured := as.integer(!(family %in% .measured_fams))]
  if (any(picked$.unmeasured == 1L))
    jlog_wa("family_unmeasured_first",
            fams = paste(picked[.unmeasured == 1L, family], collapse = ","),
            note = "한 번도 안 잰 계열을 앞세운다(헤더 규약 이행) — 측정되면 원래 prio 로 복귀")
  ## ★전부 미측정 우선으로 밀면 역효과다 — 미측정 계열이 8개라 5칸을 통째로 채워
  ##   오늘 실제로 이긴 위험 계열(cvar 2.526 등)이 B2 에서 사라진다. 그래서 **슬롯을 예약**한다:
  ##   prio 순으로 (n - k) 칸을 채우고, 남은 k 칸을 한 번도 안 잰 계열에 준다(k = 미측정이 있을 때만 2).
  ##   착취(prio)와 탐색(미측정)을 한 블록 안에서 나눈다 — 어느 쪽도 구조적으로 배제되지 않는다.
  setorderv(picked, c(".prio", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  .k <- if (any(picked$.unmeasured == 1L)) min(2L, sum(picked$.unmeasured == 1L)) else 0L
  .k <- min(.k, max(0L, n - 1L))          # prio 칸을 최소 1개는 남긴다
  .exploit <- head(picked[.unmeasured == 0L], max(0L, n - .k))
  .explore <- head(picked[.unmeasured == 1L], .k)
  picked <- head(rbind(.exploit, .explore), n)
  if (nrow(.explore))
    jlog_wa("family_explore_slots", k = nrow(.explore),
            fams = paste(.explore$family, collapse = ","),
            note = "미측정 계열 탐색 슬롯 — 측정되면 다음부터 prio 순서로 복귀")
  if (!nrow(picked)) return(NULL)

  cells <- lapply(seq_len(nrow(picked)), function(i) {
    r <- picked[i]
    list(code = sprintf("B2_%d", 5L + i),
         label = sprintf("%s(%s)", r$label, r$family),
         weighting = list(kind = "catalog", catalog_id = r$catalog_id, label = r$label),
         note = sprintf("카탈로그 선정 — 계열 %s · 출처 %s. 격자가 재구현하지 않고 등록부를 소비한다.",
                        r$family, r$origin %||% "?"),
         root_paper = list(title = sprintf("weight_catalog: %s", r$catalog_id),
                           url = "https://github.com/qvest/weight_catalog"))
  })
  list(cells = cells, n_available = nrow(A), families = sort(unique(A$family)))
}
