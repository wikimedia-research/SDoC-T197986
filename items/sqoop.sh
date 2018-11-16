## Takes forever in R+MariaDB:
# # ssh -N stat6 -L 3307:analytics-store.eqiad.wmnet:3306
# library(DBI)
# con <- dbConnect(RMySQL::MySQL(), host = "127.0.0.1", group = "client", dbname = "wikidatawiki", port = 3307)
# all_items_query <- "SELECT
#   term_entity_id, term_type, term_text
# FROM wb_terms
# WHERE term_entity_type = 'item'
#   AND term_type IN('alias', 'label', 'description')
#   AND term_language = 'en'
# "
# all_wikidata_items <- wmf::mysql_read(all_items_query, "wikidatawiki", con = con)
# dbDisconnect(con)

## Modified from https://github.com/wikimedia-research/SDoC-Initial-Metrics/blob/master/T177353/sqoop_to_hdfs.R
# 1. Copy password file via stat1004:
hdfs dfs -cp /user/goransm/mysql-analytics-research-client-pw.txt /user/bearloga/mysql-analytics-research-client-pw.txt
# 2. Try connecting on stat1004:
sqoop list-tables  --password-file /user/bearloga/mysql-analytics-research-client-pw.txt --username research --connect jdbc:mysql://analytics-store.eqiad.wmnet/wikidatawiki
# 3. Setup directory on HDFS:
hdfs dfs -mkdir /user/bearloga/mediawiki_sqoop

# 3. Cleanup any attempts:
hive -e "USE bearloga; DROP TABLE IF EXISTS wb_item_terms;"

# 4. Sqoop English terms with 8 parallel workers to speed up the process
sqoop import --connect jdbc:mysql://analytics-store.eqiad.wmnet/wikidatawiki -m 4 \
  --password-file /user/bearloga/mysql-analytics-research-client-pw.txt \
  --username research \
  --query 'SELECT term_row_id, term_entity_id, term_full_entity_id, term_entity_type, term_type, term_language, term_text FROM wb_terms WHERE $CONDITIONS AND term_entity_type = "item" AND term_type IN("alias", "label", "description") AND term_language = "en"' \
  --split-by term_row_id \
  --as-avrodatafile \
  --target-dir /tmp/wb_item_terms \
  --delete-target-dir

# 5. Import sqoop'd data into Hive:
hive -f wb_item_terms.hql

# 6. Repair table:
hive -e "USE bearloga; SET hive.mapred.mode = nonstrict; MSCK REPAIR TABLE wb_item_terms;"
