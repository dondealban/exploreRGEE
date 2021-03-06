#' Viz GEE data
#' @description This function allows users to quickly view a previously created get_*() object.
#' @param data A previously created get_* object
#' @param scale A \code{numeric} value indicating scale in meters. 250 (default)
#' @param band A \code{character} indicating what bands/type to use when you have more than one. Can select more than one, e.g. c('Red', 'Green', 'Blue').
#' @param palette \code{character} color palette using colorBrewer format, e.g. "RdBu" (default), "RdYlGn", etc.
#' @param n_pal \code{numeric} indicating levels of colors in palette. 11 is max and (default).
#' @param reverse \code{logical} TRUE/FALSE whether to reverse palette or not, FALSE (default).
#' @param min \code{numeric} indicating lowest value for viewing.
#' @param max \code{numeric} indicating highest value for viewing.
#' @param gamma \code{numeric} gamma correction factor.
#' @param opacity \code{numeric} transparent display value.
#' @note This function uses a scale argument which is used to generate a min and max value for viewing. Because this uses getInfo(), it can take a while
#' depending on the scale. Since this is used for viewing, I would suggest to go bigger on the scale. Also, normalized differences have been hard-coded so that
#' getInfo() doesn't need to be run, e.g. NDVI (min = 0, max = 1). If a user selects more than one band, the first three bands will be overlayed like earth engine. When visualizing a
#' \link[exploreRGEE]{get_diff} object, black is towards 0, red is negative (-) and green/blue is positive (+).
#' @return A leaflet map.
#' @export
#'
#' @examples \dontrun{
#'
#' # Load Libraries
#'
#' library(rgee)
#' rgee::ee_intialize()
#' library(exploreRGEE)
#'
#' # Bring in data
#' huc <- exploreRGEE::huc
#'
#' ld8 <- get_landsat(huc, method = 'ld8', startDate = '2014-01-01',
#'                   endDate = '2018-12-31', c.low = 6, c.high = 11)
#'
#' ld8 %>% viz(scale = 30, band = 'NDVI', palette = 'RdYlGn')
#'
#' # or without scale, when min and max are used scale is irrelevant.
#'
#' ld8 %>% viz(min = 0, max = 1, band = 'NDVI', palette = 'RdYlGn')
#'
#' }
viz <- function(data, scale = 250, band = NULL, palette = "RdBu", n_pal = 11, reverse = FALSE, min = NULL, max = NULL, gamma = NULL, opacity = NULL){


  if(missing(data))stop({"Need a previously created get_* object as 'data'."})

# dissecting the passed get_*() object, not a huge fan of it but it works for now....
  if(class(data)[[1]] == "ee.image.Image"){
    image <- data
    geom <- ee$Geometry$Rectangle(-180, -90, 180, 90)
    method <- NULL
    param <- NULL
    stat <- NULL
    startDate <- NULL
    endDate <- NULL
    bbox <- c(-104, 40)

  } else if (class(data)[[1]] == 'sf'){

    image <- data$geometry
    geom <- setup(data)
    method <- NULL
    param <- 'user FeatureCollection'
    stat <- NULL
    startDate <- NULL
    endDate <- NULL
    bbox <- as.numeric(sf::st_bbox(data))

  } else {
    image <- data$data
    geom <- data$geom
    method <- data$method
    param <- data$param
    stat <- data$stat
    startDate <- data$startDate
    endDate <- data$endDate
    bbox <- data$bbox
  }


    if(is.null(param) & is.null(band))stop({"Need to choose a band name."})

    if(is.null(param)){

     image = image$select(band)
     param <- band

    }

    if(isTRUE(length(param) > 1) | isTRUE(class(data) == 'diff_list')){

      id_tag <- paste0(method, ' - ',stat, "; " ,startDate, " - ", endDate)

      m1 <- leaf_call(data = image, geom = geom, min = min, max = max, palette = NULL,
                      id_tag = id_tag, bbox = bbox, reverse = NULL, n_pal = NULL, bands = param, gamma = gamma, opacity = opacity)

    } else {

      if(class(data)[[1]] == 'sf'){

        id_tag <- paste0(param)
        m1 <- rgee::Map$addLayer(rgee::sf_as_ee(data),visParams = list(), id_tag)

      } else {

      reducers <- rgee::ee$Reducer$min()$combine(
      reducer2 = rgee::ee$Reducer$max(),
      sharedInputs = TRUE
    )

    stats <- image$reduceRegions(
      reducer = reducers,
      collection = geom,
      scale = scale
    )

    #make more dynamic in future maybe?

    if(is.null(min) | is.null(max)){

      min <- stats$getInfo()$features[[1]]$properties$min
      max <- stats$getInfo()$features[[1]]$properties$max

    }



  if(class(data) == 'terrain_list' && param == "complete"){

    mlay <- rgee::Map$addLayer(image$clip(geom), visParams = list(bands = "hillshade", min = 0, max = 256), opacity = 0.45)
    mlay2 <- rgee::Map$addLayer(image$clip(geom), visParams = list(bands = "elevation", min = min, max = max, palette = c('green','yellow','grey','red','black')), opacity = 0.45)
    mlay3 <- rgee::Map$addLayer(image$clip(geom), visParams = list(bands = "slope", min = 0, max = 45, palette = c('white','grey','black','red','yellow')))

    m1 <-  mlay3 + mlay2 + mlay

  } else {

    id_tag <- paste0(method, ' - ', param, ' ',stat, "; " ,startDate, " - ", endDate)

    m1 <- leaf_call(data = image, min = min, max = max, palette = palette,bands = param, id_tag = id_tag, bbox = bbox, geom = geom, reverse = reverse, n_pal = n_pal, gamma = gamma, opacity = opacity)

    }
      }

    }
    print(m1)
}



