USE bearloga;

-- Taxon common names:

DROP TABLE IF EXISTS wikidata_tcn;

CREATE TABLE wikidata_tcn (
  `entity`             string  COMMENT 'Entity ID, including the Q at the beginning',
  `taxon_common_name`  string  COMMENT 'Taxon common name (English value of P1843)'
)
COMMENT 'English taxon common names queried from Wikidata via WDQS'
ROW FORMAT DELIMITED FIELDS TERMINATED BY "\t";

LOAD DATA LOCAL INPATH '/home/bearloga/tmp/taxon_common_names.tsv'
OVERWRITE INTO TABLE wikidata_tcn;

-- Taxon aliases:

DROP TABLE IF EXISTS wikidata_ta;

CREATE TABLE wikidata_ta (
  `entity`  string  COMMENT 'Entity ID, including the Q at the beginning',
  `alias`   string  COMMENT 'Entity alias'
)
COMMENT 'English taxon aliases queried from Wikidata via WDQS'
ROW FORMAT DELIMITED FIELDS TERMINATED BY "\t";

LOAD DATA LOCAL INPATH '/home/bearloga/tmp/taxon_aliases.tsv'
OVERWRITE INTO TABLE wikidata_ta;
