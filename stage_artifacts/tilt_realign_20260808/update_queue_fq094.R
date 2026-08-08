suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
QP <- "06_Registry/alpha_frontier_queue.json"
bak <- sprintf("%s.bak_fq094_%s", QP, format(Sys.time(), "%Y%m%d_%H%M%S")); file.copy(QP, bak)
q <- fromJSON(QP, simplifyVector = FALSE); n0 <- length(q$entries); hit <- 0L
for (i in seq_along(q$entries)) {
  e <- q$entries[[i]]; if (is.null(e$id) || !identical(e$id, "FQ-094")) next
  e$precheck_20260808 <- paste0(
    "★착수 전 사전 확인(426개월·445,720행, 유동성 2e8 필터, `p24_fq094_precheck.R`) — **전제 약함**. ",
    "①역방향 rank-IC **mean −0.0025 · t = −0.60 · IC>0 비율 49.1%**(동전) — '정방향 FMB t=2.50* 이므로 역방향도 유의 가능'이라는 전제가 지지되지 않는다(역방향은 단순 부호 반전이 아님). ",
    "②익월 수익: autocorr 최저20 +0.41% vs 최고20 +0.38%(t=0.33, p=0.742) — 차이 없음. ",
    "③cap-tier 분해: MEGA −0.0052(t −0.65) · MID −0.0052(t −0.97) · SMALL +0.0048(t 1.18) — 어느 tier 에도 유의 신호 없음. ",
    "★부수: `wall_check` 가 우려한 'low-autocorr = 고변동성 과다표현'은 **반대 방향으로 반증**(최저20 변동성 0.0341 < 최고20 0.0362, t=−21.87) — 우려 자체가 기각. ",
    "∴ 착수 EV 낮음. 정방향의 신호력(FMB t)이 역방향 신호력을 함의하지 않음이 실측 확인.")
  e$status <- "precheck_negative"
  e$revival_trigger <- paste0(
    "① autocorr 창(12M)을 바꾸거나 가중/비선형 형태로 재정의하면 재시험 ",
    "② 국면 조건부(특정 regime 안에서만)로 좁히면 별개 라운드 ",
    "③ 정방향의 FMB 신호력이 어디서 오는지 규명되면 역방향 설계가 달라질 수 있음")
  q$entries[[i]] <- e; hit <- 1L
}
stopifnot("FQ-094 미발견" = hit == 1L)
q$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(q, pretty = TRUE, auto_unbox = TRUE, null = "null"), QP)
c2 <- fromJSON(QP, simplifyVector = FALSE)
ok <- any(vapply(c2$entries, function(e) identical(e$id,"FQ-094") && identical(e$status,"precheck_negative"), logical(1)))
cat(sprintf("[검증] entries %d→%d 보존=%s | FQ-094 갱신=%s | 백업 %s\n",
            n0, length(c2$entries), n0==length(c2$entries), ok, basename(bak)))
stopifnot(n0 == length(c2$entries), ok)
