suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099d1a] ",fmt,"\n"),...))
dd <- fread("stage_artifacts/fq099/fq099d1b_dedup.csv")
clean <- dd[dedup_flag==FALSE]$code
say("★입력 실측: 깨끗한 미탐색 %d건 (중복기재 %d건 제외)", length(clean), nrow(dd)-length(clean))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
## 기전 서술 판정 = 정의문에 문헌 인용 또는 경제 해석 문장이 있는가 (비율 공식만이면 없음)
CIT <- c("(19","(20","et al","Novy-Marx","Piotroski","Sloan","Fama","Altman","Ohlson","Asness",
         "Frazzini","Beneish","Titman","Jegadeesh","Daniel","Hou","Cooper","Richardson")
rows <- rbindlist(lapply(clean, function(k){
  f <- reg[[k]]; if (is.null(f)) return(NULL)
  d  <- if (is.null(f$definition)) "" else f$definition
  lb <- f$labels
  cit <- any(sapply(CIT, function(p) grepl(p, d, fixed=TRUE)))       # ★fixed 필수
  ## 정의문에서 공식 뒤 해석 문장 존재 여부 (마침표 2개 이상 = 공식 + 설명)
  nsent <- length(gregexpr(".", d, fixed=TRUE)[[1]])
  data.table(code=k, cat=if(is.null(f$category)) "?" else f$category,
             ev=if(is.null(lb$evidence_tier)) NA_character_ else as.character(lb$evidence_tier),
             cite=cit, nsent=nsent, deflen=nchar(d), def=substr(d,1,88))
}))
say("--- 기전 서술(문헌 인용) 있는 것 ---")
a <- rows[cite==TRUE]
say("  %d / %d 건", nrow(a), nrow(rows))
if (nrow(a)) for (i in seq_len(nrow(a))) say("  %-28s [%s] %s", a$code[i], a$cat[i], a$def[i])
say("--- 인용 없음: 설명문장 유무로 2차 분류 ---")
b <- rows[cite==FALSE]
say("  설명 있음(문장>=2) %d건 · 공식만(문장<2) %d건", nrow(b[nsent>=2]), nrow(b[nsent<2]))
for (i in seq_len(nrow(b[nsent<2]))) say("  [공식만] %-28s %s", b[nsent<2]$code[i], b[nsent<2]$def[i])
fwrite(rows, "stage_artifacts/fq099/fq099d1a_mechanism.csv")
say("저장 → stage_artifacts/fq099/fq099d1a_mechanism.csv")
