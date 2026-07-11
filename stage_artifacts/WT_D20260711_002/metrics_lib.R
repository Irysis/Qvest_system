#==============================================================================
# WT-D20260711_002 Phase A — metrics_lib.R
# FROZEN objective readability metrics (preregistration.json sha256 96b7e06d...).
# subjective=0, deterministic. Shared by fetch step + convergence check.
#==============================================================================
suppressPackageStartupMessages({ library(stringi) })

.HANGUL <- paste0("[", intToUtf8(0xAC00), "-", intToUtf8(0xD7A3), "]")
.HANJA  <- paste0("[", intToUtf8(0x4E00), "-", intToUtf8(0x9FFF), "]")

# tag-strip identical to pilot 02_fetch_excerpts.R::strip_all
strip_all <- function(x) {
  x <- gsub("&cr;","\n",x,fixed=TRUE); x <- gsub("<[^>]+>"," ",x)
  x <- gsub("&#[0-9]+;"," ",x); x <- gsub("&[a-zA-Z]+;"," ",x)
  x <- gsub("[ \t]+"," ",x); x <- gsub(" *\n *","\n",x); trimws(x)
}

# FROZEN: full MD&A section = last '경영진단 및 분석의견' anchor -> next standard
# post-MD&A header (fixed candidate list) or +40000 chars cap.
.NEXT_HEADERS <- c("주요계약 및 연구개발활동","연구개발활동","그 밖에 투자자 보호",
                   "그 밖에 투자의사결정","이사회에 관한 사항","감사제도에 관한 사항",
                   "주주에 관한 사항","임원 및 직원","계열회사","타법인출자")
extract_mdna_full <- function(plain) {
  anc <- "경영진단 및 분석의견"
  occ <- gregexpr(anc, plain, fixed=TRUE)[[1]]
  if (occ[1] < 0) return(NULL)
  start <- occ[length(occ)]                       # last occ = body
  tail_txt <- substr(plain, start + 500L, nchar(plain))
  ends <- vapply(.NEXT_HEADERS, function(h) {
    p <- regexpr(h, tail_txt, fixed=TRUE)[1]; if (p > 0) p else NA_integer_
  }, integer(1))
  rel_end <- suppressWarnings(min(ends, na.rm=TRUE))
  end <- if (is.finite(rel_end)) start + 500L + rel_end - 1L else min(start + 40000L, nchar(plain))
  sec <- substr(plain, start, end)
  # skip the near-identical '예측정보 주의사항' boilerplate: start at first '개요' within 2500
  win <- substr(sec, 1, 2500)
  gi <- regexpr("개요", win, fixed=TRUE)[1]
  if (gi > 0) sec <- substr(sec, gi, nchar(sec))
  sec
}

# FROZEN metric computation on a stripped MD&A section
compute_metrics <- function(section) {
  s <- section
  n_hangul <- stri_count_regex(s, .HANGUL)
  n_hanja  <- stri_count_regex(s, .HANJA)
  n_latin  <- stri_count_regex(s, "[A-Za-z]")
  n_digit  <- stri_count_regex(s, "[0-9]")
  content  <- n_hangul + n_hanja + n_latin
  # sentences: split on .!? ; qualifying = nchar>=10 & has hangul
  segs <- unlist(stri_split_regex(s, "[.!?]+"))
  seg_ok <- segs[nchar(segs) >= 10 & stri_count_regex(segs, .HANGUL) > 0]
  m1_avg_sentence_len_chars <- if (length(seg_ok) > 0) mean(nchar(seg_ok)) else NA_real_
  # words per sentence + hard-word pct (over qualifying sentences)
  wc <- lapply(seg_ok, function(sg) {
    toks <- unlist(stri_split_regex(sg, "\\s+"))
    toks <- toks[nzchar(toks)]
    if (length(toks) == 0) return(character(0))
    keep <- stri_count_regex(toks, .HANGUL) > 0 | stri_count_regex(toks, "[A-Za-z]") > 0
    toks[keep]
  })
  all_words <- unlist(wc)
  nsent <- length(seg_ok)
  words_per_sent <- if (nsent > 0) length(all_words) / nsent else NA_real_
  hard <- if (length(all_words) > 0) {
    hlen <- stri_count_regex(all_words, .HANGUL)
    has_jargon <- stri_count_regex(all_words, .HANJA) > 0 | stri_count_regex(all_words, "[A-Za-z]") > 0
    (hlen >= 4) | has_jargon
  } else logical(0)
  pct_hard <- if (length(all_words) > 0) mean(hard) else NA_real_
  m2_fog_kr <- if (!is.na(words_per_sent) && !is.na(pct_hard)) 0.4*(words_per_sent + 100*pct_hard) else NA_real_
  m3_hanja_latin_density <- if (content > 0) (n_hanja + n_latin) / content else NA_real_
  m4_numeric_table_density <- if ((n_digit + content) > 0) n_digit / (n_digit + content) else NA_real_
  m5_section_nchar <- nchar(s)
  list(
    m1_avg_sentence_len_chars = m1_avg_sentence_len_chars,
    m2_fog_kr = m2_fog_kr,
    m3_hanja_latin_density = m3_hanja_latin_density,
    m4_numeric_table_density = m4_numeric_table_density,
    m5_section_nchar = m5_section_nchar,
    n_content_chars = content, n_sentences = nsent, n_words = length(all_words)
  )
}

# char 5-gram Jaccard for boilerplate YoY (m6) — computed pairwise in analysis step
char_ngram_set <- function(s, n = 5L) {
  s2 <- gsub("\\s+", "", s)
  if (nchar(s2) < n) return(character(0))
  unique(stri_sub(s2, 1:(nchar(s2)-n+1L), length = n))
}
jaccard <- function(a, b) {
  if (length(a) == 0 || length(b) == 0) return(NA_real_)
  length(intersect(a,b)) / length(union(a,b))
}
