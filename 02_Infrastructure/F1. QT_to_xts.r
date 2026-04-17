#퀀티와이즈 시계열 데이터를 xts class 변환하는 함수

QT_to_xts <- function(x){
  x <- x[-1:-5,]
  x <- x %>% 
    dplyr::rename("DATE" = 'Code')
  
  x <- apply(x, 2, as.numeric) %>% as.data.frame()
  
  x$DATE <- as.Date(x$DATE, origin = "1899-12-30")
  
  rownames(x) <- x$DATE
  
  x <- x[,-1]
  
  x <- as.xts(x)
}

QT_to_xts_macro <- function(x){
  x <- x[-1:-7,]
  x <- x %>% 
    dplyr::rename("DATE" = 'Code')
  
  x <- apply(x, 2, as.numeric) %>% as.data.frame()
  
  x$DATE <- as.Date(x$DATE, origin = "1899-12-30")
  
  rownames(x) <- x$DATE
  
  x <- x[,-1]
  
  x <- as.xts(x)
}
