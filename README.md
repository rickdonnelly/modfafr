# modfafr
Reshape FAF flow data for use in data analyses and simulation

The FHWA [Freight Analysis System](http://www.ops.fhwa.dot.gov/freight/freight_analysis/faf/) (FAF) contains commodity flow estimates and forecasts between regions within the USA by mode of transport and commodity. This small library contains functions that morph the FAF data into a format better suited for time series analysis and simulation modeling. This functionality and supporting data are bundled in a R package, which can be installed from this repository:

```
install.packages("devtools")  # if not already installed
devtools::install_github("rickdonnelly/modfafr")
```

The FAF fuses data from several public and private databases to create these static forecasts, which are publicly available. The flow data are distributed in comma-separated value format, with separate records for each pair of domestic origin-destination FAF regions, commodity, and mode of transportation (and foreign origin, destination, and mode of transport, if applicable). There are separate columns on each row for estimates of total tonnage and shipment value by year. The functions in this package transforms these data into a format that I have found much easier to use for data mining and simulation: 

+ A separate record is created for each year from each original record. The latter represents each combination of origin, destination, commodity, and mode of transport. Note that foreign origin, destination, and travel mode are also define a unique record, if applicable. 
+ The total value and tonnage, provided in implied millions of dollars and thousands of tons, are converted into actual value and tonnage (i.e., multiplied by 1e6 and 1e3, respectively).
+ The modes of transport and trade type are coded as unintuitive integer codes. They are replaced by descriptive strings. They make the data frame slightly larger, but make processing easier and less error-prone. 
+ A subset of FAF regions can be defined as being internal to or in the halo of the model or study area, reducing the amount of time required to process these data by eliminating irrelevant data. This might not be useful in Kansas, where flows from most of the country could pass through. But it can make handling of states at or near the edge of the continent much quicker to process (assuming that you can identify the halo from which most through trips will come to and from).
+ The distance between the centroids of the domestic origin-destination pairs are appended to each record. A file containing these distances must be created exogenously.  A set of values skimmed from the [National Highway Planning Network](http://www.fhwa.dot.gov/planning/processes/tools/nhpn/index.cfm) are included in this package. A function is also provided to create them using the Google Maps API, although because of the volume of interchanges it requires a subscription to do so. 

The results can optionally be saved in a comma-separated value file for later processing, although the reshape_faf_data function returns a data frame that you can then save in whatever format or file system you want. I typically save the resulting data frame in R binary format in order to keep from having to recreate it often, but you could load this package and use that function to download the data from the FAF website every time you use it. The code to do might look like this:

```
faf_source <- ""
faf <- reshape_faf_data(faf_source)
```

In this case the function will use the inter-regional distances provided with the package, process data for the entire country, and simply return the data frame with the resulting values. It can take a long time to convert the entire data set. A more ambitious use might involve defining a set of FAF regions that define a specific area to use modeled or analyzed. A distinction is made between the internal area and its optional halo:

+ The _internal regions_ are those that you want to compile data for or limit analyses to. Another way to think of it is the subset of FAF regions that you want to consider flows originating or terminating in (or both). For example, a statewide model of Oregon might include FAF regions 411, 419, and 532, corresponding to the Portland MSA, remainder of Oregon, and Washington portion of the Portland MSA, respectively. Any FAF record that has domestic origin or destination, or both, within the internal regions will be retained. 
+ The _halo regions_ are those which might contribute through trips within the internal regions. Flows between California and Washington, for example, would likely pass through Oregon, so would be included in the halo. Any record that has both origin and destination in the list of halo zones are retained. Note that those between the halo and internal zone have already been included in the internal zones. Flows between the halo zones and the rest of the country, as well as flows wholly within a single halo zone, will be removed from the data, for they cannot pass through the internal regions.

Both of these definitions are optional. If the internal regions are not defined then the halo regions are superfluous. In that case the entire FAF database (i.e., the entire country) is processed. If the internal regions are specified then the definition of halo regions is optional. They can safely be defined for areas along the coast, but probably not for most states. Flows through Texas, for example, come from all over the nation. If you coded the example shown above it might look something like this:

```
original_data <- "FAF4.2.csv"  # Stored locally to speed up processing
oregon <- modfafr::reshape_faf_data(original_data, internal_faf_regions = c(411, 419, 532),
  halo_faf_regions = c(61:69, 513, 519))
```

The code in this package has been tested with FAF Versions 3.5 and 4.2 flow databases under R 3.3.2 running on macOS Sierra. It has also been successfully tested on a workstation running the same version of R under Windows Server 2016. Please create a new issue if you find problems or compatibility issues.
