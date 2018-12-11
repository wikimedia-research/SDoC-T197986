library(magrittr)
library(glue)
library(purrr)
library(WikidataQueryServiceR)

# Helper functions:
deurl <- function(x) {
  stringi::stri_extract(x, regex = "(Q[0-9]+)$")
}
empty2na <- function(x) {
  if (is.character(x)) {
    y <- x
    y[x == ""] <- NA
    return(y)
  }
  return(x)
}
foo <- function(...) { return(list(list(...))) }
# example usage of foo:
(temp <- data.frame("id" = c(1, 1, 2), "a" = c(0, 1, 0), "b" = c(NA, 0, 1)))
temp %>%
  dplyr::mutate(temp = purrr::pmap(list(a = a, b = b), foo)) %>%
  dplyr::group_by(id) %>%
  dplyr::summarize(l = list(purrr::reduce(temp, c)))
# l[[1]]: list(list(a = 0, b = NA), list(a = 1, b = 0))
# l[[2]]: list(list(a = 0, b = 1))

if (!dir.exists("data")) dir.create("data")

# Some examples to illustrate the problem:
entity_ids <- c(
  "Q311230", # Epiphyllum oxypetalum
  "Q11946202", # butterfly
  "Q28319", # lepidopteros
  "Q3469592", # salamander
  "Q319469"# Salamandridae
)

sparql_query <- "SELECT
  ?item ?itemManualLabel
  (LANG(?itemManualLabel) AS ?language) ?itemDesc
  ?instanceOf ?instanceOfLabel
  ?taxonCommonName ?alias
  ?group ?groupManualLabel
WHERE
{
  BIND(wd:${entity_id} AS ?item).
  ?item wdt:P31 ?instanceOf.
  ?item rdfs:label ?itemManualLabel
  FILTER((LANG(?itemManualLabel)) IN('en', 'es'))
  OPTIONAL{
    ?item wdt:P1843 ?taxonCommonName.
    FILTER (LANG(?taxonCommonName) IN('en', 'es') && LANG(?taxonCommonName) = LANG(?itemManualLabel))
  }
  OPTIONAL{
    ?item schema:description ?itemDesc.
    FILTER(LANG(?itemDesc) IN('en', 'es') && LANG(?itemDesc) = LANG(?itemManualLabel))
  }
  OPTIONAL{
    ?item skos:altLabel ?alias.
    FILTER(LANG(?alias) IN('en', 'es') && LANG(?alias) = LANG(?itemManualLabel))
  }
  OPTIONAL{
    ?item p:P31 [
      pq:P642 ?group;
    ].
    ?group rdfs:label ?groupManualLabel.
    FILTER((LANG(?groupManualLabel)) IN('en', 'es') && LANG(?groupManualLabel) = LANG(?itemManualLabel))
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language '[AUTO_LANGUAGE],en'. }
}
"

wikidata_results <- entity_ids %>%
  purrr::map_chr(~ glue_data(list(entity_id = .x), sparql_query, .open = "${")) %>%
  purrr::map_dfr(query_wikidata, .id = "example") %>%
  dplyr::mutate(item = deurl(item), instanceOf = deurl(instanceOf), group = deurl(group)) %>%
  dplyr::rename(entity = item, label = itemManualLabel, description = itemDesc,
                instance_of = instanceOf, instance_of_label = instanceOfLabel,
                taxon_common_name = taxonCommonName,
                group_label = groupManualLabel)
wikidata_results %>%
  dplyr::arrange(example, language, entity, taxon_common_name) %>%
  dplyr::mutate_all(empty2na) %>%
  readr::write_tsv("data/example.tsv")

# Taxons and their common names:
taxons_query_tcns <- "SELECT ?taxon ?taxonCommonName
WHERE
{
  ?taxon wdt:P31 wd:Q16521.
  ?taxon wdt:P1843 ?taxonCommonName.
  FILTER (LANG(?taxonCommonName) = 'en')
}
"
taxons_query_aliases <- "SELECT ?taxon ?alias
WHERE
{
  ?taxon wdt:P31 wd:Q16521.
  ?taxon skos:altLabel ?alias.
  FILTER (LANG(?alias) = 'en')
}
"

taxons_queries <- list(
  taxon_common_names = taxons_query_tcns,
  aliases = taxons_query_aliases
)

wikidata_taxons <- purrr::map(taxons_queries, query_wikidata) %>%
  purrr::map(~ dplyr::mutate(.x, taxon = deurl(taxon)))

wikidata_taxons$taxon_common_names %>%
  dplyr::rename(entity = taxon, taxon_common_name = taxonCommonName) %>%
  readr::write_tsv("data/taxon_common_names.tsv")

wikidata_taxons$aliases %>%
  dplyr::rename(entity = taxon) %>%
  readr::write_tsv("data/taxon_aliases.tsv")

# Locally: scp -r data/taxon_*.tsv stat4:/home/bearloga/tmp/
#          scp items/wikidata_taxons_load.hql stat4:/home/bearloga/tmp/
# On stat1004: hive -f ~/tmp/wikidata_taxons_load.hql

