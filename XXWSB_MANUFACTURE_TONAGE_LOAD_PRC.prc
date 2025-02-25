CREATE OR REPLACE PROCEDURE BOLINF.XXWSB_MANUFACTURE_TONAGE_LOAD_PRC 
                                  (X_ERRBUF              OUT VARCHAR2,
                                   X_RETCODE             OUT NUMBER,
                                   P_PERIOD_NAME            IN  VARCHAR2,
								   P_INITIAL_LOAD_FLAG  IN VARCHAR2)
IS

V_CURR_PERIOD VARCHAR2(6);
V_REC_COUNT   NUMBER;
V_PERIOD_START_DATE VARCHAR2(20);
V_PERIOD_END_DATE VARCHAR2(20);

BEGIN
     
	  SELECT TO_CHAR(SYSDATE,'MON-YY') INTO V_CURR_PERIOD FROM DUAL;
      --  apps.fnd_file.put_line(apps.fnd_file.log, 'Current Period as per System Date '||V_CURR_PERIOD) ;
 
       SELECT COUNT(*)  into v_rec_count FROM BOLINF.XXWSB_MANUFACTURE_TONNAGE_NC_TAB;
	   
	   	BEGIN
								
									select start_date,end_date into V_PERIOD_START_DATE,V_PERIOD_END_DATE
                                            from gl_periods where period_set_name = 'WSB_13_Calendar'
                                                 and Period_name = P_PERIOD_NAME;
												 
									EXCEPTION WHEN OTHERS THEN
                                         NULL;
                                   END;	
 
      IF  (P_PERIOD_NAME IS NOT NULL  AND P_PERIOD_NAME <> V_CURR_PERIOD AND v_rec_count <> 0 )THEN
            apps.fnd_file.put_line(apps.fnd_file.log, 'User Entered the Period Parameter,But Period is not equal to Current Period.
                                                       This program will run for only current Period '||V_CURR_PERIOD ||' '||'User Requested Period is '||P_PERIOD_NAME) ;
	  END IF;
	  
	        IF  (P_PERIOD_NAME IS NOT NULL  AND P_PERIOD_NAME = V_CURR_PERIOD  AND v_rec_count <> 0)THEN
                   apps.fnd_file.put_line(apps.fnd_file.log, 'User Entered the Period Parameter,
		                                  Period is equal to Current Period. Data will laod for the period '||P_PERIOD_NAME) ;
					BEGIN		  
		                            DELETE FROM BOLINF.XXWSB_MANUFACTURE_TONNAGE_NC_TAB WHERE TRANS_MONTH = V_CURR_PERIOD;
				                               COMMIT;
																 
				                     apps.fnd_file.put_line(apps.fnd_file.log, 'Existing Current Period Data Deleted Successfully 
							                                                 and loading New Data for Period '||V_CURR_PERIOD) ;
			              EXCEPTION WHEN OTHERS THEN
			                        apps.fnd_file.put_line(apps.fnd_file.log, 'Error Occured While Deleting the Table for Period '||V_CURR_PERIOD||' '||SQLERRM) ;
				                     X_RETCODE := 2;
			        END;  			  
	        END IF;
	  
            IF (P_PERIOD_NAME IS NULL AND P_INITIAL_LOAD_FLAG <> 'Y' AND v_rec_count <> 0 ) THEN
		                     apps.fnd_file.put_line(apps.fnd_file.log, 'Period Parameter is null, Data will load for Current Period '||V_CURR_PERIOD) ;
		              BEGIN		  
		                        DELETE FROM BOLINF.XXWSB_MANUFACTURE_TONNAGE_NC_TAB WHERE TRANS_MONTH = V_CURR_PERIOD;
				                                  COMMIT;
													   
				                    apps.fnd_file.put_line(apps.fnd_file.log, 'Existing Current Period Data Deleted 
							                                                   Successfully and loading New Data for Period '||V_CURR_PERIOD) ;
			                  EXCEPTION WHEN OTHERS THEN
			                        apps.fnd_file.put_line(apps.fnd_file.log, 'Error Occured While Deleting the Table for Period '||V_CURR_PERIOD||' '||SQLERRM) ;
				                               X_RETCODE := 2;
			           END;  
            END IF;
	  
 
	  IF ((P_PERIOD_NAME = V_CURR_PERIOD OR P_PERIOD_NAME IS NULL) AND v_rec_count <> 0) THEN
	             apps.fnd_file.put_line(apps.fnd_file.log, 'Started Loading Data For Current Period '||V_CURR_PERIOD) ;
	    BEGIN
	            INSERT INTO  BOLINF.XXWSB_MANUFACTURE_TONNAGE_NC_TAB  
		          	                   (ORG ,
                                        CATEGORY ,
                                        TRANS_MONTH,
                                        transaction_date ,
                                        TRANSACTION_ID ,
                                        TRANSACTION_REFERENCE ,
                                        TRANSACTION_SPURCE_NAME ,
                                        ITEM_CODE ,
                                        QTY ,
                                        TRANSACTION_TYPE_NAME ,
                                        DESCRIPTION ,
                                        TRANSACTION_SOURCE_ID ,
                                        ORDER_NUMBER ,
										WIP_ENTITY_NAME,
                                        WIP_ENTITY_ID ,
                                        TEAM_DESC ,
                                        LOBO ,
                                        SALESREP_NAME )
							(  SELECT
                                     org.organization_code org,
                                     ffv.attribute2 category,
                                     to_char(mmt.transaction_date, 'MON-YY') trans_month,
                                     mmt.transaction_date,
                                     mmt.TRANSACTION_ID,
                                     mmt.TRANSACTION_REFERENCE,
                                     mmt.TRANSACTION_SOURCE_NAME,
                                     msi.segment1 item_code,
                                     apps.xxwsb_inv_get_uom_rate(mmt.inventory_item_id, mmt.transaction_uom, 'LB') * 
									    (mmt.primary_quantity * nvl(msi.unit_weight, 1)) / 2000 qty,
                                     mtt.TRANSACTION_TYPE_NAME,
                                     mtt.DESCRIPTION,
                                     mmt.transaction_source_id,
                                     nvl(substr(wen.wip_entity_name, 1, instr(wen.wip_entity_name, '-', 1, 1) - 1), '0') order_number,
                                     wen.wip_entity_name,
                                     wen.wip_entity_id,
                                     nvl(BOLINF.WSB_SALESREP_TEAM_INFO.WSB_SALESREP_ID((
                                                   SELECT
                                                   distinct
                                                   OH.SALESREP_ID
                                                   FROM 
                                                   JTF_RS_TEAMS_VL JRT,
                                                   JTF_RS_TEAM_MEMBERS_VL JRTM,
                                                   JTF_RS_SALESREPS JRS,
                                                   oe_order_headers_all oh,
                                                    mtl_sales_orders mso
                                                   WHERE
                                                       JRT.TEAM_ID = JRTM.TEAM_ID
                                                       and JRS.PERSON_ID = JRTM.PERSON_ID
                                                       and JRS.SALESREP_ID(+) = oh.salesrep_id
                                                       and oh.order_number = mso.segment1
                                                       and mso.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                   	and JRT.TEAM_DESC =decode(mso.segment2, 'HOU-COMPONENT ORDER','TX Components Team', 'ATL-COMPONENT ORDER','GA Components Team',  JRT.TEAM_DESC )
                                                   )),nvl(BOLINF.WSB_SALESREP_TEAM_INFO.WSB_SALESREP_ID((SELECT  distinct ooh_std.salesrep_id
                                                   --, ooh_std.order_number                   std_order
                                                             FROM oe_order_headers_all        ooh_std,
                                                                  oe_order_lines_all          ool_std,
                                                                   mtl_sales_orders mso1,
                                                                  po_requisition_headers_all  prh,
                                                                  po_requisition_lines_all    prl,
                                                                  oe_order_headers_all  ooh_int,
                                                                          oe_order_lines_all    ool_int, 
                                                                          oe_transaction_types_all ot,
                                                                          JTF_RS_TEAMS_VL JRT,
                                                   JTF_RS_TEAM_MEMBERS_VL JRTM,
                                                   JTF_RS_SALESREPS JRS
                                                            WHERE     ooh_std.header_id = ool_std.header_id
                                                                  --AND TO_CHAR (ool_std.schedule_ship_date, 'MON-YY') IN
                                                                          --('AUG-23', 'SEP-23', 'OCT-23')
                                                                  --AND ooh_std.order_number = '30200'
                                                                  AND ooh_std.ship_from_org_id = msi.organization_id
                                                                              --  AND ool_std.flow_status_code = 'PO_REQ_CREATED'
                                                                  AND ool_std.line_id = prl.attribute1
                                                                  AND prl.attribute_category = 'ORDER ENTRY'
                                                                  AND prh.requisition_header_id = prl.requisition_header_id
                                                                  AND ooh_int.header_id = ool_int.header_id
                                                                          AND ool_int.source_document_line_id =   prl.requisition_line_id
                                                                         and  ot.transaction_type_id = ooh_std.order_type_id
                                                                          --and ooh_int.order_number = '1060939'
                                                                          and ooh_int.order_number = mso1.segment1
                                                                          and mso1.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                   					   --and JRT.TEAM_DESC =decode(mso.segment2, 'HOU-COMPONENT ORDER','TX Components Team', 'ATL-COMPONENT ORDER','GA Components Team',  JRT.TEAM_DESC )
                                                                          and JRT.TEAM_ID = JRTM.TEAM_ID
                                                       and JRS.PERSON_ID = JRTM.PERSON_ID
                                                       and JRS.SALESREP_ID(+) = ooh_std.salesrep_id
                                                                          )),'NO TEAM')) TEAM_DESC
                                                   ,
                                            nvl((
                                                        SELECT
                                                        distinct
                                                        ot.attribute2
                                                        FROM 
                                                        oe_order_headers_all oh,
                                                         mtl_sales_orders mso,
                                                         oe_transaction_types_all ot
                                                        WHERE
                                                            ot.transaction_type_id = oh.order_type_id
                                                            and oh.order_number = mso.segment1
                                                            and mso.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                        ),nvl((SELECT  distinct ot.attribute2
                                                        --, ooh_std.order_number                   std_order
                                                                  FROM oe_order_headers_all        ooh_std,
                                                                       oe_order_lines_all          ool_std,
                                                                        mtl_sales_orders mso1,
                                                                       po_requisition_headers_all  prh,
                                                                       po_requisition_lines_all    prl,
                                                                       oe_order_headers_all  ooh_int,
                                                                               oe_order_lines_all    ool_int, 
                                                                               oe_transaction_types_all ot
                                                                 WHERE     ooh_std.header_id = ool_std.header_id
                                                                       --AND TO_CHAR (ool_std.schedule_ship_date, 'MON-YY') IN
                                                                               --('AUG-23', 'SEP-23', 'OCT-23')
                                                                       --AND ooh_std.order_number = '30200'
                                                                       AND ooh_std.ship_from_org_id = msi.organization_id
                                                                                   --  AND ool_std.flow_status_code = 'PO_REQ_CREATED'
                                                                       AND ool_std.line_id = prl.attribute1
                                                                       AND prl.attribute_category = 'ORDER ENTRY'
                                                                       AND prh.requisition_header_id = prl.requisition_header_id
                                                                       AND ooh_int.header_id = ool_int.header_id
                                                                               AND ool_int.source_document_line_id =   prl.requisition_line_id
                                                                              and  ot.transaction_type_id = ooh_std.order_type_id
                                                                               --and ooh_int.order_number = '1060939'
                                                                               and ooh_int.order_number = mso1.segment1
                                                                               and mso1.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                                               )
                                                                               --and ool_int.line_number in (11,20)
                                                                               ,'NO LOB')
                                                                               ) LOBO,
                                                        (SELECT distinct jrs.name
                                                         FROM
                                                             jtf_rs_teams_vl jrt,
                                                             jtf_rs_team_members_vl jrtm,
                                                             jtf_rs_salesreps jrs,
                                                             oe_order_headers_all oh,
                                                             mtl_sales_orders mso
                                                         WHERE
                                                             jrt.team_id = jrtm.team_id
															 and jrs.org_id = 0
                                                             AND jrs.person_id = jrtm.person_id
                                                             AND jrs.salesrep_id(+) = oh.salesrep_id
                                                             AND oh.order_number = mso.segment1
                                                             AND mso.segment1 = nvl(substr(wen.wip_entity_name, 1, instr(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                             AND jrt.team_desc = decode(mso.segment2, 'HOU-COMPONENT ORDER', 'TX Components Team', 'ATL-COMPONENT ORDER', 'GA Components Team', jrt.team_desc)
                                                     ) salesrep_name
                                            FROM
                                                fnd_flex_values ffv,
                                                fnd_flex_value_sets ffvs,
                                                mtl_categories mca,
                                                mtl_item_categories mic,
                                                mtl_system_items msi,
                                                mtl_material_transactions mmt,
                                                mtl_parameters org,
                                                wip_entities wen,
                                                org_acct_periods oap,
                                                MTL_TRANSACTION_TYPES mtt
                                            WHERE
                                                org.organization_id = mmt.organization_id
                                                AND mic.organization_id = mmt.organization_id
                                                AND mic.inventory_item_id = mmt.inventory_item_id
                                                AND msi.organization_id = mmt.organization_id
                                                AND msi.inventory_item_id = mmt.inventory_item_id
                                                AND mca.category_id = mic.category_id
                                                AND mca.structure_id = 101
                                                AND ffv.flex_value = mca.segment1
                                                AND ffvs.flex_value_set_id = ffv.flex_value_set_id
                                                AND ffvs.flex_value_set_name = 'WSB_PRODUCT_LINE_CATEGORY'
                                                AND mmt.transaction_type_id = 44
                                                AND mmt.transaction_source_type_id = 5
                                                AND mmt.transaction_action_id = 31
                                                AND ffv.attribute2 <> 'Accessories'
                                                AND wen.wip_entity_id = mmt.transaction_source_id
                                                AND trunc(mmt.transaction_date) >= trunc(oap.period_start_date)
                                                AND trunc(mmt.transaction_date) <= trunc(oap.schedule_close_date)
                                                AND msi.organization_id IN (82, 85)
                                                AND oap.organization_id IN (82, 85)
                                                and mtt.TRANSACTION_TYPE_ID = mmt.TRANSACTION_TYPE_ID
                                                AND oap.organization_id = msi.organization_id
                                              --  AND TO_DATE(transaction_date , 'DD-MON-RR') = TO_DATE(('01-APR-24'), 'DD-MON-RR')
                                             -- and oap.period_name = 'APR-24'
                                            	and to_date ( ( '01-' || oap.period_name ) , 'DD-MON-RR' )
                                            	between to_date ( V_PERIOD_START_DATE, 'DD-MON-RR' ) 
                                            	and to_date  ( V_PERIOD_END_DATE, 'DD-MON-RR' )
                                                --BETWEEN TO_DATE(('01-APR-24'), 'DD-MON-RR') AND TO_DATE(('02-APR-24'), 'DD-MON-RR')
                                            
                                            
                                              );		
                                	
                                COMMIT;
								apps.fnd_file.put_line(apps.fnd_file.log, 'Data Load Completed For '||V_CURR_PERIOD||' '||SQLERRM) ;
			    EXCEPTION WHEN OTHERS THEN
				    apps.fnd_file.put_line(apps.fnd_file.log, 'Error Occured While Inserting Data for Period '||V_CURR_PERIOD||' '||SQLERRM) ;
					 X_RETCODE := 2;
			END;   
			   
	  END IF;
	  
	  
	  IF (v_rec_count = 0) THEN
	  
	            apps.fnd_file.put_line(apps.fnd_file.log, 'Started Processing the Intial Load Process as Initial Load Process Flag set to Y ') ;
	          
			          DELETE FROM BOLINF.XXWSB_MANUFACTURE_TONNAGE_NC_TAB
					     COMMIT;
	  
	       BEGIN
	           INSERT INTO  BOLINF.XXWSB_MANUFACTURE_TONNAGE_NC_TAB  
		          	                   (ORG ,
                                        CATEGORY ,
                                        TRANS_MONTH,
                                        transaction_date ,
                                        TRANSACTION_ID ,
                                        TRANSACTION_REFERENCE ,
                                        TRANSACTION_SPURCE_NAME ,
                                        ITEM_CODE ,
                                        QTY ,
                                        TRANSACTION_TYPE_NAME ,
                                        DESCRIPTION ,
                                        TRANSACTION_SOURCE_ID ,
                                        ORDER_NUMBER ,
										WIP_ENTITY_NAME,
                                        WIP_ENTITY_ID ,										
                                        TEAM_DESC ,
                                        LOBO ,
                                        SALESREP_NAME 
										)
							(  SELECT
                                     org.organization_code org,
                                     ffv.attribute2 category,
                                     to_char(mmt.transaction_date, 'MON-YY') trans_month,
                                     mmt.transaction_date,
                                     mmt.TRANSACTION_ID,
                                     mmt.TRANSACTION_REFERENCE,
                                     mmt.TRANSACTION_SOURCE_NAME,
                                     msi.segment1 item_code,
                                     apps.xxwsb_inv_get_uom_rate(mmt.inventory_item_id, mmt.transaction_uom, 'LB') * 
									    (mmt.primary_quantity * nvl(msi.unit_weight, 1)) / 2000 qty,
                                     mtt.TRANSACTION_TYPE_NAME,
                                     mtt.DESCRIPTION,
                                     mmt.transaction_source_id,
                                     nvl(substr(wen.wip_entity_name, 1, instr(wen.wip_entity_name, '-', 1, 1) - 1), '0') order_number,
                                     wen.wip_entity_name,
                                     wen.wip_entity_id,
                                     nvl(BOLINF.WSB_SALESREP_TEAM_INFO.WSB_SALESREP_ID((
                                                   SELECT
                                                   distinct
                                                   OH.SALESREP_ID
                                                   FROM 
                                                   JTF_RS_TEAMS_VL JRT,
                                                   JTF_RS_TEAM_MEMBERS_VL JRTM,
                                                   JTF_RS_SALESREPS JRS,
                                                   oe_order_headers_all oh,
                                                    mtl_sales_orders mso
                                                   WHERE
                                                       JRT.TEAM_ID = JRTM.TEAM_ID
                                                       and JRS.PERSON_ID = JRTM.PERSON_ID
                                                       and JRS.SALESREP_ID(+) = oh.salesrep_id
                                                       and oh.order_number = mso.segment1
                                                       and mso.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                   	and JRT.TEAM_DESC =decode(mso.segment2, 'HOU-COMPONENT ORDER','TX Components Team', 'ATL-COMPONENT ORDER','GA Components Team',  JRT.TEAM_DESC )
                                                   )),nvl(BOLINF.WSB_SALESREP_TEAM_INFO.WSB_SALESREP_ID((SELECT  distinct ooh_std.salesrep_id
                                                   --, ooh_std.order_number                   std_order
                                                             FROM oe_order_headers_all        ooh_std,
                                                                  oe_order_lines_all          ool_std,
                                                                   mtl_sales_orders mso1,
                                                                  po_requisition_headers_all  prh,
                                                                  po_requisition_lines_all    prl,
                                                                  oe_order_headers_all  ooh_int,
                                                                          oe_order_lines_all    ool_int, 
                                                                          oe_transaction_types_all ot,
                                                                          JTF_RS_TEAMS_VL JRT,
                                                   JTF_RS_TEAM_MEMBERS_VL JRTM,
                                                   JTF_RS_SALESREPS JRS
                                                            WHERE     ooh_std.header_id = ool_std.header_id
                                                                  --AND TO_CHAR (ool_std.schedule_ship_date, 'MON-YY') IN
                                                                          --('AUG-23', 'SEP-23', 'OCT-23')
                                                                  --AND ooh_std.order_number = '30200'
                                                                  AND ooh_std.ship_from_org_id = msi.organization_id
                                                                              --  AND ool_std.flow_status_code = 'PO_REQ_CREATED'
                                                                  AND ool_std.line_id = prl.attribute1
                                                                  AND prl.attribute_category = 'ORDER ENTRY'
                                                                  AND prh.requisition_header_id = prl.requisition_header_id
                                                                  AND ooh_int.header_id = ool_int.header_id
                                                                          AND ool_int.source_document_line_id =   prl.requisition_line_id
                                                                         and  ot.transaction_type_id = ooh_std.order_type_id
                                                                          --and ooh_int.order_number = '1060939'
                                                                          and ooh_int.order_number = mso1.segment1
                                                                          and mso1.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                   					   --and JRT.TEAM_DESC =decode(mso.segment2, 'HOU-COMPONENT ORDER','TX Components Team', 'ATL-COMPONENT ORDER','GA Components Team',  JRT.TEAM_DESC )
                                                                          and JRT.TEAM_ID = JRTM.TEAM_ID
                                                       and JRS.PERSON_ID = JRTM.PERSON_ID
                                                       and JRS.SALESREP_ID(+) = ooh_std.salesrep_id
                                                                          )),'NO TEAM')) TEAM_DESC
                                                   ,
                                            nvl((
                                                        SELECT
                                                        distinct
                                                        ot.attribute2
                                                        FROM 
                                                        oe_order_headers_all oh,
                                                         mtl_sales_orders mso,
                                                         oe_transaction_types_all ot
                                                        WHERE
                                                            ot.transaction_type_id = oh.order_type_id
                                                            and oh.order_number = mso.segment1
                                                            and mso.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                        ),nvl((SELECT  distinct ot.attribute2
                                                        --, ooh_std.order_number                   std_order
                                                                  FROM oe_order_headers_all        ooh_std,
                                                                       oe_order_lines_all          ool_std,
                                                                        mtl_sales_orders mso1,
                                                                       po_requisition_headers_all  prh,
                                                                       po_requisition_lines_all    prl,
                                                                       oe_order_headers_all  ooh_int,
                                                                               oe_order_lines_all    ool_int, 
                                                                               oe_transaction_types_all ot
                                                                 WHERE     ooh_std.header_id = ool_std.header_id
                                                                       --AND TO_CHAR (ool_std.schedule_ship_date, 'MON-YY') IN
                                                                               --('AUG-23', 'SEP-23', 'OCT-23')
                                                                       --AND ooh_std.order_number = '30200'
                                                                       AND ooh_std.ship_from_org_id = msi.organization_id
                                                                                   --  AND ool_std.flow_status_code = 'PO_REQ_CREATED'
                                                                       AND ool_std.line_id = prl.attribute1
                                                                       AND prl.attribute_category = 'ORDER ENTRY'
                                                                       AND prh.requisition_header_id = prl.requisition_header_id
                                                                       AND ooh_int.header_id = ool_int.header_id
                                                                               AND ool_int.source_document_line_id =   prl.requisition_line_id
                                                                              and  ot.transaction_type_id = ooh_std.order_type_id
                                                                               --and ooh_int.order_number = '1060939'
                                                                               and ooh_int.order_number = mso1.segment1
                                                                               and mso1.segment1 = nvl(SUBSTR(wen.wip_entity_name, 1, INSTR(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                                               )
                                                                               --and ool_int.line_number in (11,20)
                                                                               ,'NO LOB')
                                                                               ) LOBO,
                                                        (SELECT distinct jrs.name
                                                         FROM
                                                             jtf_rs_teams_vl jrt,
                                                             jtf_rs_team_members_vl jrtm,
                                                             jtf_rs_salesreps jrs,
                                                             oe_order_headers_all oh,
                                                             mtl_sales_orders mso
                                                         WHERE
                                                             jrt.team_id = jrtm.team_id
															 AND jrs.org_id = 0
                                                             AND jrs.person_id = jrtm.person_id
                                                             AND jrs.salesrep_id(+) = oh.salesrep_id
                                                             AND oh.order_number = mso.segment1
                                                             AND mso.segment1 = nvl(substr(wen.wip_entity_name, 1, instr(wen.wip_entity_name, '-', 1, 1) - 1), '0')
                                                             AND jrt.team_desc = decode(mso.segment2, 'HOU-COMPONENT ORDER', 'TX Components Team', 'ATL-COMPONENT ORDER', 'GA Components Team', jrt.team_desc)
                                                     ) salesrep_name
                                            FROM
                                                fnd_flex_values ffv,
                                                fnd_flex_value_sets ffvs,
                                                mtl_categories mca,
                                                mtl_item_categories mic,
                                                mtl_system_items msi,
                                                mtl_material_transactions mmt,
                                                mtl_parameters org,
                                                wip_entities wen,
                                                org_acct_periods oap,
                                                MTL_TRANSACTION_TYPES mtt
                                            WHERE
                                                org.organization_id = mmt.organization_id
                                                AND mic.organization_id = mmt.organization_id
                                                AND mic.inventory_item_id = mmt.inventory_item_id
                                                AND msi.organization_id = mmt.organization_id
                                                AND msi.inventory_item_id = mmt.inventory_item_id
                                                AND mca.category_id = mic.category_id
                                                AND mca.structure_id = 101
                                                AND ffv.flex_value = mca.segment1
                                                AND ffvs.flex_value_set_id = ffv.flex_value_set_id
                                                AND ffvs.flex_value_set_name = 'WSB_PRODUCT_LINE_CATEGORY'
                                                AND mmt.transaction_type_id = 44
                                                AND mmt.transaction_source_type_id = 5
                                                AND mmt.transaction_action_id = 31
                                                AND ffv.attribute2 <> 'Accessories'
                                                AND wen.wip_entity_id = mmt.transaction_source_id
                                                AND trunc(mmt.transaction_date) >= trunc(oap.period_start_date)
                                                AND trunc(mmt.transaction_date) <= trunc(oap.schedule_close_date)
                                                AND msi.organization_id IN (82, 85)
                                                AND oap.organization_id IN (82, 85)
                                                and mtt.TRANSACTION_TYPE_ID = mmt.TRANSACTION_TYPE_ID
                                                AND oap.organization_id = msi.organization_id
                                              --  AND TO_DATE(transaction_date , 'DD-MON-RR') = TO_DATE(('01-APR-24'), 'DD-MON-RR')
                                             -- and oap.period_name = 'APR-24'
                                            	and to_date ( ( '01-' || oap.period_name ) , 'DD-MON-RR' )
                                            	between to_date ( ( '01-' || 'JAN-20' ) , 'DD-MON-RR' ) 
                                            	and to_date ( V_PERIOD_END_DATE , 'DD-MON-RR' )
                                                --BETWEEN TO_DATE(('01-APR-24'), 'DD-MON-RR') AND TO_DATE(('02-APR-24'), 'DD-MON-RR')
                                            
                                            
                                              );		
                                COMMIT;
								apps.fnd_file.put_line(apps.fnd_file.log, 'Initial Data Load Completed '||SQLERRM) ;
			    EXCEPTION WHEN OTHERS THEN
				    apps.fnd_file.put_line(apps.fnd_file.log, 'Error Occured While Inserting Data during Initial load Process '||SQLERRM) ;
					 X_RETCODE := 2;
			END;   
	        
	  END IF;  
	  
                       X_RETCODE := 0;
EXCEPTION WHEN OTHERS THEN
apps.fnd_file.put_line(apps.fnd_file.log, 'UnKnown Error Occured while Executing the Procedure for Period '||P_PERIOD_NAME||' '||SQLERRM) ;
X_RETCODE := 2;
END;
/