# Palette function

Pal <- function(pal, reverse, n_pal) {

  if(isTRUE(reverse)){

  rev(RColorBrewer::brewer.pal(n = n_pal ,name = pal))

  } else {

    RColorBrewer::brewer.pal(n = n_pal ,name = pal)
}

}


# leaflet mapping function

leaf_call <- function(data, geom, min, max, palette, id_tag, bbox, reverse, n_pal, bands, gamma, opacity){

    rgee::Map$setCenter(bbox[1], bbox[2], 6)

    GetURL <- function(service, host = "basemap.nationalmap.gov") {
      sprintf("https://%s/arcgis/services/%s/MapServer/WmsServer", host, service)
    }

    grp = "Hydrography"
    opt <- leaflet::WMSTileOptions(format = "image/png", transparent = TRUE)

    if(is.null(palette)){

if(isTRUE(class(data) == 'diff_list')){


  mLayer <- rgee::Map$addLayer(data$clip(geom)$sldStyle(sld_intervals(data, bands)), visParams = list(), id_tag, opacity = opacity)

} else {

  mLayer <- rgee::Map$addLayer(data$clip(geom), visParams = list(bands = bands, min = min, max = max, gamma = gamma), id_tag, opacity = opacity)

}

mLayer

    } else {

    mLayer <- rgee::Map$addLayer(data$clip(geom),
                           visParams = list(min = min, max = max, palette = Pal(palette, reverse, n_pal)), id_tag, opacity = opacity)
}
    m1 <- mLayer %>%
      leaflet::addWMSTiles(GetURL("USGSHydroCached"),
                           group = grp, options = opt, layers = "0") %>%
      leaflet::hideGroup(group = grp) %>%
      leaflet::addLayersControl(baseGroups = c("CartoDB.Positron", "CartoDB.DarkMatter",
                                               "OpenStreetMap", "Esri.WorldImagery", "OpenTopoMap"),
                                overlayGroups = c(id_tag, grp))
}


# Sld styles for diff_list


sld_intervals <- function(data, param){


    if(isTRUE(class(data) == 'met_list')){
  paste0(
    "<RasterSymbolizer>",
    '<ColorMap  type="ramp" extended="false" >',
    '<ColorMapEntry color="#B22222" quantity="-100" />',
    '<ColorMapEntry color="#FF0000" quantity="-25.4" />',
    '<ColorMapEntry color="#000000" quantity="0" />',
    '<ColorMapEntry color="#008000" quantity="25.4" />',
    '<ColorMapEntry color="#0000CD" quantity="100" />',
    "</ColorMap>",
    "</RasterSymbolizer>"
  )
} else {
    paste0(
      "<RasterSymbolizer>",
      '<ColorMap  type="ramp" extended="false" >',
      '<ColorMapEntry color="#B22222" quantity="-0.9" />',
      '<ColorMapEntry color="#FF0000" quantity="-0.2" />',
      '<ColorMapEntry color="#000000" quantity="0" />',
      '<ColorMapEntry color="#008000" quantity="0.2" />',
      '<ColorMapEntry color="#0000CD" quantity="0.9" />',
      "</ColorMap>",
      "</RasterSymbolizer>"
    )

}

}
