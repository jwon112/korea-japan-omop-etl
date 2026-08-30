/**************************************
 --encoding : UTF-8
 --Author: JMPark
 --Date: 2019.02.04
 
@NHISNSC_rawdata : DB containing NHIS National Sample cohort DB
@NHISNSC_database: DB for NHIS-NSC in CDM format

 --Description: Basic information of the version of CDM and source data
 --Generating Table: CDM_SOURCE
***************************************/

DELETE FROM @NHISNSC_database.CDM_SOURCE;

INSERT INTO @NHISNSC_database.CDM_SOURCE
(
    cdm_source_name,
    cdm_source_abbreviation,
    cdm_holder,
    source_description,
    source_documentation_reference,
    cdm_etl_reference,
    cdm_release_date,
    cdm_version,
    vocabulary_version
)
SELECT
    'The National Health Insurance Service - National Sample Cohort',
    'NHIS-NSC',
    'The National Health Insurance Service in South Korea',
    'NHIS National Sample Cohort eligibility, claims, prescriptions, procedures, and health-check data covering 2002 through 2013.',
    'https://nhiss.nhis.or.kr/',
    'korea-japan-omop-etl Python package',
    CONVERT(date, GETDATE()),
    'v5.3.1',
    LEFT(COALESCE(
        (SELECT TOP (1) vocabulary_version
         FROM @NHISNSC_database.VOCABULARY
         WHERE vocabulary_id = 'None'),
        'unknown'
    ), 20);
