library(tidyverse, quietly = T)
library(magrittr, quietly = T)
library(ggpubr, quietly = T)
library(viridis, quietly = T)
library(Peptides, quietly = T)


# Function to plot binned feature map

plot_features <- function(binned_features, rt, MZ, fit_bounds){
  
  lib_features <- read.csv(binned_features)
  time_axis <- read.csv(rt, col.names = "rt")
  mz_axis <- bind_rows(data.frame(mz = 401.0305), read.csv(MZ, col.names = "mz"))
  
  lib_features <- lib_features %>%
    set_colnames(mz_axis$mz) %>%
    cbind(time_axis) %>%
    pivot_longer(!rt, names_to = "mz", values_to = "intensity") %>%
    mutate(mz = as.numeric(mz))
  
  plot <- ggplot() +
    theme_minimal()  +
    geom_contour_filled(data = lib_features, aes(x = rt, y = mz, z = intensity, fill = stat(level)))+ 
    scale_y_continuous(expand = c(0, 0)) +
    theme(legend.position='none') +
    scale_fill_manual(values = c("#226d8c", "#277DA1", "#3F8BAB", "#579AB6", "#6FA8C0", "#87B7CB",
                                 "#9FC5D5", "#B7D4E0", "#CFE2EA", "#E7F1F5", "#FFFFFF")) +
    ylab ("m/z") +
    xlab("Retention Time (min)") +
    scale_x_continuous(position = "top")+
    coord_cartesian(xlim = c(18.91, 91.91))
  
  if(missing(fit_bounds)){
    
    plot
    
  } else {
    bounds <- read.csv(fit_bounds)
    
    
    plot +
      geom_line(data = bounds, aes(x = RT, y = Lowmz), color = "#264653", size = 1) +
      geom_line(data = bounds, aes(x = RT, y = Highmz), color = "#264653", size = 1)
    
  }
  
}



# Function to plot acquisition scheme

plot_acquisition_scheme <- function(scan_info, time_start, time_end){
  
  scan_info_full <- read.csv(scan_info) %>%
    mutate(ScanType = "DIA") %>%
    mutate(ScanType = if_else(ms.level == 1, "MS1", ScanType)) %>%
    mutate(ScanType = if_else(str_detect(scanDescription, "ITMS") == TRUE, "Alignment Scan", ScanType)) %>%
    mutate(width = if_else(ScanType == "Alignment Scan", 10, 4)) %>%
    mutate(width = if_else(ScanType == "MS1", 305, width)) %>%
    mutate(WindowStart = precursormz - width) %>%
    mutate(WindowEnd = precursormz + width) %>%
    mutate(TimeEnd = if_else(ScanType == "Alignment Scan", scanTime+0.0001252664*2, scanTime+0.00045*2)) %>%
    mutate(TimeEnd = if_else(ScanType == "MS1", scanTime+0.0004166667*2, TimeEnd))
  
  
  ggplot(scan_info_full, aes(xmin = scanTime, xmax = TimeEnd, 
                             ymin = WindowStart, ymax = WindowEnd, 
                             fill = ScanType)) +
    theme_minimal() +
    geom_rect() +
    coord_cartesian(xlim = c(time_start, time_end)) +
    xlab ("Retention Time (min)") +
    labs(y = expression(italic("m/z"))) +
    scale_fill_manual(name = "Scan Type", values = c("#f9844a", "#277da1", "#264653")) +
    #scale_fill_manual(name = "Scan Type", values = c("#f94144", "#577590", "#264653")) +
    theme(legend.position = "left") + 
    scale_x_continuous(breaks = seq(0, 100, by = 0.02))
  
  
}



# Function to process LoQ info

read_loq <- function(file1, label1, file2, label2){
  
  FoM_1 <- read.csv(file1) %>%
    mutate(Method = label1) %>%
    mutate(Pep_Type = if_else(LOQ <= 100, "B", "A")) %>%
    mutate(Pep_Type = if_else(LOQ <= 10, "C", Pep_Type))
  
  
  
  FoM_2 <- read.csv(file2) %>%
    mutate(Method = label2)  %>%
    mutate(Pep_Type = if_else(LOQ <= 100, "B", "A")) %>%
    mutate(Pep_Type = if_else(LOQ <= 10, "C", Pep_Type))
  
  
  
  all_FoM <- bind_rows(FoM_1, FoM_2) 
  
  return(all_FoM)
}

# Function to plot LoQ density plot

