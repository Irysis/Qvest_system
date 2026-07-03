# [1.5/5] Naver T+0 보완 — KRX T+1 발행지연 gap을 Naver로 채움.
# ★외부화 2026-06-19(도훈 "왜 네이버를 안쓰지"): 기존 morning_briefing.sh의 인라인 멀티라인 `Rscript -e`가
#   첫 줄 invisible(NULL)만 실행되는 no-op 트랩이라 naver_run_pipeline()이 한 번도 안 돌았음(KRX 지연분 미보완).
#   단일줄 source 패턴으로 수리. (TZ 버그 수정으로 last_confirmed=T-1 정상화도 동반 — trading_calendar.R)
source("02_Infrastructure/ops/morning_steps/_root.R")
source("02_Infrastructure/data/naver_data_collector.R")
tryCatch(naver_run_pipeline(),
         error = function(e) cat(sprintf("Naver pipeline skipped: %s\n", e$message)))
