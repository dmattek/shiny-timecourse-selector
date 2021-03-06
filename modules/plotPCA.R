#
# Time Course Inspector: Shiny app for plotting time series data
# Author: Marc-Antoine Jacques
#
# This module is for plotting first 2 PCA components with convex hulls around clusters
# Requires:
# - data as a matrix in wide format for prcomp
# - a table with track IDs matched to clusters
# - a table with clusters matched to colours


## Help text ----
helpText.pca = c(alLearnMore = paste0("<p>Display first two <a href=https://en.wikipedia.org/wiki/Principal_component_analysis target=\"_blank\" title=\"External link\">principal components</a> ",
                                      "coloured by clusters.<p>"))


# UI ----
plotPCAUI =  function(id, label = "Plot PCA.") {
  ns <- NS(id)
  
  tagList(
    actionLink(ns("alLearnMore"), "Learn more"),
    checkboxInput(ns('chBplotStyle'),
                  'Appearance',
                  FALSE),
    conditionalPanel(
      condition = "input.chBplotStyle",
      ns = ns,
      
      fluidRow(
        column(
          2,
          numericInput(
            ns('inPlotPCAwidth'),
            'Width [%]',
            value = 100,
            min = 10,
            width = '100px',
            step = 5
          )
        ),
        column(
          2,
          numericInput(
            ns('inPlotPCAheight'),
            'Height [px]',
            value = PLOTPSDHEIGHT,
            min = 100,
            width = '100px',
            step = 50
          )
        )
      )),
    
    fluidRow(
      column(2,
             actionButton(ns('butPlot'), 'Plot!')),
      column(2,
             checkboxInput(ns('chBplotInt'), 'Interactive'))),
    
    uiOutput(ns('uiPlotPCA')),

    checkboxInput(ns('chBdownload'),
                  'Download',
                  FALSE),
    conditionalPanel(
      condition = "input.chBdownload",
      ns = ns,
      
      downCsvUI(ns('downDataPCA'), ""),
      downPlotUI(ns('downPlotPCA'), "")
    )
  )
}

# Server ----

