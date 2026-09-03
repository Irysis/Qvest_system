suppressMessages(library(jsonlite))
p <- fromJSON("qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json", simplifyVector=FALSE)
cat("TOP KEYS:\n"); print(names(p))
show <- function(x, pre="", depth=0){
  if(depth>1) return(invisible())
  if(is.list(x)){
    nm <- names(x)
    if(is.null(nm)) { cat(pre,"[unnamed list len",length(x),"]\n"); return(invisible()) }
    for(k in nm){
      v <- x[[k]]
      if(is.list(v)) { cat(pre,k," <list ",length(v),">\n",sep=""); show(v, paste0(pre,"  "), depth+1) }
      else cat(pre,k," = ",substr(paste(v,collapse=","),1,180),"\n",sep="")
    }
  }
}
show(p)
