rm(list = ls())

library(tidyverse)
library(magrittr)
library(stars)
library(arrow)

#load functions
source("./functions.r") #cpc_rename, tmfemi_reformat


# The list of projects to be run in this evaluation:
proj_meta = read.csv("/home/tws36/4c_evaluations/data/project_metadata/proj_meta.csv")
projects = c("1112", "1113", "1201", "1396", "1399")

c = Sys.time()
biome_proj_list = lapply(seq_along(projects), function(i) {
  proj = projects[i]
  t0 = proj_meta %>% filter(ID == proj) %>% pull(t0)

  k = read_parquet(paste0("/maps/epr26/tmf_pipe_out/", proj, "/", proj, "k.parquet")) %>%
    dplyr::select(c("lat", "lng", "ecoregion"))
  matches = read_parquet(paste0("/maps/epr26/tmf_pipe_out/", proj, "/", proj, "matches.parquet"))

  #get biome
  matches_biome = matches %>% dplyr::select(c("lat", "lng", "ecoregion"))

  pair_paths = list.files(paste0("/maps/epr26/tmf_pipe_out/", proj, "/pairs"), full = TRUE)
  matchless_ind = pair_paths %>% str_detect("matchless")
  parquet_ind = pair_paths %>% str_detect(".parquet")
  matched_paths = pair_paths[!matchless_ind & parquet_ind]

  a = Sys.time()
  biome_list = mclapply(seq_along(matched_paths), mc.cores = 10, function(j) {
    pairs = read_parquet(matched_paths[j]) %>%
      dplyr::left_join(., k, by = join_by(k_lat == lat, k_lng == lng)) %>%
      rename(k_ecoregion = ecoregion) %>%
      dplyr::left_join(., matches_biome, by = join_by(k_lat == lat, k_lng == lng)) %>%
      rename(s_ecoregion = ecoregion)

    control <- pairs %>%
      dplyr::select(starts_with('s_')) %>%
      rename_with(~str_replace(.x, 's_', '')) %>%
      mutate(treatment = 'control') %>%
      tmfemi_reformat(t0 = t0)

    treat <- pairs %>%
      dplyr::select(starts_with('k_')) %>%
      rename_with(~str_replace(.x, 'k_', '')) %>%
      mutate(treatment = 'treatment') %>%
      tmfemi_reformat(t0 = t0)

    if("biome" %in% colnames(control) & "biome" %in% colnames(treat)) {
      biome_df = rbind(control, treat) %>%
        pull(biome) %>%
        table() %>%
        as.data.frame() %>%
        mutate(pair = j)
    }

  # pair_var = rbind(control, treat) %>%
  #     dplyr::select(elevation:biome) %>%
  #     reframe(elevation = median(elevation),
  #             slope = median(slope),
  #             accessibility = median(accessibility),
  #             cpc0_u = median(cpc0_u),
  #             cpc0_d = median(cpc0_d),
  #             cpc5_u = median(cpc5_u),
  #             cpc5_d = median(cpc5_d),
  #             cpc10_u = median(cpc10_u),
  #             cpc10_d = median(cpc10_d)) %>%
  #     pivot_longer(cols = elevation:cpc10_d, names_to = "var", values_to = "val") %>%
  #     mutate(pair = j)
    return(biome_df)
  })

  b = Sys.time()
  cat(b - a, "\n") #35 seconds per project: fast enough

  biome_proj_df = do.call(rbind, biome_list) %>%
    mutate(project = proj)

  return(biome_proj_df)
})
d = Sys.time()
cat("Total:", d - c, "\n") #7.111846 when mclapply outside, 2.133847 when mclapply inside


biome_proj = do.call(rbind, biome_proj_list)