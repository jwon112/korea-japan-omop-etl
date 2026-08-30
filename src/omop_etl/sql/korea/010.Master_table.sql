/**************************************
 --encoding : UTF-8
 --Author: SW Lee, JM Park
 --Date: 2018.08.21

 @NHISNSC_raw : DB containing NHIS National Sample cohort DB
 @NHISNSC_database : DB for NHIS-NSC in CDM format
 @NHIS_JK: JK table in NHIS NSC
 @NHIS_20T: 20 table in NHIS NSC
 @NHIS_30T: 30 table in NHIS NSC
 @NHIS_40T: 40 table in NHIS NSC
 @NHIS_60T: 60 table in NHIS NSC
 @NHIS_GJ: GJ table in NHIS NSC
 --Description: Among T1 tables of sample cohort, keep primary keys of 30T, 40T, 60T, GJ, JK table and create table which has unique serial number.
				The serial number is used as primary key of condition, drug, procedure and device tables, and the serial number of GJ table will be used as priomary key of visit_occurrence table.
			   the serial number of JK table will be used as priomary key of observation table.
			   Those keys is created for tracking sample cogort DB in converted CDM DB
 --Generating Table: SEQ_MASTER
***************************************/

/**************************************
 1. Create table
    : serial number(PK), source table, person_id, primary keys of 30T, 40T, 60T, GJ, JK tables
***************************************/
IF OBJECT_ID('@NHISNSC_database.SEQ_MASTER', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT TOP (1) 1 FROM @NHISNSC_database.SEQ_MASTER)
        THROW 51000, 'SEQ_MASTER already contains rows; refusing to rebuild in place.', 1;
    DROP TABLE @NHISNSC_database.SEQ_MASTER;
END;

CREATE TABLE @NHISNSC_database.SEQ_MASTER (
	master_seq		BIGINT	identity(1, 1) PRIMARY KEY,
	source_table	CHAR(3)	NOT NULL, -- 30T = 130, 40T = 140, 60T = 160 GJ ='GJT', JK = 'JKT'
	person_id		INT	NOT NULL,
	key_seq			BIGINT	NULL, -- 30T, 40T, 60T
	seq_no			NUMERIC(4)	NULL, -- 30T, 40T, 60T
	total_cost		FLOAT	NULL, -- 30T, 60T source AMT, reused by COST
	hchk_year		CHAR(4)	NULL, -- GJ
	stnd_y			CHAR(4) NULL, -- JK
)

/*
  The legacy RAW database has no indexes and resides on C:. Build one narrow
  claim-key lookup in the F:-backed target so the three large detail joins do
  not repeatedly hash the full NHID_20 row width.
*/
IF OBJECT_ID('@NHISNSC_database.NHIS_CLAIM_PERSON', 'U') IS NOT NULL
    DROP TABLE @NHISNSC_database.NHIS_CLAIM_PERSON;

SELECT
	CAST(KEY_SEQ AS VARCHAR(50)) AS key_seq,
	TRY_CONVERT(INT, PERSON_ID) AS person_id
INTO @NHISNSC_database.NHIS_CLAIM_PERSON
FROM @NHISNSC_rawdata.@NHIS_20T
WHERE KEY_SEQ IS NOT NULL
  AND TRY_CONVERT(INT, PERSON_ID) IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX UX_NHIS_CLAIM_PERSON_key_seq
	ON @NHISNSC_database.NHIS_CLAIM_PERSON (key_seq);
GO


/**************************************
 2. Insert data of 30T
    : serial number is starting from 3000000001
***************************************/
-- 1) Reset the serial number
DBCC CHECKIDENT('@NHISNSC_database.seq_master', RESEED, 3000000000);

-- 2) Insert data
INSERT INTO @NHISNSC_database.SEQ_MASTER
	(source_table, person_id, key_seq, seq_no, total_cost)
SELECT '130', b.person_id, a.key_seq, a.seq_no, TRY_CONVERT(FLOAT, a.amt)
FROM @NHISNSC_rawdata.@NHIS_30T a
JOIN @NHISNSC_database.NHIS_CLAIM_PERSON b
  ON CAST(a.key_seq AS VARCHAR(50)) = b.key_seq
