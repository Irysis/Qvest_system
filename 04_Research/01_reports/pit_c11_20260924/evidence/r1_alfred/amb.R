suppressMessages(library(data.table)); P <- readRDS("profile.rds")
for (s in c("CPIAUCSL","INDPRO","FEDFUNDS","UMCSENT","PERMIT")) { V <- sort(as.Date(readLines(paste0("vint_", s, ".txt")))); d <- P[[s]][nwin >= 2]
  cat("\n==", s, nrow(d), "\n"); for (i in seq_len(min(nrow(d), if (s=="PERMIT") 12 else 30))) { w <- V[V > d$pe[i] & V <= d$pe[i] + 34]; cat(format(d$obs[i]), ":", paste(format(w), collapse=" "), "\n") } }