#' Plot PCA
#'
#' @param input 
#' @param output 
#' @param session 
#' @param inDataWide a matrix in wide format for prcomp.
#' @param inIdWithCl a data.table with track IDs matched to clusters
#' @param inColWithCl a named vector of colours with colours matched to clusters
#' @param inMeth a list with names of distance and linkage methods
#'
#' @return
#' @export
#'
#' @examples
plotPCA = function(input, output, session, 
                      inDataWide,
                      inIdWithCl,
                      inColWithCl,
                      inMeth) {
  
  ns <- session$ns
  
  ## UI rendering ----
  
  ## Processing ----
  
  # Calculate PCA
  # Return a list with a data.table with 3 columns (PC1, PC2, id)
  # and the percentage of explained variance
  calcPCA <- reactive({
    cat(file = stderr(), 'plotPCA:calcPCA \n')
    
    locM = inDataWide()
    
    shiny::validate(
      shiny::need(!is.null(locM),   "Nothing to plot. Load data first!"),
      shiny::need(sum(is.na(locM)), "Cannot calculate PCA in the presence of missing data and/or NAs.")
    )    
    
    if (is.null(locM)) 
      return(NULL)
    
    if (sum(is.na(locM)) > 0)
      return(NULL)
    
    # Calc PCA
    locPCAres = prcomp(locM,
                       scale = T)
    
    # Calc the explained variance
    locVar = locPCAres$sdev^2
    locVarExpl = locVar / sum(locVar)
    
    # convert the result to a data.table; use only first 2 PCs
    locPCAdt = as.data.table(locPCAres$x[, 1:2])
    
    # add row names of the input data as a column
    locPCAdt[,
             (COLID) := rownames(locM)]
    
    
    return(list(pcaDT = locPCAdt, 
                varEx = locVarExpl))
  })
  
  ## Plotting ----
  # Function instead of reactive as per:
  # http://stackoverflow.com/questions/26764481/downloading-png-from-shiny-r
  # This function is used to plot and to downoad a pdf
  
  output$uiPlotPCA = renderUI({
    if (input$chBplotInt) {
      plotlyOutput(
        ns("outPlotPCAint"),
        width = paste0(input$inPlotPCAwidth, '%'),
        height = paste0(input$inPlotPCAheight, 'px'))      
    } else {
      plotOutput(
        ns("outPlotPCA"),
        width = paste0(input$inPlotPCAwidth, '%'),
        height = paste0(input$inPlotPCAheight, 'px'))
    }
  })
  
  
  output$outPlotPCA <- renderPlot({
    
    loc.p = plotClPCA()
    if(is.null(loc.p))
      return(NULL)
    
    return(loc.p)
  })
  
  
  output$outPlotPCAint <- renderPlotly({
    # This is required to avoid
    # "Warning: Error in <Anonymous>: cannot open file 'Rplots.pdf'"
    # When running on a server. Based on:
    # https://github.com/ropensci/plotly/issues/494
    if (names(dev.cur()) != "null device")
      dev.off()
    pdf(NULL)
    
    loc.p = plotClPCA()
    if(is.null(loc.p))
      return(NULL)
    
    loc.p = LOCremoveGeom(loc.p, "GeomPolygon")
    
    return(plotly_build(loc.p))
  })
  
  # PCA visualization of partitioning methods 
  plotClPCA <- function() {
    cat(file = stderr(), 'plotPCA:plotClPCA: in\n')
    
    # make the f-n dependent on the button click
    locBut = input$butPlot
    
    # until clicking the Plot button
    locPCAres = calcPCA()
    locIDwithCl = inIdWithCl()
    locColWithCl = inColWithCl()
    
    shiny::validate(
      shiny::need(!is.null(locPCAres), "Data not loaded or missing values present. Cannot calculate PCA!"),
      shiny::need(!is.null(locIDwithCl), "ID ~ Cl identifiers missing."),
      shiny::need(!is.null(locColWithCl), "Cl ~ Color assignments missing.")
    )
    
    if (is.null(locPCAres))
      return(NULL)
    
    if (is.null(locIDwithCl))
      return(NULL)
    
    if (is.null(locColWithCl))
      return(NULL)
    
    # Add cluster numbers to each track based on track ID
    # When manual tracks are selected for display in the UI,
    # this merge will also result only in those clusters that were selected.
    locPCAres$pcaDT = merge(locPCAres$pcaDT,
                            locIDwithCl,
                            by = COLID)
    
    # Turn cluster numbers into factors for plotting
    locPCAres$pcaDT[,
                    (COLCL) := as.factor(get(COLCL))]
    
    # Calculate convex hulls around clusters
    locCH = locPCAres$pcaDT[,
                            .SD[chull(PC1, PC2)],
                            by = c(COLCL)]
    
    # Scatter plot with convex hulls around clusters
    locP = ggplot(locPCAres$pcaDT,
                  aes_string(x = "PC1",
                             y = "PC2",
                             label = COLID,
                             label2 = COLCL)) +
      geom_point(aes_string(color = COLCL),
                 alpha = 0.5) +
      geom_polygon(data = locCH, 
                   aes_string(color = COLCL,
                              fill = COLCL),
                   size = 0.5,
                   alpha = 0.5) +
      xlab(sprintf("PC1 (%.4g %%)", 100*locPCAres$varEx[1])) +
      ylab(sprintf("PC1 (%.4g %%)", 100*locPCAres$varEx[2])) +
      LOCggplotTheme(in.font.base = PLOTFONTBASE, 
                     in.font.axis.text = PLOTFONTAXISTEXT, 
                     in.font.axis.title = PLOTFONTAXISTITLE, 
                     in.font.strip = PLOTFONTFACETSTRIP, 
                     in.font.legend = PLOTFONTLEGEND) +
      scale_fill_manual(name = "Cluster",
                        values = locColWithCl) +
      scale_colour_manual(name = "Cluster",
                          values = locColWithCl)
    
    return(locP)
  }
  
  ## Download ----
  
  # PCA data - download CSV
  # Note: to make the filename contain the distance and linkage methods,
  # the function downCsv would need to accept the function that generates the name
  # instead of a fixed string with the filename. Similar to the downPlot function.
  callModule(downCsv, "downDataPCA", 
             in.fname = "pca.csv",
             calcPCA()$pcaDT)
  
  # PCA plot - download pdf
  callModule(downPlot, "downPlotPCA", 
             in.fname = createPlotFname,
             plotClPCA, TRUE)
  
  # Create the string for the file name based on distance and linkage methods
  createPlotFname = reactive({
    
    locMeth = inMeth()
    
    paste0('clust_hier_pca_',
           locMeth$diss,
           '_',
           locMeth$link, 
           '.pdf')
  })
  
  ## Pop-overs ----
  addPopover(session, 
             ns("alLearnMore"),
             title = "Principal Component Analysis",
             content = helpText.pca[["alLearnMore"]],
             trigger = "click")
  
}