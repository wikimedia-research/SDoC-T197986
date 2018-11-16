USE bearloga;

WITH wd_aliases AS (
  SELECT
    entity,
    CONCAT_WS(', ', COLLECT_SET(DISTINCT(alias))) AS aliases
  FROM wikidata_ta
  GROUP BY entity
), wd_tcns AS (
  SELECT
    entity,
    CONCAT_WS(', ', COLLECT_SET(DISTINCT(taxon_common_name))) AS tcns
  FROM wikidata_tcn
  GROUP BY entity
), wd_taxons AS (
  SELECT IF(wd_aliases.entity IS NULL, wd_tcns.entity, wd_aliases.entity) AS entity
  FROM wd_aliases
  FULL OUTER JOIN wd_tcns ON wd_aliases.entity = wd_tcns.entity
), wd_taxon_terms AS (
  SELECT entity, term_type, term_language, term_text
  FROM wd_taxons
  LEFT JOIN wb_item_terms ON wd_taxons.entity = wb_item_terms.term_full_entity_id
), wd_taxon_collected AS (
  SELECT
    entity, term_type, term_language,
    CONCAT_WS(', ', COLLECT_SET(DISTINCT(term_text))) AS term_texts
  FROM wd_taxon_terms
  GROUP BY entity, term_type, term_language
)
SELECT
  wd_taxon_collected.entity AS entity,
  term_type,
  term_language,
  term_texts,
  aliases,
  tcns
FROM wd_taxon_collected
LEFT JOIN wd_aliases ON wd_taxon_collected.entity = wd_aliases.entity
LEFT JOIN wd_tcns ON wd_taxon_collected.entity = wd_tcns.entity;
