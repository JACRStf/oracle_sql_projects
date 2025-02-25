CREATE OR REPLACE PROCEDURE bolinf.xxwsb_acct_plan_om_det_invstgprc(X_ERRBUF              OUT VARCHAR2,
																	X_RETCODE             OUT NUMBER) IS
-- **********************************************************************************************
-- * PROCEDURE: 	BOLINF.XXWSB_ACCT_PLAN_OM_DET_INVSTGPRC                                     *
-- * Date:      	08-AUG-2024                                                                 *
-- * Purpose:   	PROCEDURE to load Acct Plan Invoice Data into Stg table                     *
-- *------------------------------------------------------------------------------------        *
-- * REVISIONS:                                                                                 *
-- *                                                                                            *
-- * Date         Person              Changes Made                                              *
-- * ----------   -----------------   -------------------------------------------------         *
-- * 08-Aug-2024  Ravi M    		  Initial Version 			                         		*
-- **********************************************************************************************
    l_init_count NUMBER;
    l_ydate      NUMBER;
	l_del_rec	 NUMBER;
	L_STG_YEAR_CNT	NUMBER;
	l_present_cnt	NUMBER;
	l_creation_date	DATE;
	l_created_by	VARCHAR2(25);
	l_last_updated_date	DATE;
	l_last_updated_by	VARCHAR2(25);
