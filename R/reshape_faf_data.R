#' Reshape and extend the FAF v4 data from original to simulation-ready format
#'
#' @param faf_flow_data Filename of FAF flow data in the format distributed by
#'   FHWA (i.e., as downloaded from their website). This file can be the URL
#'   from the FAF website, or stored locally. It can also be stored in gzip
#'   format.
#' @param faf_interregional_distances Name of file containing FAF inter-regional
#'   distances. Fields for dms_orig (domestic origin), dms_dest (domestic
#'   destination), and distance should be provided. All other fields are
#'   ignored, if included.
#' @param internal_faf_regions A list of the FAF regions within the modeled or
#'   study area. If not specified the entire FAF database will be processed.
#'   (Optional)
#' @param halo_faf_regions A optional list of FAF regions adjacent to the
#'   modeled or study area that might create flows through it. This parameter
#'   can be omitted if desired, which will imply that no halo is defined.
#'   (Optional, and ignored if internal_faf_regions are not specified)
#' @param save_to Filename for saving the processed FAF trip records in
#'   comma-separated value format. (Optional)
#'
#' @details This function reshapes the FHWA Freight Analysis Framework (FAF)
#'   data from its originally distributed format into a one more ideally suited
#'   for visualization with ggplot2 or use in time-series simulation. It changes
#'   the format of categorical variables from hard-to-remember integer values to
#'   descriptive strings, and adds the distance between the centroids of the
#'   domestic origins and destinations. The value of shipments and tonnage,
#'   originally coded in millions of dollars and thousands of tons, are stored
#'   in unscaled format. The format of the data is also changed, with a separate
#'   record created for each year. The original data have several valueyyyy and
#'   tonsyyyy fields, corresponding to the years included for each FAF region
#'   origin-destination pair. These are rewritten for each year. It leads to a
#'   larger data frame than the original, but can be more easily filtered by
#'   year in downstream code. Finally, the function can filter out observations
#'   that are not within a specified internal and halo study or modeled area,
#'   which usually reduces the size of the resulting data frame considerably.
#'   This can significantly reduce the amount of time required to process these
#'   data in subsequent analyses. The user can also optionally save the results
#'   in a comma-separated value file. The function returns the processed data
#'   frame, which of course can be stored in any format desired.
#'
#' @export
#' @examples
#' # Process the entire FAF dataset, and save results in CSV file
#' faf <- reshape_faf_data(faf_flow_data, faf_skims, save_to = "reshaped-faf.csv")
#'
#' # Process Oregon as internal, with Idaho and Washington as the halo
#' oregon <- reshape_faf_data(faf_flow_data, faf_interregional_distances,
#'   c(141, 149, 532), c(160, 531, 539), "reshaped-faf.csv")

reshape_faf_data <- function(faf_flow_data,
  faf_interregional_distances = faf4_interregional_distances,
  internal_faf_regions = NULL, halo_faf_regions = c(), save_to = NULL) {
  # How we process zones will depend upon what category they are (internal
  # versus halo). Start by extracting all travel to, fron, and within the FAF
  # regions classified as internal to our study area. Bugs in read_csv surface
  # when col_types = "number", so we're explicit about the fields we need to be
  # in certain format.
  raw <- readr::read_csv(faf_flow_data) %>%
    dplyr::mutate(fr_orig = as.integer(fr_orig), fr_dest = as.integer(fr_dest),
      dms_orig = as.integer(dms_orig), dms_dest = as.integer(dms_dest),
      fr_inmode = as.integer(fr_inmode), fr_outmode = as.integer(fr_outmode),
      sctg2 = as.integer(sctg2))
  print(paste(nrow(raw), "records read from", faf_flow_data), quote = FALSE)
  internal <- dplyr::filter(raw,
    dms_orig %in% internal_faf_regions | dms_dest %in% internal_faf_regions)

  # Next extract flows that are between the halo zones, for we have already
  # grabbed those between the halo and internal in the step above. We can also
  # ignore trips that are internal to a halo region.
  if (length(halo_faf_regions)>0) {
    halo <- raw %>%
      dplyr::filter(dms_orig %in% halo_faf_regions &
        dms_dest %in% halo_faf_regions) %>%
      dplyr::filter(dms_orig != dms_dest)
  } else {
    halo <- dplyr::data_frame()
  }
  combined <- dplyr::bind_rows(internal, halo)
  print(paste(nrow(combined), "internal and halo flow records retained"),
    quote = FALSE)

  # The raw data are in wide format, with tonnage and value for several years
  # (base year plus several forecast years in five-year intervals). Convert the
  # data into tall format so that we can separate the year from the metric, and
  # then put it back into (sort of) wide format so that we can easily filter by
  # year.
  reformatted <- combined %>%
    tidyr::gather("vname", "n", -(fr_orig:trade_type)) %>%
    tidyr::separate(vname, c("vname", "year"), sep = '_') %>%
    tidyr::spread(vname, n)

  # Next append the skim distance between the FAF regions, which are obtained
  # from a matrix of such values previously compiled by @gregmacfarlane, and
  # stored as a data frame.
  distance <- readr::read_csv(faf_interregional_distances)
  faf <- dplyr::left_join(reformatted, distance, by = c("dms_orig", "dms_dest"))

  # Make sure that all of the records now have distance coded. If missing values
  # snuck through them catch them now.
  problem_children <- dplyr::filter(faf, is.na(distance))
  if (nrow(problem_children)>0) {
    print("FAF region pairs with missing skim values:", quote = FALSE)
    missing_skims <- xtabs(~dms_orig+dms_dest, data = problem_children)
    print(missing_skims)
    stop("FAF regions found in flow data, but no corresponding skims")
  }

  # Several of the variables in the original data have numeric values that are
  # hard to remember what they stand for. We will make it simpler by recoding
  # these variables. We will be able to distinguish them from their original
  # counterparts by converting the variable name to camelCase.
  trade_type_labels <- c("Domestic", "Import", "Export")
  faf$trade_type <- trade_type_labels[faf$trade_type]

  # Do the same for the modes of transport
  mode_labels <- c("Truck", "Rail", "Water", "Air", "Multi", "Pipeline",
    "Other", "None")   # Corresponds to FAF modes 1-8
  faf$dms_mode <- factor(mode_labels[faf$dms_mode], levels = mode_labels)
  faf$fr_inmode <- factor(mode_labels[faf$fr_inmode], levels = mode_labels)
  faf$fr_outmode <- factor(mode_labels[faf$fr_outmode], levels = mode_labels)

  # Recode commodities as factors
  faf$sctg2 <- factor(faf$sctg2)

  # Scale the units for tons (thousands) and value (millions)
  faf$value <- round(faf$value*1e6, 2)
  faf$tons <- round(faf$tons*1e3, 1)

  # Write the data frame to a CSV file if the user has asked for it
  if (!is.null(save_to)) readr::write_csv(faf, save_to)

  # Return the results
  faf
}