LoQ_density <- function(file1, label1, file2, label2){
  
  all_FoM <- read_loq(file1, label1, file2, label2)
  
  
  print(paste0(label1, " has ", nrow(filter(all_FoM, Method == label1)), " detectable peptides."))
  print(paste0(label1, " has ", nrow(filter(all_FoM, Method == label1 & Pep_Type != "A")),
               " quantifiable peptides."))
  print(paste0(label1, " has ", nrow(filter(all_FoM, Method == label1 & Pep_Type == "C")), 
               " quantifiable peptides over at least 1 order of magnitude."))
  
  print(paste0(label2, " has ", nrow(filter(all_FoM, Method == label2)), " detectable peptides."))
  print(paste0(label2, " has ", nrow(filter(all_FoM, Method == label2 & Pep_Type != "A")), " quantifiable peptides."))
  print(paste0(label2, " has ", nrow(filter(all_FoM, Method == label2 & Pep_Type == "C")), 
               " quantifiable peptides over at least 1 order of magnitude."))
  
  ggplot(all_FoM, aes(x = LOQ, color = Method)) +
    geom_density(alpha = 0) +
    theme_minimal() +
    ylab("Density") +
    xlab("Lower Limit of Quantitation (%)") +
    scale_color_manual(values = c( "#277DA1", "#f94144")) +
    theme(legend.position = c(0.8, 0.8)) +
    geom_vline(xintercept = median(filter(all_FoM, Method == label2& LOQ <= 100)$LOQ), 
               color = "#277DA1", linetype = "dashed")+
    geom_vline(xintercept = median(filter(all_FoM, Method == label1& LOQ <= 100)$LOQ), 
               color = "#f94144", linetype = "dashed")  +
    annotate("text", label = paste0(" ", round(median(filter(all_FoM, Method == label1& LOQ <= 100)$LOQ), 1),
                                    "%"), 
             x = median((filter(all_FoM, Method == label1& LOQ <= 100)$LOQ)) + 0.15,
             y = 0.046, hjust = "left", size = 3,
             color = "#f94144")  +
    annotate("text", label = paste0(round(median(filter(all_FoM, Method == label2& LOQ <= 100)$LOQ), 1),
                                    "% "), 
             x = median((filter(all_FoM, Method == label2& LOQ <= 100)$LOQ)) - 0.15,
             y = 0.046, hjust = "right", size = 3,
             color = "#277DA1") +
    coord_cartesian(xlim = c(3, 97))
  
  
  
  print(paste0(label1, " has ", median(filter(all_FoM, Method == label1& LOQ <= 100)$LOQ), " median LoQ."))
  print(paste0(label2, " has ", median(filter(all_FoM, Method == label2& LOQ <= 100)$LOQ), " median LoQ."))
  
  
  
}


LoQ_density_cum <- function(file1, label1, file2, label2){
  
  all_FoM <- read_loq(file1, label1, file2, label2)
  
  
  print(paste0(label1, " has ", nrow(filter(all_FoM, Method == label1)), " detectable peptides."))
  print(paste0(label1, " has ", nrow(filter(all_FoM, Method == label1 & Pep_Type != "A")),
               " quantifiable peptides."))
  print(paste0(label1, " has ", nrow(filter(all_FoM, Method == label1 & Pep_Type == "C")), 
               " quantifiable peptides over at least 1 order of magnitude."))
  
  print(paste0(label2, " has ", nrow(filter(all_FoM, Method == label2)), " detectable peptides."))
  print(paste0(label2, " has ", nrow(filter(all_FoM, Method == label2 & Pep_Type != "A")), " quantifiable peptides."))
  print(paste0(label2, " has ", nrow(filter(all_FoM, Method == label2 & Pep_Type == "C")), 
               " quantifiable peptides over at least 1 order of magnitude."))
  
  ggplot(all_FoM, aes(x = LOQ, color = Method)) +
    #stat_ecdf(geom = "step")+
    #stat_bin(aes(y=cumsum(..count..), LOQ=LOQ),geom="line") +
    #geom_step(aes(len=length(all_FoM), y = ..y..*len),stat = "ecdf") +
    stat_bin(data = filter(all_FoM, Method == label2), aes(y=cumsum(..count..), LOQ=LOQ), geom="line") +
    stat_bin(data = filter(all_FoM, Method == label1), aes(y=cumsum(..count..), LOQ=LOQ), geom="line") +
    theme_minimal() +
    ylab("Total peptides") +
    xlab("Lower Limit of Quantitation (%)")+
    scale_color_manual(values = c( "#277DA1", "#f94144")) +
    theme(legend.position = "none")
  
  
}


# Function for pairwise LoQ comparison

