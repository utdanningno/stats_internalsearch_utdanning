

Skript for å vaske søketermer fra søkeordlogg for feilstavinger og tagge søketermer fra søkeordlogg med kategori.

Søkelogg lagret i tabellen `uno_solrwidgets_searchlog_history`.

Liste over vanlige feilstavinger av søkeordene lagres `uno_searchlog_search_string_korrekturlest`.

datatabell schema

TODO: Fjerne lokale databasekvalifikatorer.


--
-- Table structure for table `uno_solr_searchlog_search_string_count_raw`
--

DROP TABLE IF EXISTS uno_solr_searchlog_search_string_count_raw;
CREATE TABLE uno_solr_searchlog_search_string_count_raw (
	search_string varchar(255) NOT NULL,
	search_string_orig varchar(255) NOT NULL,
	search_string_normalized varchar(255) NOT NULL,
	search_count int UNSIGNED NOT NULL DEFAULT '0',
	KEY search_string (search_string),
	KEY search_string_orig (search_string_orig),
	KEY search_string_normalized (search_string_normalized)
) ;

DROP TABLE IF EXISTS uno_solr_searchlog_search_string_count;
CREATE TABLE uno_solr_searchlog_search_string_count (
	lnr int UNSIGNED NOT NULL AUTO_INCREMENT,
	search_string varchar(255) NOT NULL,
	search_string_variants varchar(1024) NOT NULL,
	search_count int UNSIGNED NOT NULL,
	search_string_normalized varchar(255) NOT NULL,
	innholdstype varchar(255) NULL DEFAULT '',
	i_ordbok varchar(255)  NULL DEFAULT '',
	noter varchar(255) NOT NULL,
	PRIMARY KEY (lnr),
	KEY (search_string)
) ;






-- telle opp antall søk etter hver søketerm,
-- men fjerne alle uønska spesialtegn fra søketermene
-- filtere bare de som har N forekomster
TRUNCATE uno_solr_searchlog_search_string_count_raw ;
INSERT INTO uno_solr_searchlog_search_string_count_raw
SELECT

	-- søkestreng med spesialtegn fjernet
	LCASE(TRIM(
		REGEXP_REPLACE(
			REGEXP_REPLACE(search_string,
				'([^\,\+\#\/ a-zæøåüöáé0-9\.\-]+)', ' '),
		'[ ]{1,}', ' ')
	)) AS search_string,

	-- backup av vasket søkestreng før vi vasker den med eksterne data
	LCASE(TRIM(
		REGEXP_REPLACE(
			REGEXP_REPLACE(search_string,
				'([^\,\+\#\/ a-zæøåüöáé0-9\.\-]+)', ' '),
		'[ ]{1,}', ' ')
	)) AS search_string_orig,

	-- fjerne alle tegn og mellomrom unntatt bokstaver, tall og +/
	LCASE(
		REGEXP_REPLACE(search_string, '([^\+\/a-zæøåüöáé0-9]+)', '')
	) AS search_string_normalized,

	COUNT(DISTINCT session_id) AS search_count
FROM solr_log.uno_solrwidgets_searchlog_history
WHERE search_type = "plain"
AND CHAR_LENGTH(search_string) > 1
-- grupper på alle unike kombinasjoner av store og små bokstaver
GROUP BY search_string
HAVING COUNT(DISTINCT session_id) > 4
;

-- erstatte søkestrenger med feilstavinger med korrekturleste strenger i search_string-feltet
-- koble på en strengen uten forskjeller i mellomrom (space), komma, bindestreker og lignende.
UPDATE uno_solr_searchlog_search_string_count_raw SOLR, solr_log.uno_searchlog_search_string_korrekturlest KOR SET
	SOLR.search_string = KOR.feilstaving_av,
	SOLR.search_string_normalized = KOR.feilstaving_av
WHERE REGEXP_REPLACE(KOR.search_string, '([^\+\/a-zæøåüöáé0-9]+)', '') = SOLR.search_string_normalized
;



TRUNCATE uno_solr_searchlog_search_string_count ;
INSERT INTO uno_solr_searchlog_search_string_count
SELECT
	NULL AS lnr,
	SUBSTRING_INDEX(
	  GROUP_CONCAT(search_string ORDER BY search_count DESC SEPARATOR ";" )
	  , ";", 1) AS search_string,
	GROUP_CONCAT(DISTINCT search_string_orig ORDER BY search_count DESC SEPARATOR " ; "
	) AS search_string_variants,
	SUM(search_count) AS search_count,
	-- hvis søkeordet har vært endret fra uno_searchlog_search_string_korrekturlest,
	-- sett inn "manuell" som innholdstype
	-- sjekk for case-sensistivitet
	search_string_normalized,
	IF(MD5(
		MAX(`search_string`)) = MD5(MAX(`search_string_orig`)
		), NULL, "manuell") AS innholdstype,
	"" AS noter,
	"" AS i_ordbok
FROM solr_log.uno_solr_searchlog_search_string_count_raw
WHERE CHAR_LENGTH(search_string) > 1
GROUP BY search_string_normalized
HAVING SUM(search_count) > 4
ORDER BY search_count DESC
;



-- Tagge søkeordene etter kategori


-- er søkestrengen et yrke eller utdanningsbeskrivelse?
UPDATE solr_log.uno_solr_searchlog_search_string_count SOLR, uno_data_local.drupal_sammenligning D SET
	SOLR.innholdstype = D.innholdstype,
	SOLR.search_string = D.tittel
WHERE SOLR.search_string = D.tittel
;



-- er søkestrengen et organisasjonsakronym, UiO, NTNU etc
UPDATE solr_log.uno_solr_searchlog_search_string_count SOLR, uno_data_beta.d8_organisasjoner D SET
	SOLR.innholdstype = "org",
	SOLR.search_string = D.org_akronym
WHERE SOLR.search_string = D.org_akronym
AND SOLR.innholdstype = ""
;

-- er søkestrengen et organisasjonsnavn?
UPDATE solr_log.uno_solr_searchlog_search_string_count SOLR, uno_data_beta.d8_organisasjoner D SET
	SOLR.innholdstype = "org",
	SOLR.search_string = D.org_navn
WHERE SOLR.search_string = D.org_navn
AND SOLR.innholdstype = ""
;


-- er søkestrengen en SO-kravkode ?
UPDATE solr_log.uno_solr_searchlog_search_string_count SOLR, uno_data_beta.d8_kravkode D SET
	SOLR.innholdstype = "kravkode",
	SOLR.search_string = D.tittel
WHERE SOLR.search_string = D.kravkode
AND SOLR.innholdstype = ""
;


-- enkeltutdanninger
UPDATE solr_log.uno_solr_searchlog_search_string_count SOLR, uno_data_local.z_ssb_styrk98 D SET
	SOLR.innholdstype = "styrk98"
WHERE SOLR.search_string = SUBSTRING_INDEX(D.tittel, " (", 1)
AND SOLR.innholdstype = ""
;
