/**************************************
 Korea NHIS-NSC: visit_occurrence

 One valid NHID_20 claim becomes one visit. One distinct health-check
 person/year becomes one outpatient visit backed by the GJT SEQ_MASTER key.
***************************************/

;WITH claim_source AS (
	SELECT
		TRY_CONVERT(BIGINT, key_seq) AS visit_occurrence_id,
		TRY_CONVERT(INT, person_id) AS person_id,
		form_cd,
		in_pat_cors_type,
		TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(recu_fr_dt)), ''), 112)
			AS visit_start_date,
		TRY_CONVERT(INT, vscn) AS visit_days,
		TRY_CONVERT(INT, ykiho_id) AS care_site_id,
		CAST(key_seq AS VARCHAR(50)) AS visit_source_value
	FROM @NHISNSC_rawdata.@NHIS_20T
),
valid_claim AS (
	SELECT *
	FROM claim_source
	WHERE visit_occurrence_id IS NOT NULL
	  AND person_id IS NOT NULL
	  AND visit_start_date IS NOT NULL
),
dated_claim AS (
	SELECT
		v.*,
		CASE
			WHEN v.visit_days > 0
			 AND (
				v.form_cd IN ('02', '2', '04', '06', '07', '10', '12')
				OR (
					v.form_cd IN ('03', '3', '05', '08', '8', '09', '9',
						'11', '13', '20', '21', 'ZZ')
					AND v.in_pat_cors_type IN ('11', '21', '31')
				)
			 )
				THEN DATEADD(DAY, v.visit_days - 1, v.visit_start_date)
			ELSE v.visit_start_date
		END AS visit_end_date
	FROM valid_claim v
)
INSERT INTO @NHISNSC_database.VISIT_OCCURRENCE (
	visit_occurrence_id,
	person_id,
	visit_concept_id,
	visit_start_date,
	visit_start_datetime,
	visit_end_date,
	visit_end_datetime,
	visit_type_concept_id,
	provider_id,
	care_site_id,
	visit_source_value,
	visit_source_concept_id
)
SELECT
	v.visit_occurrence_id,
	v.person_id,
	CASE
		WHEN v.form_cd IN ('02', '2', '04', '06', '07', '10', '12')
		 AND v.in_pat_cors_type IN ('11', '21', '31') THEN 9203
		WHEN v.form_cd IN ('02', '2', '04', '06', '07', '10', '12')
		 AND v.in_pat_cors_type NOT IN ('11', '21', '31') THEN 9201
		WHEN v.form_cd IN ('03', '3', '05', '08', '8', '09', '9',
			'11', '13', '20', '21', 'ZZ')
		 AND v.in_pat_cors_type IN ('11', '21', '31') THEN 9203
		WHEN v.form_cd IN ('03', '3', '05', '08', '8', '09', '9',
			'11', '13', '20', '21', 'ZZ')
		 AND v.in_pat_cors_type NOT IN ('11', '21', '31') THEN 9202
		ELSE 0
	END,
	v.visit_start_date,
	NULL,
	v.visit_end_date,
	NULL,
	44818517,
	NULL,
	v.care_site_id,
	v.visit_source_value,
	NULL
FROM dated_claim v
JOIN @NHISNSC_database.OBSERVATION_PERIOD op
  ON op.person_id = v.person_id
 AND v.visit_start_date >= op.observation_period_start_date
 AND v.visit_end_date <= op.observation_period_end_date
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO

;WITH health_year AS (
	SELECT DISTINCT
		TRY_CONVERT(INT, person_id) AS person_id,
		TRY_CONVERT(INT, hchk_year) AS health_year
	FROM @NHISNSC_rawdata.@NHIS_GJ
	WHERE TRY_CONVERT(INT, person_id) IS NOT NULL
	  AND TRY_CONVERT(INT, hchk_year) BETWEEN 1900 AND 2099
)
INSERT INTO @NHISNSC_database.VISIT_OCCURRENCE (
	visit_occurrence_id,
	person_id,
	visit_concept_id,
	visit_start_date,
	visit_start_datetime,
	visit_end_date,
	visit_end_datetime,
	visit_type_concept_id,
	provider_id,
	care_site_id,
	visit_source_value,
	visit_source_concept_id
)
SELECT
	m.master_seq,
	h.person_id,
	9202,
	DATEFROMPARTS(h.health_year, 1, 1),
	NULL,
	DATEFROMPARTS(h.health_year, 1, 1),
	NULL,
	44818517,
	NULL,
	NULL,
	CAST(m.master_seq AS VARCHAR(50)),
	NULL
FROM health_year h
JOIN @NHISNSC_database.SEQ_MASTER m
  ON m.source_table = 'GJT'
 AND m.person_id = h.person_id
 AND TRY_CONVERT(INT, m.hchk_year) = h.health_year
JOIN @NHISNSC_database.OBSERVATION_PERIOD op
  ON op.person_id = h.person_id
 AND DATEFROMPARTS(h.health_year, 1, 1)
     BETWEEN op.observation_period_start_date
         AND op.observation_period_end_date
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO
