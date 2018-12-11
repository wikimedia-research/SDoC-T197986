USE bearloga;

DROP TABLE IF EXISTS bearloga.wb_terms;

CREATE EXTERNAL TABLE `bearloga.wb_terms` (
  `term_row_id`          bigint  COMMENT 'Primary key, see mw:Wikibase/Schema/wb_terms',
  `term_entity_id`       bigint  COMMENT 'Entity ID, missing the Q at the beginning',
  `term_full_entity_id`  string  COMMENT 'Entity ID, including the Q at the beginning',
  `term_entity_type`     string  COMMENT 'Entity type, e.g. "item"',
  `term_language`        string  COMMENT 'Language code',
  `term_type`            string  COMMENT 'One of: label, description, alias',
  `term_text`            string  COMMENT 'Text, should be in English',
  `term_search_key`      string  COMMENT 'Same as term_text but normalized for search, e.g. all lowercase',
  `term_weight`          float   COMMENT 'Search weight?'
)
COMMENT
  'Labels, descriptions, and aliases for Wikidata entities'
ROW FORMAT SERDE
  'org.apache.hadoop.hive.serde2.avro.AvroSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.avro.AvroContainerInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.avro.AvroContainerOutputFormat'
LOCATION
  'hdfs://analytics-hadoop/tmp/wb_terms'
;