# Joining sqoop'd wb_terms with wikidata_ta (aliases) & wikidata_tcn (taxon common names):
# On stat1004:
# > cd ~/tmp
# > export HADOOP_HEAPSIZE=1024 && nice ionice hive -S -f wikidata_taxons_query.hql 2> /dev/null | grep -v JAVA_TOOL_OPTIONS | grep -v parquet.hadoop | grep -v WARN: | grep -v :WARN > wikidata_taxons.tsv
# Locally: scp stat4:/home/bearloga/tmp/wikidata_taxons.tsv data/
word2vec <- function(x) {
  return(strsplit(x, ", ")[[1]])
}

wikidata_taxons <- read.delim("data/wikidata_taxons.tsv.gz", sep = "\t", quote = "", as.is = TRUE, header = TRUE, stringsAsFactors = FALSE, na.strings = c("", "NA", "NULL"))
wikidata_taxons %<>%
  tidyr::spread(term_type, term_texts, fill = NA) %>%
  dplyr::select(-`<NA>`) %>%
  dplyr::filter(entity != "entity") %>%
  dplyr::mutate(
    query_aliases = purrr::map(aliases, word2vec),
    query_taxon_common_names = purrr::map(tcns, word2vec),
    sqoop_aliases = purrr::map(alias, word2vec),
    sqoop_label = purrr::map(label, word2vec)
  ) %>%
  dplyr::select(-c(alias, aliases, tcns, label)) %>%
  dplyr::rename(sqoop_description = description)

readr::write_rds(wikidata_taxons, "data/wikidata_taxons_refined.rds", compress = "gz")

# Organisms known by a common name:
commons_query <- "SELECT
  ?item ?itemLabel ?itemDesc
  ?group ?groupLabel
  ?differentFrom ?differentFromLabel
  (GROUP_CONCAT(DISTINCT(?alias);separator=', ') as ?aliases)
WHERE
{
  # BIND(wd:Q11946202 AS ?item). # example: butterfly
  # Instance of group of organisms known by one particular common name:
  ?item wdt:P31 wd:Q55983715.
  # What that group of organisms is (if that information is available):
  OPTIONAL {
    ?item p:P31 [
      pq:P642 ?group;
    ].
  }
  OPTIONAL {
    ?item schema:description ?itemDesc.
    FILTER (LANG(?itemDesc) = 'en')
  }
  # Some entities have a 'different from' statement:
  OPTIONAL {
    ?item wdt:P1889 ?differentFrom.
  }
  # Let's also grab any available aliases:
  OPTIONAL {
    ?item skos:altLabel ?alias.
    FILTER (LANG(?alias) = 'en')
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language '[AUTO_LANGUAGE],en'. }
}
GROUP BY ?item ?itemLabel ?itemDesc ?group ?groupLabel ?differentFrom ?differentFromLabel
"

wikidata_commons <- query_wikidata(commons_query) %>%
  dplyr::mutate(item = deurl(item), group = deurl(group),
                differentFrom = deurl(differentFrom),
                aliases = empty2na(aliases))

# A tibble of aliases:
wikidata_aliases <- wikidata_commons %>%
  dplyr::select(item, label = itemLabel, description = itemDesc, aliases) %>%
  dplyr::arrange(item, label, description, aliases) %>%
  dplyr::distinct() %>%
  dplyr::mutate(label = ifelse(grepl("^Q[0-9]+", label), NA, label),
                aliases = purrr::map(aliases, ~ strsplit(.x, ", ")[[1]]),
                description = ifelse(description == "", NA, description))

# A tibble of "of"-s:
wikidata_groups <- wikidata_commons %>%
  dplyr::select(item, group, groupLabel) %>%
  dplyr::arrange(item, group) %>%
  dplyr::distinct()

wikidata_groups %<>%
  # dplyr::filter(item == "Q11065036") %>%
  dplyr::mutate(temp = purrr::pmap(list(item = group, label = groupLabel), foo)) %>%
  dplyr::group_by(item) %>%
  dplyr::summarize(groups = list(purrr::reduce(temp, c)))

# A tibble of "different from"-s
wikidata_different_froms <- wikidata_commons %>%
  dplyr::select(item, differentFrom, differentFromLabel) %>%
  dplyr::arrange(item, differentFrom) %>%
  dplyr::distinct()

wikidata_different_froms %<>%
  # dplyr::filter(item == "Q10980893") %>%
  dplyr::mutate(temp = purrr::pmap(list(item = differentFrom, label = differentFromLabel), foo)) %>%
  dplyr::group_by(item) %>%
  dplyr::summarize(different_from = list(purrr::reduce(temp, c)))

wikidata_aliases %>%
  dplyr::full_join(wikidata_groups) %>%
  dplyr::full_join(wikidata_different_froms) %>%
  readr::write_rds("data/wikidata_organisms_known_by_common_name.rds", compress = "gz")
