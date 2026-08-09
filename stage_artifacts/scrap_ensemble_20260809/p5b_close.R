#!/usr/bin/env Rscript
# p5b_close.R — NP-2b 결과 FQ 반영 + 텔레그램 (아크 수렴 보고)
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")

source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-174"); stopifnot(length(i) == 1)
Q$entries[[i]]$status <- "arc_converged_all_faces_swept_20260809"
Q$entries[[i]]$np2b_result_20260809 <- paste0(
  "NP-2b 실측 완료(p5_np2b, 사전등록 = 스크립트 헤더): 연속 beta-틸트의 알파 풀 이식 = ",
  "**CONFIG_SCOPED — 전이 불성립**. FR_001 우량 12 풀(base EW: CAGR 15.88% SR 1.207 MDD 21.7% ",
  "Calmar 0.731 PORT_t 1.419)에서 3 arm 전부 실패 — inv-beta² 는 ΔMDD +0.3%p(무개선, 유의 바 1.77%p 미달)에 ",
  "Calmar 0.731→0.661 악화·PORT_t 1.42→0.95 훼손. 기전: 우량 풀은 이미 포트 beta 0.493·MDD 21.7% 로 ",
  "낮고 beta 산포가 좁아 틸트의 재료 자체가 없음 — 틸트는 알파 가중만 희석. ",
  "★아크 수렴 진술: 폐지 풀의 수확 가능 구조는 **beta 하나뿐**이었다. '작동'한 소비면 전부가 위장된 ",
  "beta 수확(국면 타이밍 = beta / 연속 비중 MDD 절감 = beta 산포 수확 / 위생 필터의 MDD 악화 = 저beta 실패작 제거)이고, ",
  "유일한 절대-알파 경로(선택)는 재료 천장(2.04 < 2.95)에 막혔다. 연속 비중 레버는 'beta 산포가 넓고 ",
  "알파 구조가 없는 풀'에서만 유효한 config-scoped 능력으로 한정."
)
Q$entries[[i]]$next_action <- paste0(
  "[프론티어 잔존 2 + 부활 조건] ①재료 교체(NP-3): 비-수익 원천 모듈이 module_catalog 에 유입되면 ",
  "천장 재산정 — 그때 본 아크의 측정 하네스(dedup·천장·소비면 순회) 전체 재사용 가능. ",
  "②국면 라벨 교체: 사전 관측 가능 지표로 P(상태|상태_t-1) 가 base rate 를 유의하게 넘는 라벨 확보 시 ",
  "상태-조건부 lane 재개(regime-engine Track1 소관 — FR 모드 밖 별도 라운드). ",
  "[부활 신호] beta 산포 넓고 알파 없는 신규 풀 등장 시 연속 beta-틸트(NP-2 능력) 즉시 적용 가능. ",
  "[이관 확정] beta 실측 3건 → WT-D20260809_002 (노출 스케일 층)."
)
res <- write_frontier_queue(Q)
cat("[fq174-np2b] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(OUT, "charts")
p1 <- tg_chart_sweep(
  labels = c("혼합 풀 99개 (알파 없음)", "우량 풀 12개 (알파 있음)"),
  values = c(8.9, -0.3),
  out_dir = CH, title = "같은 비중 기법, 두 풀 — 낙폭 절감이 전이되지 않는다",
  value_label = "최대낙폭 개선 (%p, 클수록 좋음)", hline = 1.77, hline_label = "우량 풀 유의 바 1.77%p",
  highlight = "우량 풀 12개 (알파 있음)", filename = "np2b_transfer.png")
p2 <- tg_chart_sweep(
  labels = c("민감도 반비례 제곱", "민감도 반비례", "변동성 반비례", "동일가중 (기준)"),
  values = c(0.951, 1.141, 1.241, 1.419),
  out_dir = CH, title = "우량 풀에서는 틸트가 초과수익 확신도만 깎는다",
  value_label = "다중검정 t값 (벤치마크 대비)", hline = 2.95, hline_label = "자본 문턱 2.95",
  highlight = "동일가중 (기준)", filename = "np2b_portt.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "폐지줍기 아크 수렴 — 그 풀에서 캘 수 있는 것은 시장 민감도뿐이었습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "낙폭 절감 기법을 우량 풀에 이식하니 무효 — 폐지 풀의 유일한 구조가 시장 민감도임이 확정됐습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "이식: 혼합 풀에서 낙폭을 8.9%p 깎았던 비중 기법을 우량 풀에 옮겼습니다",
           "결과: 낙폭 개선 0 — 우량 풀은 이미 민감도가 낮아 깎을 재료가 없습니다",
           "대가: 초과수익 확신도만 1.42 에서 0.95 로 깎였습니다",
           "정리: 폐지 풀에서 통한 방법들은 전부 민감도를 캐고 있었던 것입니다",
           "의미: 진짜 초과수익 경로는 재료 천장에 막혀 있음이 재확인됐습니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "혼합풀"   = "틸트 낙폭 -8.9%p (유의) — 민감도 산포가 재료",
           "우량풀"   = "틸트 낙폭 +0.3%p (무효, 유의 바 1.77%p)",
           "확신도"   = "우량 풀 1.419 → 틸트 후 0.951 (훼손)",
           "우량기준" = "동일가중만으로 샤프 1.207 · 낙폭 21.7% · 칼마 0.731",
           "판정"     = "전이 불성립 — 능력은 조건부로만 보존")),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "낙폭 절감 능력은 '민감도 산포 넓고 알파 없는 풀' 한정 조건부입니다",
           "우량 풀은 동일가중이 모든 틸트를 이겼습니다 — 단순함이 정답인 사례",
           "이 판정으로 폐지 풀 소비면 순회가 전부 실측 완료됐습니다")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "새 데이터 원천 모듈이 들어오면 측정 하네스 전체를 재사용해 천장을 다시 잽니다",
           "국면 라벨 교체는 별도 연구 라운드로 등재돼 있습니다",
           "민감도 실측 3건은 노출 조절 연구로 이관 완료했습니다",
           "판정: 자본 반영 없음 — 전 과정 참고 기록입니다"))
  ),
  charts = c(p1, p2),
  footer = "📚 FQ-174 NP-2b · p5_np2b.json · metric_type=diagnostic_precheck",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
