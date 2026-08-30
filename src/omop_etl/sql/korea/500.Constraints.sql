/*********************************************************************************
# Copyright 2014 Observational Health Data Sciences and Informatics
#
#
# Licensed under the Apache License, Version 2.0 (the "License")
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
********************************************************************************/

/************************

 ####### #     # ####### ######      #####  ######  #     #           #######      #####      #####
 #     # ##   ## #     # #     #    #     # #     # ##   ##    #    # #           #     #    #     #  ####  #    #  ####  ##### #####    ##   # #    # #####  ####
 #     # # # # # #     # #     #    #       #     # # # # #    #    # #                 #    #       #    # ##   # #        #   #    #  #  #  # ##   #   #   #
 #     # #  #  # #     # ######     #       #     # #  #  #    #    # ######       #####     #       #    # # #  #  ####    #   #    # #    # # # #  #   #    ####
 #     # #     # #     # #          #       #     # #     #    #    #       # ###       #    #       #    # #  # #      #   #   #####  ###### # #  # #   #        #
 #     # #     # #     # #          #     # #     # #     #     #  #  #     # ### #     #    #     # #    # #   ## #    #   #   #   #  #    # # #   ##   #   #    #
 ####### #     # ####### #           #####  ######  #     #      ##    #####  ###  #####      #####   ####  #    #  ####    #   #    # #    # # #    #   #    ####


sql server script to create foreign key constraints within OMOP common data model, version 5.3.0

last revised: 14-June-2018

author:  Patrick Ryan, Clair Blacketer


*************************/


/************************
*************************
*************************
*************************

Foreign key constraints

*************************
*************************
*************************
************************/


/************************

Standardized vocabulary

************************/

-- Create unified constraint log table in the CDM database (once)
USE @NHISNSC_database;
IF OBJECT_ID('dbo.cdm_constraint_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.cdm_constraint_log (
        log_id          INT IDENTITY(1,1) PRIMARY KEY,
        run_datetime    DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
        table_name      SYSNAME        NOT NULL,
        constraint_name SYSNAME        NOT NULL,
        status          VARCHAR(20)    NOT NULL,   -- 'OK', 'FAIL', 'SKIP'
        message         NVARCHAR(4000) NULL
    );
END;


-- Vocabulary constraints run in the mapping database
use @Mapping_database

