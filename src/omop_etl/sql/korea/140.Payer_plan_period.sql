/**************************************
 --encoding : UTF-8
 --Author: JH Cho
 --Date: 2018.09.15
 
 @NHISNSC_rawdata : DB containing NHIS National Sample cohort DB
 @NHISNSC_database : DB for NHIS-NSC in CDM format
 @NHIS_JK: JK table in NHIS NSC
 @NHIS_20T: 20 table in NHIS NSC
 @NHIS_30T: 30 table in NHIS NSC
 @NHIS_40T: 40 table in NHIS NSC
 @NHIS_60T: 60 table in NHIS NSC
 @NHIS_GJ: GJ table in NHIS NSC
 @CONDITION_MAPPINGTABLE : mapping table between KCD and OMOP vocabulary
 @DRUG_MAPPINGTABLE : mapping table between EDI and OMOP vocabulary
 @PROCEDURE_MAPPINGTABLE : mapping table between Korean procedure and OMOP vocabulary
 @DEVICE_MAPPINGTABLE : mapping table between EDI and OMOP vocabulary
 
 --Description: Create PAYER_PLAN_PERIOD table
			   1) payer_plan_period_id = Define person_id as person_id + year
			   2) payer_plan_period_start_date = Define as the 01 Jan of the year 
			   3) payer_plan_period_end_date = Define as the 31 Dec of the year or the death date
 --Generating Table: PAYER_PLAN_PERIOD
***************************************/

/**************************************
 1. Create table
***************************************/ 
/*
CREATE TABLE @NHISNSC_database.PAYER_PLAN_PERIOD
    (
     payer_plan_period_id				BIGINT						NOT NULL , 
     person_id							INTEGER						NOT NULL ,
     payer_plan_period_start_date		DATE						NOT NULL ,
     payer_plan_period_end_date			DATE						NOT NULL ,
     payer_source_value					VARCHAR(50) 				NULL,  
     plan_source_value					VARCHAR(50) 				NULL,  
	 family_source_value				VARCHAR(50) 				NULL   
	)
 ; -- DROP TABLE @ResultDatabaseSchema.PAYER_PLAN_PERIOD
*/ 
 
/**************************************
 2. Insert data 
***************************************/  

;WITH source_year AS (
	SELECT
		TRY_CONVERT(INT, person_id) AS person_id,
		TRY_CONVERT(INT, STND_Y) AS coverage_year,
		CAST(IPSN_TYPE_CD AS VARCHAR(50)) AS plan_source_value,
		ROW_NUMBER() OVER (
			PARTITION BY TRY_CONVERT(INT, person_id), TRY_CONVERT(INT, STND_Y)
			ORDER BY CAST(IPSN_TYPE_CD AS VARCHAR(50))
		) AS row_num
	FROM @NHISNSC_rawdata.@NHIS_JK
	WHERE TRY_CONVERT(INT, person_id) IS NOT NULL
	  AND TRY_CONVERT(INT, STND_Y) BETWEEN 1900 AND 2099
),
coverage AS (
	SELECT
		s.person_id,
		s.coverage_year,
		s.plan_source_value,
		DATEFROMPARTS(s.coverage_year, 1, 1) AS start_date,
		DATEFROMPARTS(s.coverage_year, 12, 31) AS year_end_date
	FROM source_year s
	WHERE s.row_num = 1
)
INSERT INTO @NHISNSC_database.PAYER_PLAN_PERIOD (
	payer_plan_period_id,
	person_id,
	payer_plan_period_start_date,
	payer_plan_period_end_date,
	payer_source_value,
	plan_source_value,
	family_source_value
)
SELECT
	CAST(c.person_id AS BIGINT) * 10000 + c.coverage_year,
	c.person_id,
	c.start_date,
	CASE
		WHEN d.death_date IS NOT NULL AND d.death_date < c.year_end_date
			THEN d.death_date
		ELSE c.year_end_date
	END,
	'National Health Insurance Service',
	c.plan_source_value,
	NULL
FROM coverage c
JOIN @NHISNSC_database.PERSON p
  ON p.person_id = c.person_id
LEFT JOIN @NHISNSC_database.DEATH d
  ON d.person_id = c.person_id
JOIN @NHISNSC_database.OBSERVATION_PERIOD op
  ON op.person_id = c.person_id
 AND c.start_date >= op.observation_period_start_date
 AND CASE
		WHEN d.death_date IS NOT NULL AND d.death_date < c.year_end_date
			THEN d.death_date
		ELSE c.year_end_date
	 END <= op.observation_period_end_date
WHERE d.death_date IS NULL
   OR d.death_date >= c.start_date
;