;

CREATE UNIQUE NONCLUSTERED INDEX UX_SEQ_MASTER_130_source_key
	ON @NHISNSC_database.SEQ_MASTER (key_seq, seq_no)
	INCLUDE (master_seq, person_id, total_cost)
	WHERE source_table = '130';
GO

/**************************************
 3. Insert data of 40T
    : serial number is starting from 4000000001
***************************************/
-- 1) Reset the serial number
DBCC CHECKIDENT('@NHISNSC_database.seq_master', RESEED, 4000000000);

-- 2) Insert data
INSERT INTO @NHISNSC_database.SEQ_MASTER
	(source_table, person_id, key_seq, seq_no)
SELECT '140', b.person_id, a.key_seq, a.seq_no
FROM @NHISNSC_rawdata.@NHIS_40T a
JOIN @NHISNSC_database.NHIS_CLAIM_PERSON b
  ON CAST(a.key_seq AS VARCHAR(50)) = b.key_seq
;

CREATE UNIQUE NONCLUSTERED INDEX UX_SEQ_MASTER_140_source_key
	ON @NHISNSC_database.SEQ_MASTER (key_seq, seq_no)
	INCLUDE (master_seq, person_id)
	WHERE source_table = '140';
GO

/**************************************
 4. Insert data of 60T
    : serial number is starting from 6000000001
***************************************/
-- 1) Reset the serial number
DBCC CHECKIDENT('@NHISNSC_database.seq_master', RESEED, 6000000000);

-- 2) Insert data
INSERT INTO @NHISNSC_database.SEQ_MASTER
	(source_table, person_id, key_seq, seq_no, total_cost)
SELECT '160', b.person_id, a.key_seq, a.seq_no, TRY_CONVERT(FLOAT, a.amt)
FROM @NHISNSC_rawdata.@NHIS_60T a
JOIN @NHISNSC_database.NHIS_CLAIM_PERSON b
  ON CAST(a.key_seq AS VARCHAR(50)) = b.key_seq
;

CREATE UNIQUE NONCLUSTERED INDEX UX_SEQ_MASTER_160_source_key
	ON @NHISNSC_database.SEQ_MASTER (key_seq, seq_no)
	INCLUDE (master_seq, person_id, total_cost)
	WHERE source_table = '160';
GO

/**************************************
 5. Insert data of GJ table
    : serial number is starting from 800000000001
	: visit_occurrence_id is consisted with 12 numbers, match the numbers
***************************************/
-- 1) Reset the serial number
DBCC CHECKIDENT('@NHISNSC_database.seq_master', RESEED, 800000000000);

-- 2) Insert data
INSERT INTO @NHISNSC_database.SEQ_MASTER
	(source_table, person_id, hchk_year)
SELECT 'GJT', person_id, hchk_year
FROM @NHISNSC_rawdata.@NHIS_GJ
GROUP BY hchk_year, person_id
;

CREATE UNIQUE NONCLUSTERED INDEX UX_SEQ_MASTER_GJT_person_year
	ON @NHISNSC_database.SEQ_MASTER (person_id, hchk_year)
	INCLUDE (master_seq)
	WHERE source_table = 'GJT';
GO

/**************************************
 6. Insert data of JK table
	: serial number is starting from 900000000001
**************************************/
-- 1) Reset the serial number
DBCC CHECKIDENT('@NHISNSC_database.seq_master', RESEED, 900000000000);

-- 2) Insert data
INSERT INTO @NHISNSC_database.SEQ_MASTER
	(source_table, person_id, stnd_y)
SELECT 'JKT', person_id, STND_Y
FROM @NHISNSC_rawdata.@NHIS_JK
GROUP BY STND_Y, person_id
;

CREATE UNIQUE NONCLUSTERED INDEX UX_SEQ_MASTER_JKT_person_year
	ON @NHISNSC_database.SEQ_MASTER (person_id, stnd_y)
	INCLUDE (master_seq)
	WHERE source_table = 'JKT';
GO

/**************************************
 7. Deactivate the auto increment serial number
***************************************/
DBCC CHECKIDENT('@NHISNSC_database.seq_master', NORESEED);
