# This script should build binary dataset with skim distances
distancesFN <- "data-raw/faf4_interregional_distances.csv"
faf4_interregional_distances <- readr::read_csv(distancesFN)
devtools::use_data(faf4_interregional_distances)
