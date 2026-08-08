# update_queue_fq093.R — FQ-093 사전 확인 결과를 큐에 반영 (착수 전 전제 반증)
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
QP <- "06_Registry/alpha_frontier_queue.json"
bak <- sprintf("%s.bak_fq093_%s", QP, format(Sys.time(), "%Y%m%d_%H%M%S")); file.copy(QP, bak)
q <- fromJSON(QP, simplifyVector = FALSE); n0 <- length(q$entries); hit <- 0L
for (i in seq_along(q$entries)) {
  e <- q$entries[[i]]; if (is.null(e$id) || !identical(e$id, "FQ-093")) next
  e$precheck_20260808 <- paste0(
    "★착수 전 사전 확인(269개월 실측, `p23_fq093_precheck.R`) — **전제 반증**. ",
    "제안 신호(vol rank 상승속도 = 단면평균 vr_t − vr_lag3)는 오늘 전수 측정한 횡단면 계열과 ",
    "**겹치지 않는다**(disp_trend 와 Spearman −0.153 — 내 겹침 가설은 틀렸음). 그러나 착지점이 같다: ",
    "발화 28개월의 **평균 sleeve 수익 +4.98% vs 미발화 +3.44%**(t=0.99, p=0.327)로 **발화월이 오히려 좋다**. ",
    "즉 위기 조기경보가 아니라 **기회 신호**이며, 이걸로 de-risk 하면 손해다(β≤0.5 적용 시 **dSR −0.079**, dMDD 0.00). ",
    "동일 계열 대조: 분산속도 dSR −0.133 · disp_trend dSR −0.066. ",
    "∴ overlay 축소 트리거로서의 전제는 실측 반증 — 라운드 착수 EV 낮음. ",
    "★단 **기회 신호로서는 미검**(P9 의 횡단면 분산 +8.08% 와 같은 부류) — 소비면을 바꾸면 재시험 대상.")
  e$status <- "precheck_negative"
  e$revival_trigger <- paste0(
    "① 소비면을 '축소 트리거'에서 '기회/집중도 신호'로 바꾸면 재시험(방향이 반대이므로 별개 라운드) ",
    "② 비-return 원천과 결합해 위기 판별력이 생기면 재검 ③ 국면 라벨 자격 관문이 바뀌면 재계산")
  q$entries[[i]] <- e; hit <- 1L
}
stopifnot("FQ-093 미발견" = hit == 1L)
q$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(q, pretty = TRUE, auto_unbox = TRUE, null = "null"), QP)
c2 <- fromJSON(QP, simplifyVector = FALSE)
ok <- any(vapply(c2$entries, function(e) identical(e$id,"FQ-093") && identical(e$status,"precheck_negative"), logical(1)))
cat(sprintf("[검증] entries %d→%d 보존=%s | FQ-093 갱신=%s | 백업 %s\n",
            n0, length(c2$entries), n0 == length(c2$entries), ok, basename(bak)))
stopifnot(n0 == length(c2$entries), ok)