BEGIN TRY
    ALTER TABLE concept ADD CONSTRAINT fpk_concept_domain FOREIGN KEY (domain_id)  REFERENCES domain (domain_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept', 'fpk_concept_domain', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept', 'fpk_concept_domain', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept ADD CONSTRAINT fpk_concept_class FOREIGN KEY (concept_class_id)  REFERENCES concept_class (concept_class_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept', 'fpk_concept_class', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept', 'fpk_concept_class', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept ADD CONSTRAINT fpk_concept_vocabulary FOREIGN KEY (vocabulary_id)  REFERENCES vocabulary (vocabulary_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept', 'fpk_concept_vocabulary', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept', 'fpk_concept_vocabulary', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE vocabulary ADD CONSTRAINT fpk_vocabulary_concept FOREIGN KEY (vocabulary_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('vocabulary', 'fpk_vocabulary_concept', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('vocabulary', 'fpk_vocabulary_concept', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE domain ADD CONSTRAINT fpk_domain_concept FOREIGN KEY (domain_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('domain', 'fpk_domain_concept', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('domain', 'fpk_domain_concept', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_class ADD CONSTRAINT fpk_concept_class_concept FOREIGN KEY (concept_class_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_class', 'fpk_concept_class_concept', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_class', 'fpk_concept_class_concept', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_relationship ADD CONSTRAINT fpk_concept_relationship_c_1 FOREIGN KEY (concept_id_1)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_relationship', 'fpk_concept_relationship_c_1', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_relationship', 'fpk_concept_relationship_c_1', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_relationship ADD CONSTRAINT fpk_concept_relationship_c_2 FOREIGN KEY (concept_id_2)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_relationship', 'fpk_concept_relationship_c_2', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_relationship', 'fpk_concept_relationship_c_2', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_relationship ADD CONSTRAINT fpk_concept_relationship_id FOREIGN KEY (relationship_id)  REFERENCES relationship (relationship_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_relationship', 'fpk_concept_relationship_id', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_relationship', 'fpk_concept_relationship_id', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE relationship ADD CONSTRAINT fpk_relationship_concept FOREIGN KEY (relationship_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('relationship', 'fpk_relationship_concept', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('relationship', 'fpk_relationship_concept', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE relationship ADD CONSTRAINT fpk_relationship_reverse FOREIGN KEY (reverse_relationship_id)  REFERENCES relationship (relationship_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('relationship', 'fpk_relationship_reverse', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('relationship', 'fpk_relationship_reverse', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_synonym ADD CONSTRAINT fpk_concept_synonym_concept FOREIGN KEY (concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_synonym', 'fpk_concept_synonym_concept', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_synonym', 'fpk_concept_synonym_concept', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_synonym ADD CONSTRAINT fpk_concept_synonym_language FOREIGN KEY (language_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_synonym', 'fpk_concept_synonym_language', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_synonym', 'fpk_concept_synonym_language', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_ancestor ADD CONSTRAINT fpk_concept_ancestor_concept_1 FOREIGN KEY (ancestor_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_ancestor', 'fpk_concept_ancestor_concept_1', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_ancestor', 'fpk_concept_ancestor_concept_1', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE concept_ancestor ADD CONSTRAINT fpk_concept_ancestor_concept_2 FOREIGN KEY (descendant_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_ancestor', 'fpk_concept_ancestor_concept_2', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('concept_ancestor', 'fpk_concept_ancestor_concept_2', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE source_to_concept_map ADD CONSTRAINT fpk_source_to_concept_map_v_1 FOREIGN KEY (source_vocabulary_id)  REFERENCES vocabulary (vocabulary_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_to_concept_map_v_1', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_to_concept_map_v_1', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE source_to_concept_map ADD CONSTRAINT fpk_source_concept_id FOREIGN KEY (source_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_concept_id', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_concept_id', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE source_to_concept_map ADD CONSTRAINT fpk_source_to_concept_map_v_2 FOREIGN KEY (target_vocabulary_id)  REFERENCES vocabulary (vocabulary_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_to_concept_map_v_2', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_to_concept_map_v_2', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE source_to_concept_map ADD CONSTRAINT fpk_source_to_concept_map_c_1 FOREIGN KEY (target_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_to_concept_map_c_1', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('source_to_concept_map', 'fpk_source_to_concept_map_c_1', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE drug_strength ADD CONSTRAINT fpk_drug_strength_concept_1 FOREIGN KEY (drug_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_concept_1', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_concept_1', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE drug_strength ADD CONSTRAINT fpk_drug_strength_concept_2 FOREIGN KEY (ingredient_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_concept_2', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_concept_2', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE drug_strength ADD CONSTRAINT fpk_drug_strength_unit_1 FOREIGN KEY (amount_unit_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_unit_1', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_unit_1', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE drug_strength ADD CONSTRAINT fpk_drug_strength_unit_2 FOREIGN KEY (numerator_unit_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_unit_2', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_unit_2', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE drug_strength ADD CONSTRAINT fpk_drug_strength_unit_3 FOREIGN KEY (denominator_unit_concept_id)  REFERENCES concept (concept_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_unit_3', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('drug_strength', 'fpk_drug_strength_unit_3', 'FAIL', ERROR_MESSAGE());
END CATCH;

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'cohort_definition')
BEGIN
    BEGIN TRY
        ALTER TABLE cohort_definition ADD CONSTRAINT fpk_cohort_definition_concept FOREIGN KEY (definition_type_concept_id)  REFERENCES concept (concept_id);
        PRINT 'OK: fpk_cohort_definition_concept';
    END TRY
    BEGIN CATCH
        PRINT 'FAIL: fpk_cohort_definition_concept - ' + ERROR_MESSAGE();
    END CATCH;

    BEGIN TRY
        ALTER TABLE cohort_definition ADD CONSTRAINT fpk_cohort_subject_concept FOREIGN KEY (subject_concept_id)  REFERENCES concept (concept_id);
        PRINT 'OK: fpk_cohort_subject_concept';
    END TRY
    BEGIN CATCH
        PRINT 'FAIL: fpk_cohort_subject_concept - ' + ERROR_MESSAGE();
    END CATCH;
END;

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'attribute_definition')
BEGIN
    BEGIN TRY
        ALTER TABLE attribute_definition ADD CONSTRAINT fpk_attribute_type_concept FOREIGN KEY (attribute_type_concept_id)  REFERENCES concept (concept_id);
        PRINT 'OK: fpk_attribute_type_concept';
    END TRY
    BEGIN CATCH
        PRINT 'FAIL: fpk_attribute_type_concept - ' + ERROR_MESSAGE();
    END CATCH;
END;


/**************************

Standardized meta-data

***************************/



/************************

Standardized clinical data

************************/

Use @NHISNSC_database

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_gender_concept'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_gender_concept FOREIGN KEY (gender_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_race_concept'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_race_concept FOREIGN KEY (race_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_ethnicity_concept'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_ethnicity_concept FOREIGN KEY (ethnicity_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_gender_concept_s'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_gender_concept_s FOREIGN KEY (gender_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_race_concept_s'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_race_concept_s FOREIGN KEY (race_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_ethnicity_concept_s'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_ethnicity_concept_s FOREIGN KEY (ethnicity_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_location'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_location FOREIGN KEY (location_id)  REFERENCES location (location_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_provider'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_person_care_site'
      AND parent_object_id = OBJECT_ID('person')
)
BEGIN
    ALTER TABLE person ADD CONSTRAINT fpk_person_care_site FOREIGN KEY (care_site_id)  REFERENCES care_site (care_site_id);
END;


IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_observation_period_person'
      AND parent_object_id = OBJECT_ID('observation_period')
)
BEGIN
    ALTER TABLE observation_period ADD CONSTRAINT fpk_observation_period_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'fpk_observation_period_concept'
      AND parent_object_id = OBJECT_ID('observation_period')
)
BEGIN
    ALTER TABLE observation_period ADD CONSTRAINT fpk_observation_period_concept FOREIGN KEY (period_type_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_specimen_person'
      AND parent_object_id = OBJECT_ID('specimen')
)
BEGIN
    ALTER TABLE specimen ADD CONSTRAINT fpk_specimen_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_specimen_concept'
      AND parent_object_id = OBJECT_ID('specimen')
)
BEGIN
    ALTER TABLE specimen ADD CONSTRAINT fpk_specimen_concept FOREIGN KEY (specimen_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_specimen_type_concept'
      AND parent_object_id = OBJECT_ID('specimen')
)
BEGIN
    ALTER TABLE specimen ADD CONSTRAINT fpk_specimen_type_concept FOREIGN KEY (specimen_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_specimen_unit_concept'
      AND parent_object_id = OBJECT_ID('specimen')
)
BEGIN
    ALTER TABLE specimen ADD CONSTRAINT fpk_specimen_unit_concept FOREIGN KEY (unit_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_specimen_site_concept'
      AND parent_object_id = OBJECT_ID('specimen')
)
BEGIN
    ALTER TABLE specimen ADD CONSTRAINT fpk_specimen_site_concept FOREIGN KEY (anatomic_site_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_specimen_status_concept'
      AND parent_object_id = OBJECT_ID('specimen')
)
BEGIN
    ALTER TABLE specimen ADD CONSTRAINT fpk_specimen_status_concept FOREIGN KEY (disease_status_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_death_person'
      AND parent_object_id = OBJECT_ID('death')
)
BEGIN
    ALTER TABLE death ADD CONSTRAINT fpk_death_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_death_type_concept'
      AND parent_object_id = OBJECT_ID('death')
)
BEGIN
    ALTER TABLE death ADD CONSTRAINT fpk_death_type_concept FOREIGN KEY (death_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_death_cause_concept'
      AND parent_object_id = OBJECT_ID('death')
)
BEGIN
    ALTER TABLE death ADD CONSTRAINT fpk_death_cause_concept FOREIGN KEY (cause_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_death_cause_concept_s'
      AND parent_object_id = OBJECT_ID('death')
)
BEGIN
    ALTER TABLE death ADD CONSTRAINT fpk_death_cause_concept_s FOREIGN KEY (cause_source_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_person'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_type_concept'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_type_concept FOREIGN KEY (visit_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_provider'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_care_site'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_care_site FOREIGN KEY (care_site_id)  REFERENCES care_site (care_site_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_concept_s'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_concept_s FOREIGN KEY (visit_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_admitting_s'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_admitting_s FOREIGN KEY (admitting_source_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_discharge'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_discharge FOREIGN KEY (discharge_to_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_preceding'
      AND parent_object_id = OBJECT_ID('visit_occurrence')
)
BEGIN
    ALTER TABLE visit_occurrence ADD CONSTRAINT fpk_visit_preceding FOREIGN KEY (preceding_visit_occurrence_id) REFERENCES visit_occurrence (visit_occurrence_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_person'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_type_concept'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_type_concept FOREIGN KEY (visit_detail_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_provider'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_care_site'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_care_site FOREIGN KEY (care_site_id)  REFERENCES care_site (care_site_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_concept_s'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_concept_s FOREIGN KEY (visit_detail_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_admitting_s'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_admitting_s FOREIGN KEY (admitting_source_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_discharge'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_discharge FOREIGN KEY (discharge_to_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_preceding'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_preceding FOREIGN KEY (preceding_visit_detail_id) REFERENCES visit_detail (visit_detail_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_v_detail_parent'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpk_v_detail_parent FOREIGN KEY (visit_detail_parent_id) REFERENCES visit_detail (visit_detail_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpd_v_detail_visit'
      AND parent_object_id = OBJECT_ID('visit_detail')
)
BEGIN
    ALTER TABLE visit_detail ADD CONSTRAINT fpd_v_detail_visit FOREIGN KEY (visit_occurrence_id) REFERENCES visit_occurrence (visit_occurrence_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_person'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_concept'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_concept FOREIGN KEY (procedure_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_type_concept'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_type_concept FOREIGN KEY (procedure_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_modifier'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_modifier FOREIGN KEY (modifier_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_provider'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_visit'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_procedure_concept_s'
      AND parent_object_id = OBJECT_ID('procedure_occurrence')
)
BEGIN
    ALTER TABLE procedure_occurrence ADD CONSTRAINT fpk_procedure_concept_s FOREIGN KEY (procedure_source_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_person'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_concept'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_concept FOREIGN KEY (drug_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_type_concept'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_type_concept FOREIGN KEY (drug_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_route_concept'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_route_concept FOREIGN KEY (route_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_provider'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_visit'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_concept_s'
      AND parent_object_id = OBJECT_ID('drug_exposure')
)
BEGIN
    ALTER TABLE drug_exposure ADD CONSTRAINT fpk_drug_concept_s FOREIGN KEY (drug_source_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_device_person'
      AND parent_object_id = OBJECT_ID('device_exposure')
)
BEGIN
    ALTER TABLE device_exposure ADD CONSTRAINT fpk_device_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_device_concept'
      AND parent_object_id = OBJECT_ID('device_exposure')
)
BEGIN
    ALTER TABLE device_exposure ADD CONSTRAINT fpk_device_concept FOREIGN KEY (device_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_device_type_concept'
      AND parent_object_id = OBJECT_ID('device_exposure')
)
BEGIN
    ALTER TABLE device_exposure ADD CONSTRAINT fpk_device_type_concept FOREIGN KEY (device_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_device_provider'
      AND parent_object_id = OBJECT_ID('device_exposure')
)
BEGIN
    ALTER TABLE device_exposure ADD CONSTRAINT fpk_device_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_device_visit'
      AND parent_object_id = OBJECT_ID('device_exposure')
)
BEGIN
    ALTER TABLE device_exposure ADD CONSTRAINT fpk_device_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_device_concept_s'
      AND parent_object_id = OBJECT_ID('device_exposure')
)
BEGIN
    ALTER TABLE device_exposure ADD CONSTRAINT fpk_device_concept_s FOREIGN KEY (device_source_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_person'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_concept'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_concept FOREIGN KEY (condition_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_type_concept'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_type_concept FOREIGN KEY (condition_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_provider'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_visit'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_concept_s'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_concept_s FOREIGN KEY (condition_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_status_concept'
      AND parent_object_id = OBJECT_ID('condition_occurrence')
)
BEGIN
    ALTER TABLE condition_occurrence ADD CONSTRAINT fpk_condition_status_concept FOREIGN KEY (condition_status_concept_id) REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_person'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_concept'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_concept FOREIGN KEY (measurement_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_type_concept'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_type_concept FOREIGN KEY (measurement_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_operator'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_operator FOREIGN KEY (operator_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_value'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_value FOREIGN KEY (value_as_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_unit'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_unit FOREIGN KEY (unit_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_provider'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_visit'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_measurement_concept_s'
      AND parent_object_id = OBJECT_ID('measurement')
)
BEGIN
    ALTER TABLE measurement ADD CONSTRAINT fpk_measurement_concept_s FOREIGN KEY (measurement_source_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_person'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_note_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_type_concept'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_note_type_concept FOREIGN KEY (note_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_class_concept'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_note_class_concept FOREIGN KEY (note_class_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_encoding_concept'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_note_encoding_concept FOREIGN KEY (encoding_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_language_concept'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_language_concept FOREIGN KEY (language_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_provider'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_note_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_visit'
      AND parent_object_id = OBJECT_ID('note')
)
BEGIN
    ALTER TABLE note ADD CONSTRAINT fpk_note_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_nlp_note'
      AND parent_object_id = OBJECT_ID('note_nlp')
)
BEGIN
    ALTER TABLE note_nlp ADD CONSTRAINT fpk_note_nlp_note FOREIGN KEY (note_id) REFERENCES note (note_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_nlp_section_concept'
      AND parent_object_id = OBJECT_ID('note_nlp')
)
BEGIN
    ALTER TABLE note_nlp ADD CONSTRAINT fpk_note_nlp_section_concept FOREIGN KEY (section_concept_id) REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_note_nlp_concept'
      AND parent_object_id = OBJECT_ID('note_nlp')
)
BEGIN
    ALTER TABLE note_nlp ADD CONSTRAINT fpk_note_nlp_concept FOREIGN KEY (note_nlp_concept_id) REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_person'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_concept'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    BEGIN TRY
        ALTER TABLE observation ADD CONSTRAINT fpk_observation_concept
            FOREIGN KEY (observation_concept_id)  REFERENCES concept (concept_id);

        INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
            (table_name, constraint_name, status, message)
        VALUES ('observation', 'fpk_observation_concept', 'OK', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
            (table_name, constraint_name, status, message)
        VALUES ('observation', 'fpk_observation_concept', 'FAIL', ERROR_MESSAGE());
    END CATCH;
END
ELSE
BEGIN
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('observation', 'fpk_observation_concept', 'SKIP', 'Already exists');
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_type_concept'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_type_concept FOREIGN KEY (observation_type_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_value'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_value FOREIGN KEY (value_as_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_qualifier'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_qualifier FOREIGN KEY (qualifier_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_unit'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_unit FOREIGN KEY (unit_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_provider'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_provider FOREIGN KEY (provider_id)  REFERENCES provider (provider_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_visit'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_visit FOREIGN KEY (visit_occurrence_id)  REFERENCES visit_occurrence (visit_occurrence_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_observation_concept_s'
      AND parent_object_id = OBJECT_ID('observation')
)
BEGIN
    ALTER TABLE observation ADD CONSTRAINT fpk_observation_concept_s FOREIGN KEY (observation_source_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_fact_domain_1'
      AND parent_object_id = OBJECT_ID('fact_relationship')
)
BEGIN
    ALTER TABLE fact_relationship ADD CONSTRAINT fpk_fact_domain_1 FOREIGN KEY (domain_concept_id_1)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_fact_domain_2'
      AND parent_object_id = OBJECT_ID('fact_relationship')
)
BEGIN
    ALTER TABLE fact_relationship ADD CONSTRAINT fpk_fact_domain_2 FOREIGN KEY (domain_concept_id_2)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_fact_relationship'
      AND parent_object_id = OBJECT_ID('fact_relationship')
)
BEGIN
    ALTER TABLE fact_relationship ADD CONSTRAINT fpk_fact_relationship FOREIGN KEY (relationship_concept_id)  REFERENCES concept (concept_id);
END;


/************************

Standardized health system data

************************/

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_care_site_location'
      AND parent_object_id = OBJECT_ID('care_site')
)
BEGIN
    BEGIN TRY
        ALTER TABLE care_site ADD CONSTRAINT fpk_care_site_location FOREIGN KEY (location_id)  REFERENCES location (location_id);

        INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
            (table_name, constraint_name, status, message)
        VALUES ('care_site', 'fpk_care_site_location', 'OK', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
            (table_name, constraint_name, status, message)
        VALUES ('care_site', 'fpk_care_site_location', 'FAIL', ERROR_MESSAGE());
    END CATCH;
END
ELSE
BEGIN
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('care_site', 'fpk_care_site_location', 'SKIP', 'Already exists');
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_care_site_place'
      AND parent_object_id = OBJECT_ID('care_site')
)
BEGIN
    BEGIN TRY
        ALTER TABLE care_site ADD CONSTRAINT fpk_care_site_place FOREIGN KEY (place_of_service_concept_id)  REFERENCES concept (concept_id);

        INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
            (table_name, constraint_name, status, message)
        VALUES ('care_site', 'fpk_care_site_place', 'OK', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
            (table_name, constraint_name, status, message)
        VALUES ('care_site', 'fpk_care_site_place', 'FAIL', ERROR_MESSAGE());
    END CATCH;
END
ELSE
BEGIN
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('care_site', 'fpk_care_site_place', 'SKIP', 'Already exists');
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_provider_specialty'
      AND parent_object_id = OBJECT_ID('provider')
)
BEGIN
    ALTER TABLE provider ADD CONSTRAINT fpk_provider_specialty FOREIGN KEY (specialty_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_provider_care_site'
      AND parent_object_id = OBJECT_ID('provider')
)
BEGIN
    ALTER TABLE provider ADD CONSTRAINT fpk_provider_care_site FOREIGN KEY (care_site_id)  REFERENCES care_site (care_site_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_provider_gender'
      AND parent_object_id = OBJECT_ID('provider')
)
BEGIN
    ALTER TABLE provider ADD CONSTRAINT fpk_provider_gender FOREIGN KEY (gender_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_provider_specialty_s'
      AND parent_object_id = OBJECT_ID('provider')
)
BEGIN
    ALTER TABLE provider ADD CONSTRAINT fpk_provider_specialty_s FOREIGN KEY (specialty_source_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_provider_gender_s'
      AND parent_object_id = OBJECT_ID('provider')
)
BEGIN
    ALTER TABLE provider ADD CONSTRAINT fpk_provider_gender_s FOREIGN KEY (gender_source_concept_id)  REFERENCES concept (concept_id);
END;


/************************

Standardized health economics

************************/

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_payer_plan_period'
      AND parent_object_id = OBJECT_ID('payer_plan_period')
)
BEGIN
    ALTER TABLE payer_plan_period ADD CONSTRAINT fpk_payer_plan_period FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_cost_currency'
      AND parent_object_id = OBJECT_ID('cost')
)
BEGIN
    ALTER TABLE cost ADD CONSTRAINT fpk_visit_cost_currency FOREIGN KEY (currency_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_visit_cost_period'
      AND parent_object_id = OBJECT_ID('cost')
)
BEGIN
    ALTER TABLE cost ADD CONSTRAINT fpk_visit_cost_period FOREIGN KEY (payer_plan_period_id)  REFERENCES payer_plan_period (payer_plan_period_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drg_concept'
      AND parent_object_id = OBJECT_ID('cost')
)
BEGIN
    ALTER TABLE cost ADD CONSTRAINT fpk_drg_concept FOREIGN KEY (drg_concept_id) REFERENCES concept (concept_id);
END;

/************************

Standardized derived elements

************************/


--ALTER TABLE cohort ADD CONSTRAINT fpk_cohort_definition FOREIGN KEY (cohort_definition_id)  REFERENCES cohort_definition (cohort_definition_id);


BEGIN TRY
    ALTER TABLE cohort_attribute ADD CONSTRAINT fpk_ca_cohort_definition FOREIGN KEY (cohort_definition_id)  REFERENCES cohort_definition (cohort_definition_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('cohort_attribute', 'fpk_ca_cohort_definition', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('cohort_attribute', 'fpk_ca_cohort_definition', 'FAIL', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    ALTER TABLE cohort_attribute ADD CONSTRAINT fpk_ca_attribute_definition FOREIGN KEY (attribute_definition_id)  REFERENCES attribute_definition (attribute_definition_id);
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('cohort_attribute', 'fpk_ca_attribute_definition', 'OK', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @NHISNSC_database.dbo.cdm_constraint_log
        (table_name, constraint_name, status, message)
    VALUES ('cohort_attribute', 'fpk_ca_attribute_definition', 'FAIL', ERROR_MESSAGE());
END CATCH;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_ca_value'
      AND parent_object_id = OBJECT_ID('cohort_attribute')
)
BEGIN
    ALTER TABLE cohort_attribute ADD CONSTRAINT fpk_ca_value FOREIGN KEY (value_as_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_era_person'
      AND parent_object_id = OBJECT_ID('drug_era')
)
BEGIN
    ALTER TABLE drug_era ADD CONSTRAINT fpk_drug_era_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_drug_era_concept'
      AND parent_object_id = OBJECT_ID('drug_era')
)
BEGIN
    ALTER TABLE drug_era ADD CONSTRAINT fpk_drug_era_concept FOREIGN KEY (drug_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_dose_era_person'
      AND parent_object_id = OBJECT_ID('dose_era')
)
BEGIN
    ALTER TABLE dose_era ADD CONSTRAINT fpk_dose_era_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_dose_era_concept'
      AND parent_object_id = OBJECT_ID('dose_era')
)
BEGIN
    ALTER TABLE dose_era ADD CONSTRAINT fpk_dose_era_concept FOREIGN KEY (drug_concept_id)  REFERENCES concept (concept_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_dose_era_unit_concept'
      AND parent_object_id = OBJECT_ID('dose_era')
)
BEGIN
    ALTER TABLE dose_era ADD CONSTRAINT fpk_dose_era_unit_concept FOREIGN KEY (unit_concept_id)  REFERENCES concept (concept_id);
END;


IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_era_person'
      AND parent_object_id = OBJECT_ID('condition_era')
)
BEGIN
    ALTER TABLE condition_era ADD CONSTRAINT fpk_condition_era_person FOREIGN KEY (person_id)  REFERENCES person (person_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'fpk_condition_era_concept'
      AND parent_object_id = OBJECT_ID('condition_era')
)
BEGIN
    ALTER TABLE condition_era ADD CONSTRAINT fpk_condition_era_concept FOREIGN KEY (condition_concept_id)  REFERENCES concept (concept_id);
END;


/************************
*************************
*************************
*************************

Unique constraints

*************************
*************************
*************************
************************/

Use @Mapping_database

ALTER TABLE concept_synonym ADD CONSTRAINT uq_concept_synonym UNIQUE (concept_id, concept_synonym_name, language_concept_id);