LoQ_pairwise_histogram <- function(file1, label1, file2, label2) {
  
  all_FoM <- read_loq(file1, label1, file2, label2)
  
  quant_in_1 <- filter(all_FoM, Method == label1) %>%
    select(peptide, LOQ) %>%
    filter(LOQ >= 0 & LOQ <= 100)
  
  
  quant_in_2 <- filter(all_FoM, Method == label2) %>%
    select(peptide, LOQ) %>%
    filter(LOQ >= 0 & LOQ <= 100)
  
  both <- nrow(semi_join(quant_in_1, quant_in_2, by = "peptide"))
  
  only_1 <- nrow(anti_join(quant_in_1, quant_in_2, by = "peptide"))
  
  only_2 <- nrow(anti_join(quant_in_2, quant_in_1, by = "peptide"))
  
  print(paste0(label1, " quantifies ", only_1, " unique peptides."))
  print(paste0(label2, " quantifies ", only_2, " unique peptides."))
  print(paste0(both, " peptides are quantified in both methods."))
  
  
  Pairwise_FoM <- filter(all_FoM, Method == label1) %>%
    select(peptide, LOQ) %>%
    set_colnames(c("peptide", "LOQ1")) %>%
    inner_join(filter(all_FoM, Method == label2), by = "peptide") %>%
    select(peptide, LOQ, LOQ1) %>%
    set_colnames(c("peptide","LOQ2", "LOQ1")) %>%
    filter(LOQ2<=100 & LOQ1<=100) %>%
    mutate(ratio = LOQ2/LOQ1) %>%
    mutate(logratio = log10(ratio)) %>%
    mutate(BetterMethod = if_else(logratio > 0, label1, label2)) %>%
    mutate(BetterMethod = if_else(logratio == 0, "Tie", BetterMethod))
  
  
  ggplot((Pairwise_FoM), aes(x = logratio, fill = BetterMethod)) +
    geom_histogram(bins = 40, color = "black") +
    theme_minimal() +
    geom_vline(xintercept = median(Pairwise_FoM$logratio), linetype = "dashed", color = "#f9c74f") +
    ylab("Number of peptides") +
    xlab(paste0("log10(LoQ in ", label2, "/LoQ in ", label1, ")")) +
    scale_fill_manual(values = c("#577590", "#f94144", "grey"), name = "Better LoQ in:") +
    theme(legend.position = c(0.72, 0.75), plot.title = element_text(hjust = 0.5)) +
    #ggtitle(paste0("Pairwise comparsion of ", prettyNum(nrow(Pairwise_FoM), big.mark = ","), 
    #               " peptides \n with LoQs in both methods"))  +
    annotate("text", label = paste0("log10(median) = ", round(median(Pairwise_FoM$logratio), 3),
                                    "\nmedian = ", round(10^median(Pairwise_FoM$logratio), 3)), 
             x = median(Pairwise_FoM$logratio) - 0.06,
             y = 1420, hjust = "right", size = 3) +
    geom_vline(xintercept = 0, color = "black")
  
  
}



LoQ_pairwise_histogram_min <- function(file1, label1, file2, label2) {
  
  all_FoM <- read_loq(file1, label1, file2, label2)
  
  quant_in_1 <- filter(all_FoM, Method == label1) %>%
    select(peptide, LOQ) %>%
    filter(LOQ >= 0 & LOQ <= 100)
  
  
  quant_in_2 <- filter(all_FoM, Method == label2) %>%
    select(peptide, LOQ) %>%
    filter(LOQ >= 0 & LOQ <= 100)
  
  both <- nrow(semi_join(quant_in_1, quant_in_2, by = "peptide"))
  
  only_1 <- nrow(anti_join(quant_in_1, quant_in_2, by = "peptide"))
  
  only_2 <- nrow(anti_join(quant_in_2, quant_in_1, by = "peptide"))
  
  print(paste0(label1, " quantifies ", only_1, " unique peptides."))
  print(paste0(label2, " quantifies ", only_2, " unique peptides."))
  print(paste0(both, " peptides are quantified in both methods."))
  
  
  Pairwise_FoM <- filter(all_FoM, Method == label1) %>%
    select(peptide, LOQ) %>%
    set_colnames(c("peptide", "LOQ1")) %>%
    inner_join(filter(all_FoM, Method == label2), by = "peptide") %>%
    select(peptide, LOQ, LOQ1) %>%
    set_colnames(c("peptide","LOQ2", "LOQ1")) %>%
    filter(LOQ2<=100 & LOQ1<=100) %>%
    mutate(ratio = LOQ2/LOQ1) %>%
    mutate(logratio = log10(ratio)) %>%
    mutate(BetterMethod = if_else(logratio > 0, label1, label2)) %>%
    mutate(BetterMethod = if_else(logratio == 0, "Tie", BetterMethod))
  
  
  ggplot((Pairwise_FoM), aes(x = logratio, fill = BetterMethod)) +
    geom_histogram(bins = 40, color = "black") +
    theme_minimal() +
    geom_vline(xintercept = median(Pairwise_FoM$logratio), linetype = "dashed", color = "#f9c74f") +
    ylab("Number of peptides") +
    xlab(paste0("log10(LoQ in ", label2, "/LoQ in ", label1, ")")) +
    scale_fill_manual(values = c("#577590", "#f94144", "grey"), name = "Better LoQ in:") +
    geom_vline(xintercept = 0, color = "black") +
    theme(legend.position = "none")
  
  
}


# Function to show peptide summary by method

method_summary_plot <- function(file1, label1, file2, label2){
  
  all_FoM <- read_loq(file1, label1, file2, label2)
  
  ggplot(all_FoM, aes(x = Method, fill = Pep_Type)) +
    geom_bar() +
    theme_minimal() +
    scale_fill_manual(name = "Quantifiable?", labels = c("No", "Yes", "By factor of 10"), 
                      values = c("#CFE2EA", "#87B7CB", "#277DA1")) +
    ylab("Number of Peptides") +
    theme(legend.position = "bottom")
  
  
}
