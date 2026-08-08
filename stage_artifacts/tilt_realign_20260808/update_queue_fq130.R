suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
QP <- "06_Registry/alpha_frontier_queue.json"
bak <- sprintf("%s.bak_fq130_%s", QP, format(Sys.time(), "%Y%m%d_%H%M%S")); file.copy(QP, bak)
q <- fromJSON(QP, simplifyVector = FALSE); n0 <- length(q$entries); hit <- 0L
for (i in seq_along(q$entries)) {
  e <- q$entries[[i]]; if (is.null(e$id) || !identical(e$id, "FQ-130")) next
  e$precheck_20260808 <- paste0(
    "★착수 전 사전 확인(438개월·472,754행, 유동성 2e8, `p25_fq130_precheck.R`) — **전제 약함**. ",
    "MAX5(과거 1개월 상위 5개 일간수익 평균) FMB 를 cap-tier 별로 full-spec(월별 횡단면 회귀 + vol·size 통제)로 재검: ",
    "**MEGA 단순 t=0.22 → 통제 t=1.27**(유의 미달). MID 단순 t=−5.42 → 통제 t=0.14 · SMALL −6.21 → 0.34 — ",
    "즉 MID/SMALL 의 강한 음의 MAX 효과는 **전량 변동성 대리**이고 통제하면 사라진다. MEGA 는 통제 전후 모두 신호 없음. ",
    "축약 스펙의 t +2.76 은 재현되지 않음. ",
    "★검정력 우려는 **해소**: 내 MEGA tier(유동성 유니버스 size 상위 10%)는 월평균 **107종목**으로 n=10 이 아니다. ",
    "⚠단 이는 **tier 정의가 원 스펙과 다르다**는 뜻이기도 하다 — 원 스펙이 '상위 10종목' 리터럴이면 내가 잰 집합과 다르며, ",
    "그 경우 n=10/월로는 애초에 측정 불가라는 큐 자신의 지적이 유효하다. ",
    "∴ 어느 해석에서든 착수 EV 낮음(넓은 정의=신호 없음 / 좁은 정의=측정 불가).")
  e$status <- "precheck_negative"
  e$revival_trigger <- paste0(
    "① MEGA 를 리터럴 상위 10종목으로 정의하고 표본을 늘릴 방법(장기 패널·다국가)이 생기면 재시험 ",
    "② MAX5 외 복권형 대리변수(왜도·IVOL 잔차 등)로 바꾸면 별개 라운드 ",
    "③ vol 통제를 제거한 스펙을 '통제 없는 버전'으로 명시 소비하려면 그 자체를 사전등록")
  q$entries[[i]] <- e; hit <- 1L
}
stopifnot("FQ-130 미발견" = hit == 1L)
q$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(q, pretty = TRUE, auto_unbox = TRUE, null = "null"), QP)
c2 <- fromJSON(QP, simplifyVector = FALSE)
ok <- any(vapply(c2$entries, function(e) identical(e$id,"FQ-130") && identical(e$status,"precheck_negative"), logical(1)))
n_pn <- sum(vapply(c2$entries, function(e) identical(e$status,"precheck_negative"), logical(1)))
cat(sprintf("[검증] entries %d→%d 보존=%s | FQ-130 갱신=%s | precheck_negative 총 %d건 | 백업 %s\n",
            n0, length(c2$entries), n0==length(c2$entries), ok, n_pn, basename(bak)))
stopifnot(n0 == length(c2$entries), ok)