BEGIN
	fnd_file.put_line(fnd_file.log, 'Data Load Stage Start.. ');
    BEGIN
        SELECT
            COUNT(*)
        INTO l_init_count
        FROM
            bolinf.xxwsb_acct_plan_om_det_invstg;
    END;
	
	BEGIN
		SELECT  user_name into l_created_by  from fnd_user where user_id = fnd_global.user_id;
	EXCEPTION
		WHEN OTHERS THEN
			l_created_by := NULL;
	END;
	
	fnd_file.put_line(fnd_file.log, 'Historical Years Records count.. '||l_init_count);
	DBMS_OUTPUT.PUT_LINE('Historical Years Records count.. '||l_init_count);
	
    IF l_init_count = 0 THEN
	
	FOR C_STG in (SELECT DISTINCT
						EXTRACT(YEAR FROM summary_date) STG_YEAR
					FROM
						bolinf.xxwsb_account_plan_om_detail
					WHERE EXTRACT(YEAR FROM summary_date) in (2019,2020,2021,2022,2023,2024)) LOOP
        BEGIN
			DBMS_OUTPUT.PUT_LINE('STG_YEAR '||C_STG.STG_YEAR);

			BEGIN
			SELECT COUNT(*) INTO L_STG_YEAR_CNT FROM
				(SELECT
                    xapod.*,
                    (
                        SELECT
                            xapoc.segment1
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_co,
                    (
                        SELECT
                            xapoc.segment2
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_lob,
                    (
                        SELECT
                            xapoc.segment3
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_loc,
                    (
                        SELECT
                            xapoc.segment4
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_dept,
                    (
                        SELECT
                            xapoc.segment5
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_gl,
                    (
                        SELECT
                            xapor.segment1
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_co,
                    (
                        SELECT
                            xapor.segment2
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_lob,
                    (
                        SELECT
                            xapor.segment3
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_loc,
                    (
                        SELECT
                            xapor.segment4
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_dept,
                    (
                        SELECT
                            xapor.segment5
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_gl,
                    (
                        SELECT
                            LISTAGG(xapoi.internal_ship_from, ', ') WITHIN GROUP(
                            ORDER BY
                                xapoi.internal_ship_from
                            )
                        FROM
                            bolinf.xxwsb_account_plan_om_internal xapoi
                        WHERE
                            xapoi.order_line_id = xapod.order_line_id
                    )               manufacturing_plant,
                    upper(customer) customername
                FROM
                    bolinf.xxwsb_account_plan_om_detail xapod
                WHERE
                    EXTRACT(YEAR FROM xapod.summary_date) = C_STG.STG_YEAR);
			END;

			fnd_file.put_line(fnd_file.log, 'Year Records Count.. '||C_STG.STG_YEAR||' - '||L_STG_YEAR_CNT);
			DBMS_OUTPUT.PUT_LINE('Records Count.. -'||C_STG.STG_YEAR||' - '||L_STG_YEAR_CNT);
		
            INSERT INTO bolinf.xxwsb_acct_plan_om_det_invstg (
                query_identifier,
                customer_trx_line_id,
                summary_date,
                operating_unit,
                line_of_business,
                rev_gl_account,
                territory,
                sales_person,
                cust_account_id,
                account_number,
                customer,
                order_number,
                order_line,
                order_line_type,
                invoice_type,
                invoice_date,
                invoice_number,
                invoice_line,
                inv_line_type,
                line_desc,
                gl_date,
                warehouse,
                item_number,
                inventory_category1,
                inventory_category2,
                inventory_category3,
                inventory_category4,
                quantity,
                uom_code,
                unit_standard_price,
                unit_selling_price,
                extended_amount,
                om_freight,
                om_credits,
                om_rev,
                om_replacements,
                om_cogs,
                om_gross_profit,
                om_gross_profit_percent,
                creation_date,
                request_id,
                market_quantity,
                market_uom,
                om_material,
                om_material_overhead,
                om_resource,
                om_outside_processing,
                om_overhead,
                order_line_id,
                rev_co,
                rev_lob,
                rev_loc,
                rev_dept,
                rev_gl,
                cogs_co,
                cogs_lob,
                cogs_loc,
                cogs_dept,
                cogs_gl,
                manufacturing_plant,
                customername,
				  load_creation_date,
				  created_by,
				  last_updated_date,
				  last_updated_by
            )
                SELECT
                    xapod.*,
                    (
                        SELECT
                            xapoc.segment1
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_co,
                    (
                        SELECT
                            xapoc.segment2
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_lob,
                    (
                        SELECT
                            xapoc.segment3
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_loc,
                    (
                        SELECT
                            xapoc.segment4
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_dept,
                    (
                        SELECT
                            xapoc.segment5
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_gl,
                    (
                        SELECT
                            xapor.segment1
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_co,
                    (
                        SELECT
                            xapor.segment2
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_lob,
                    (
                        SELECT
                            xapor.segment3
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_loc,
                    (
                        SELECT
                            xapor.segment4
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_dept,
                    (
                        SELECT
                            xapor.segment5
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_gl,
                    (
                        SELECT
                            LISTAGG(xapoi.internal_ship_from, ', ') WITHIN GROUP(
                            ORDER BY
                                xapoi.internal_ship_from
                            )
                        FROM
                            bolinf.xxwsb_account_plan_om_internal xapoi
                        WHERE
                            xapoi.order_line_id = xapod.order_line_id
                    )               manufacturing_plant,
                    upper(customer) customername,
					sysdate,
					l_created_by,
					sysdate,
					l_created_by --l_last_updated_by
                FROM
                    bolinf.xxwsb_account_plan_om_detail xapod
                WHERE
                    EXTRACT(YEAR FROM xapod.summary_date) = C_STG.STG_YEAR;
        EXCEPTION
            WHEN OTHERS THEN
                fnd_file.put_line(fnd_file.log, 'Error - Data Load Initial Ingetion.. '||C_STG.STG_YEAR||' - '||SQLCODE||' - '||SQLERRM);
				DBMS_OUTPUT.PUT_LINE('Error - Data Load Initial Ingetion.. Year'||C_STG.STG_YEAR||' - '||SQLCODE||' - '||SQLERRM);
        END;
		COMMIT;
		
	END LOOP;
        
    ELSE
		
		DBMS_OUTPUT.PUT_LINE('Stage Table Has Historical Data ..');
		
		SELECT COUNT(*) INTO l_del_rec FROM bolinf.xxwsb_acct_plan_om_det_invstg
		WHERE
			trunc(summary_date,'MM') = trunc(sysdate, 'MM')
			AND trunc(summary_date,'YY') = trunc(sysdate, 'YY');
				
		fnd_file.put_line(fnd_file.log, ' Delete Records Count Present Period ..'||l_del_rec);		
		DBMS_OUTPUT.PUT_LINE(' Delete Records Count Present Period ..'||l_del_rec);
		
        BEGIN
            DELETE FROM bolinf.xxwsb_acct_plan_om_det_invstg
            WHERE
				trunc(summary_date,'MM') = trunc(sysdate, 'MM')
				AND trunc(summary_date,'YY') = trunc(sysdate, 'YY');

        EXCEPTION
            WHEN OTHERS THEN
                fnd_file.put_line(fnd_file.log, 'Error while Delete the Present Period Transactions.. '||SQLCODE||' - '||SQLERRM);
        END;

        COMMIT;
        BEGIN
		
			BEGIN
				SELECT count(*) INTO l_present_cnt
				FROM
					(SELECT
						xapod.*,
						(
							SELECT
								xapoc.segment1
							FROM
								bolinf.xxwsb_account_plan_om_cogs xapoc
							WHERE
								xapoc.order_line_id = xapod.order_line_id
						)               rev_co,
						(
							SELECT
								xapoc.segment2
							FROM
								bolinf.xxwsb_account_plan_om_cogs xapoc
							WHERE
								xapoc.order_line_id = xapod.order_line_id
						)               rev_lob,
						(
							SELECT
								xapoc.segment3
							FROM
								bolinf.xxwsb_account_plan_om_cogs xapoc
							WHERE
								xapoc.order_line_id = xapod.order_line_id
						)               rev_loc,
						(
							SELECT
								xapoc.segment4
							FROM
								bolinf.xxwsb_account_plan_om_cogs xapoc
							WHERE
								xapoc.order_line_id = xapod.order_line_id
						)               rev_dept,
						(
							SELECT
								xapoc.segment5
							FROM
								bolinf.xxwsb_account_plan_om_cogs xapoc
							WHERE
								xapoc.order_line_id = xapod.order_line_id
						)               rev_gl,
						(
							SELECT
								xapor.segment1
							FROM
								bolinf.xxwsb_account_plan_om_rev xapor
							WHERE
								xapor.customer_trx_line_id = xapod.customer_trx_line_id
						)               cogs_co,
						(
							SELECT
								xapor.segment2
							FROM
								bolinf.xxwsb_account_plan_om_rev xapor
							WHERE
								xapor.customer_trx_line_id = xapod.customer_trx_line_id
						)               cogs_lob,
						(
							SELECT
								xapor.segment3
							FROM
								bolinf.xxwsb_account_plan_om_rev xapor
							WHERE
								xapor.customer_trx_line_id = xapod.customer_trx_line_id
						)               cogs_loc,
						(
							SELECT
								xapor.segment4
							FROM
								bolinf.xxwsb_account_plan_om_rev xapor
							WHERE
								xapor.customer_trx_line_id = xapod.customer_trx_line_id
						)               cogs_dept,
						(
							SELECT
								xapor.segment5
							FROM
								bolinf.xxwsb_account_plan_om_rev xapor
							WHERE
								xapor.customer_trx_line_id = xapod.customer_trx_line_id
						)               cogs_gl,
						(
							SELECT
								LISTAGG(xapoi.internal_ship_from, ', ') WITHIN GROUP(
								ORDER BY
									xapoi.internal_ship_from
								)
							FROM
								bolinf.xxwsb_account_plan_om_internal xapoi
							WHERE
								xapoi.order_line_id = xapod.order_line_id
						)               manufacturing_plant,
						upper(customer) customername
					FROM
						bolinf.xxwsb_account_plan_om_detail xapod
					WHERE
						trunc(summary_date,'MM') = trunc(sysdate, 'MM')
						AND trunc(summary_date,'YY') = trunc(sysdate, 'YY'));
			END;
		
            INSERT INTO bolinf.xxwsb_acct_plan_om_det_invstg (
                query_identifier,
                customer_trx_line_id,
                summary_date,
                operating_unit,
                line_of_business,
                rev_gl_account,
                territory,
                sales_person,
                cust_account_id,
                account_number,
                customer,
                order_number,
                order_line,
                order_line_type,
                invoice_type,
                invoice_date,
                invoice_number,
                invoice_line,
                inv_line_type,
                line_desc,
                gl_date,
                warehouse,
                item_number,
                inventory_category1,
                inventory_category2,
                inventory_category3,
                inventory_category4,
                quantity,
                uom_code,
                unit_standard_price,
                unit_selling_price,
                extended_amount,
                om_freight,
                om_credits,
                om_rev,
                om_replacements,
                om_cogs,
                om_gross_profit,
                om_gross_profit_percent,
                creation_date,
                request_id,
                market_quantity,
                market_uom,
                om_material,
                om_material_overhead,
                om_resource,
                om_outside_processing,
                om_overhead,
                order_line_id,
                rev_co,
                rev_lob,
                rev_loc,
                rev_dept,
                rev_gl,
                cogs_co,
                cogs_lob,
                cogs_loc,
                cogs_dept,
                cogs_gl,
                manufacturing_plant,
                customername,
				load_creation_date,
				created_by,
				last_updated_date,
				last_updated_by
            )
                SELECT
                    xapod.*,
                    (
                        SELECT
                            xapoc.segment1
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_co,
                    (
                        SELECT
                            xapoc.segment2
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_lob,
                    (
                        SELECT
                            xapoc.segment3
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_loc,
                    (
                        SELECT
                            xapoc.segment4
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_dept,
                    (
                        SELECT
                            xapoc.segment5
                        FROM
                            bolinf.xxwsb_account_plan_om_cogs xapoc
                        WHERE
                            xapoc.order_line_id = xapod.order_line_id
                    )               rev_gl,
                    (
                        SELECT
                            xapor.segment1
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_co,
                    (
                        SELECT
                            xapor.segment2
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_lob,
                    (
                        SELECT
                            xapor.segment3
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_loc,
                    (
                        SELECT
                            xapor.segment4
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_dept,
                    (
                        SELECT
                            xapor.segment5
                        FROM
                            bolinf.xxwsb_account_plan_om_rev xapor
                        WHERE
                            xapor.customer_trx_line_id = xapod.customer_trx_line_id
                    )               cogs_gl,
                    (
                        SELECT
                            LISTAGG(xapoi.internal_ship_from, ', ') WITHIN GROUP(
                            ORDER BY
                                xapoi.internal_ship_from
                            )
                        FROM
                            bolinf.xxwsb_account_plan_om_internal xapoi
                        WHERE
                            xapoi.order_line_id = xapod.order_line_id
                    )               manufacturing_plant,
                    upper(customer) customername,
					sysdate,
					l_created_by,
					sysdate,
					l_created_by --l_last_updated_by					
                FROM
                    bolinf.xxwsb_account_plan_om_detail xapod
                WHERE
					trunc(summary_date,'MM') = trunc(sysdate, 'MM')
					AND trunc(summary_date,'YY') = trunc(sysdate, 'YY');

        EXCEPTION
            WHEN OTHERS THEN
                fnd_file.put_line(fnd_file.log, 'Error - Data Load Incremental Ingetion.. '||SQLCODE||' - '||SQLERRM);
        END;
		COMMIT;
		fnd_file.put_line(fnd_file.log, 'Current Period Records Count : '||l_present_cnt);
		
    END IF;
	fnd_file.put_line(fnd_file.log, 'Data Load Stage End.. ');
	DBMS_OUTPUT.PUT_LINE('Data Load Stage End.. ');
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END xxwsb_acct_plan_om_det_invstgprc;