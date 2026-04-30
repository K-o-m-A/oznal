FROM rocker/r-ver:4.5.3

ENV R_REPOS="https://packagemanager.posit.co/cran/__linux__/noble/2026-04-15"

RUN apt-get update && apt-get install -y --no-install-recommends \
    pandoc \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libjpeg-dev \
    libuv1-dev \
    libwebpmux3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.R /app/requirements.R
RUN Rscript -e "options(repos = c(CRAN = Sys.getenv('R_REPOS'))); source('/app/requirements.R')"

COPY . /app

EXPOSE 3838

CMD ["Rscript", "-e", "cat('\\nOpen http://localhost:3838 in your browser\\n\\n'); shiny::runApp('/app/app.R', host='0.0.0.0', port=3838, launch.browser=FALSE, quiet=TRUE)"]
