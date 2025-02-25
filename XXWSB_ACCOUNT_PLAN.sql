create or replace PACKAGE BODY        "XXWSB_ACCOUNT_PLAN"
AS
  /******************************************************************************
  NAME:      BOLINF.xxwsb_account_plan
  PURPOSE:   Creating custom package BOLINF.xxwsb_account_plan
  REVISIONS:
  Ver        Date        Author           Description
  ---------  ----------  ---------------  ------------------------------------
  1.0        7/26/2012   jsbisa           1. Created this package
  2.0        10/5/2012   skomirisetti     1. Modified get_pa_data procedure to get pa_cost
  2.1        1/9/2013    jsbisa           1. Added code around period selection in get_data to skip invalid dates that might get picked for periods like ADJ-12
                                             Fixed cursor for OM_DATA to get correct revenue and COGS
  3.0        04/11/2014  prao             1. Added Update statment to update the account number value based on the customer_account_id
  3.1        07/29/2014  jsbisa           1. Update om_cursor.  Complete replacement of query to match detail query created for APEX.
                                             Includes the fix to remove inner join between material transactions and code cobinations that
                                             caused some RMA return records to be filtered out.
  3.2        09/08/2014  jsbisa           1. PA_Fright now included in the update statement (It was missing).
  3.3        10/22/2014  jsbisa           1. Fixed Part6 to do outer join on Orders and correction for invoices without a SOLD-TO.
                                          2. Update all data to zero before a summary-date is re-processed in order to handle records that are deleted from Oracle
  3.4        01/19/2014  jsbisa           1. Update OM_COGS, OM_Replacements to use mtl_transaction_accounts table instead on Mtl_material_transactions.
                                             This will remove the rounding errors for these 2 fields.
  3.5        08/06/2015  jsbisa           1. Update Part6 query to remove filter on msi.mtl_transaction_enabled_flag
                                          2. Update Part6 query to add filter to remove RMA material transactions that got picked up in Part3
  3.6        02/05/2018  jsbisa           1. SR76767 - Change reset of rows not updated to be post updated instead first thing in the module.
                                             This way we don't reset every row to zero first.  Needed this to support change in trigger to only reset Salesforce flag
                                             if any of the data actually is modified.  This should greatly reduce the number of rows being processed by CastIron andn Salesforce.
                                          2. SR76767 - Change to pulled Closed periods for 7 days, down from 30
  3.7        06/20/2018  jsbisa           1. SR79154 - Add a detail tabale based on the Account Plan data.  This detail table is needed for reporting by GL Wand.
  3.8        08/09/2018  jsbisa           1. SR80170 - Add LB conversion, Add Cost Elements

  NOTES:
  Object Name:     XXWSB_ACCOUNT_PLAN
  Username:        jsbisa, Smartdog Services
  Table Name:      XXWSB_ACCOUNT_PLAN
  ******************************************************************************/
  --
  --Global Variables
  g_return_code NUMBER;
  --
  --
  -- get_om_data is called for a summary_date (first day of month) and loads OM data
  -- It can also be used to run a manual update of the data for a period.
  --
PROCEDURE get_om_data(
    p_summary_date DATE)
IS
  --
  CURSOR om_cursor(p_summary_date DATE)
  IS
    SELECT cust_account_id,
      line_of_business,
      TRUNC(gl_date, 'MONTH') summary_date,
      SUM(om_freight) om_freight,
      SUM(om_credits) om_credits,
      ROUND(SUM(om_replacements), 2) om_replacements,
      SUM(om_rev) om_revenue,
      ROUND(SUM(om_cogs), 2) om_cogs
    FROM xxwsb_account_plan_om_detail
    WHERE gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')|| '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
      AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')|| ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
    GROUP BY cust_account_id,
      line_of_business,
      TRUNC(gl_date, 'MONTH')
    ORDER BY cust_account_id,
      line_of_business,
      TRUNC(gl_date, 'MONTH') ;


  CURSOR om_detail_cursor(p_summary_date DATE)
  IS
    SELECT query_identifier,
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
        (om_rev - om_cogs) om_gross_profit,
        CASE
          WHEN om_rev != 0
          THEN ROUND((((om_rev - om_cogs) / om_rev) * 100), 2)
          ELSE 0
        END om_gross_profit_percent,
        SYSDATE creation_date,
        fnd_global.conc_request_id request_id,
        NVL(CASE
          WHEN uom_code = 'LB' THEN quantity
          ELSE ((quantity * apps.XXWSB_INV_get_uom_rate(inventory_item_id, uom_code, primary_uom_code) * (unit_weight * apps.XXWSB_INV_get_uom_rate(inventory_item_id, weight_uom_code, 'LB'))))
        END, 0) market_quantity,
        'LB' market_uom,
        NVL(om_material,0) om_material,
        NVL(om_material_overhead,0) om_material_overhead,
        NVL(om_resource,0) om_resource,
        NVL(om_outside_processing,0) om_outside_processing,
        NVL(om_overhead,0) om_overhead,
        order_line_id
      FROM
        (SELECT query_identifier,
          customer_trx_line_id,
          TRUNC(gl_date, 'MONTH') summary_date,
          operating_unit,
          line_of_business,
          rev_gl_account,
          territory,
          sales_person,
          cust_account_id,
          account_number,
          customer,
          order_line_id,
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
          inventory_item_id,
          item_number,
          primary_uom_code,
          weight_uom_code,
          unit_weight,
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
          ROUND(SUM(om_replacements), 2) om_replacements,
          ROUND(SUM(om_cogs), 2) om_cogs,
          ROUND(SUM(om_material), 2) om_material,
          ROUND(SUM(om_material_overhead), 2) om_material_overhead,
          ROUND(SUM(om_resource), 2) om_resource,
          ROUND(SUM(om_outside_processing), 2) om_outside_processing,
          ROUND(SUM(om_overhead), 2) om_overhead
        FROM
          (SELECT
            /*+ INDEX(trx RA_CUSTOMER_TRX_U1) INDEX(hcasa HZ_CUST_ACCT_SITES_U1) */
            'Part1' query_identifier,
            rctl.customer_trx_line_id,
            oola.line_id order_line_id,
            hou.name operating_unit,
            cc.segment2 line_of_business,
            cc.segment5 rev_gl_account,
            hcasa.territory,
            jrs.name sales_person,
            hca.cust_account_id,
            hca.account_number,
            hzp.party_name customer,
            rctl.interface_line_attribute1 order_number,
            oola.line_number
            || '.'
            || oola.shipment_number order_line,
            ott.name order_line_type,
            TYPE.description invoice_type,
            trx.trx_date invoice_date,
            trx.trx_number invoice_number,
            rctl.line_number invoice_line,
            rctl.line_type inv_line_type,
            rctl.description line_desc,
            gl_dist.gl_date gl_date,
            mp.organization_code warehouse,
            msi.inventory_item_id,
            msi.segment1 item_number,
            msi.primary_uom_code,
            msi.weight_uom_code,
            msi.unit_weight,
            mc.segment1 inventory_category1,
            mc.segment2 inventory_category2,
            mc.segment3 inventory_category3,
            mc.segment4 inventory_category4,
            NVL(rctl.quantity_invoiced, rctl.quantity_credited) quantity,
            rctl.uom_code,
            rctl.unit_standard_price,
            rctl.unit_selling_price,
            rctl.extended_amount,
            DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0) om_freight,
            CASE
              WHEN gl_dist.acctd_amount < 0
                AND rctl.quantity_invoiced > 0
                AND cc.segment5 <> '6415'
              THEN gl_dist.acctd_amount
              ELSE 0
            END om_credits,
            gl_dist.acctd_amount om_rev,
            CASE
              WHEN mmt.new_cost <> 0
                AND gl_dist.acctd_amount = 0
              THEN (
                    NVL(
                        (SELECT SUM(base_transaction_value) 
                          FROM mtl_transaction_accounts 
                         WHERE transaction_id = mmt.transaction_id 
                           AND accounting_line_type = 2)
                        ,(SELECT SUM(base_transaction_value) 
                          FROM mtl_transaction_accounts 
                         WHERE transaction_id = mmt.transaction_id 
                           AND accounting_line_type = 36)
                       )
                   )
              ELSE 0
            END om_replacements,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                    FROM mtl_transaction_accounts 
                   WHERE transaction_id = mmt.transaction_id 
                     AND accounting_line_type = 2)
                  ,(SELECT SUM(base_transaction_value) 
                    FROM mtl_transaction_accounts 
                   WHERE transaction_id = mmt.transaction_id 
                     AND accounting_line_type = 36)
                 )
            ) om_cogs,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 1) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 1) 
                 )
            ) om_material,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 2) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 2) 
                 )
            ) om_material_overhead,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 3) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 3) 
                 )
            ) om_resource,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 4) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 4) 
                 )
            ) om_outside_processing,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 5) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 5) 
                 )
            ) om_overhead,
            TRUNC(mmt.transaction_date) transaction_date
          FROM apps.ra_cust_trx_types_all TYPE,
            apps.gl_code_combinations cc,
            apps.ra_cust_trx_line_gl_dist_all gl_dist,
            apps.ra_customer_trx_all trx,
            apps.ra_customer_trx_lines_all rctl,
            apps.oe_order_lines_all oola,
            apps.oe_transaction_types_tl ott,
            apps.hr_all_organization_units hou,
            apps.mtl_parameters mp,
            apps.mtl_system_items_b msi,
            apps.hz_cust_accounts hca,
            apps.hz_parties hzp,
            apps.mtl_material_transactions mmt,
            apps.hz_cust_site_uses_all hcsua,
            apps.hz_cust_acct_sites_all hcasa,
            apps.jtf_rs_salesreps jrs,
            apps.mtl_categories mc
          WHERE 1 = 1
            AND trx.complete_flag = 'Y'
            AND hou.organization_id = rctl.org_id
            AND rctl.warehouse_id = msi.organization_id
            AND rctl.inventory_item_id = msi.inventory_item_id
            AND oola.ship_from_org_id = mp.organization_id
            AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
            AND TYPE.org_id = trx.org_id
            AND trx.customer_trx_id = rctl.customer_trx_id
            AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
            AND rctl.interface_line_attribute6 = oola.line_id
            AND rctl.line_type = 'LINE'
            AND cc.code_combination_id = gl_dist.code_combination_id
            AND gl_dist.customer_trx_id = trx.customer_trx_id
            AND ott.transaction_type_id(+) = oola.line_type_id
            AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
            || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
            AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
            || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
            AND trx.org_id = TYPE.org_id
            AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
            AND hzp.party_id = hca.party_id
            AND cc.segment5 IN('3041', '6415') -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
            AND mmt.inventory_item_id = oola.inventory_item_id
            AND mmt.organization_id = oola.ship_from_org_id
            AND mmt.transaction_action_id IN(1, 27)
            AND mmt.transaction_type_id IN(33) -- sales order issues
            AND mmt.source_line_id = oola.line_id
            AND mc.category_id =
            (SELECT mic.category_id
            FROM apps.mtl_item_categories mic,
              apps.mtl_category_sets mcs
            WHERE mcs.category_set_name = 'Inventory'
              AND mic.category_set_id = mcs.category_set_id
              AND mic.organization_id = msi.organization_id
              AND mic.inventory_item_id = msi.inventory_item_id
            )
          AND hcsua.site_use_id = trx.bill_to_site_use_id
          AND hcasa.cust_acct_site_id = hcsua.cust_acct_site_id
          AND jrs.salesrep_id = trx.primary_salesrep_id
          AND jrs.org_id = trx.org_id
        UNION ALL
        /* Assembly/Configuration OM Lines - joined by top_model_line_id instead of line_id */
        SELECT
          query_identifier,
          customer_trx_line_id,
          order_line_id,
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
          inventory_item_id,
          item_number,
          primary_uom_code,
          weight_uom_code,
          unit_weight,
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
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                    FROM mtl_transaction_accounts 
                   WHERE transaction_id = a.transaction_id 
                     AND accounting_line_type = 2)
                  ,(SELECT SUM(base_transaction_value) 
                    FROM mtl_transaction_accounts 
                   WHERE transaction_id = a.transaction_id 
                     AND accounting_line_type = 36)
                 )
            ) om_cogs,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 1) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 1) 
                 )
            ) om_material,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 2) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 2) 
                 )
            ) om_material_overhead,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 3) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 3) 
                 )
            ) om_resource,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 4) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 4) 
                 )
            ) om_outside_processing,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 5) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = a.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 5) 
                 )
            ) om_overhead,
          transaction_date
        FROM (
        SELECT
          /*+ INDEX(trx RA_CUSTOMER_TRX_U1) INDEX(hcasa HZ_CUST_ACCT_SITES_U1) */
          'Part2' query_identifier,
          rctl.customer_trx_line_id,
          oola.top_model_line_id order_line_id,
          hou.name operating_unit,
          cc.segment2 line_of_business,
          cc.segment5 rev_gl_account,
          hcasa.territory,
          jrs.name sales_person,
          hca.cust_account_id,
          hca.account_number,
          hzp.party_name customer,
          rctl.interface_line_attribute1 order_number,
          oola.line_number
          || '.'
          || oola.shipment_number order_line,
          ott.name order_line_type,
          TYPE.description invoice_type,
          trx.trx_date invoice_date,
          trx.trx_number invoice_number,
          rctl.line_number invoice_line,
          rctl.line_type inv_line_type,
          rctl.description line_desc,
          gl_dist.gl_date gl_date,
          mp.organization_code warehouse,
          msi.inventory_item_id,
          msi.segment1 item_number,
          msi.primary_uom_code,
          msi.weight_uom_code,
          msi.unit_weight,
          mc.segment1 inventory_category1,
          mc.segment2 inventory_category2,
          mc.segment3 inventory_category3,
          mc.segment4 inventory_category4,
          NVL(rctl.quantity_invoiced, rctl.quantity_credited) quantity,
          rctl.uom_code,
          rctl.unit_standard_price,
          rctl.unit_selling_price,
          rctl.extended_amount,
          DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0) om_freight,
          CASE
            WHEN gl_dist.acctd_amount < 0
              AND rctl.quantity_invoiced > 0
              AND cc.segment5 <> '6415'
            THEN gl_dist.acctd_amount
            ELSE 0
          END om_credits,
          gl_dist.acctd_amount om_rev,
          SUM(
          CASE
            WHEN mmt.new_cost <> 0
              AND gl_dist.acctd_amount = 0
            THEN (
                NVL(
                    (SELECT SUM(base_transaction_value) 
                      FROM mtl_transaction_accounts mta
                     WHERE mta.transaction_id = mmt.transaction_id 
                       AND mta.accounting_line_type = 2)
                    ,(SELECT SUM(base_transaction_value) 
                      FROM mtl_transaction_accounts mta
                     WHERE mta.transaction_id = mmt.transaction_id 
                       AND mta.accounting_line_type = 36)
                   )
                 )
            ELSE 0
          END) om_replacements,
          TRUNC(mmt.transaction_date) transaction_date,
          mmt.transaction_id
        FROM apps.ra_cust_trx_types_all TYPE,
          apps.gl_code_combinations cc,
          apps.ra_cust_trx_line_gl_dist_all gl_dist,
          apps.ra_customer_trx_all trx,
          apps.ra_customer_trx_lines_all rctl,
          apps.oe_order_lines_all oola,
          apps.oe_transaction_types_tl ott,
          apps.hr_all_organization_units hou,
          apps.mtl_parameters mp,
          apps.mtl_system_items_b msi,
          apps.hz_cust_accounts hca,
          apps.hz_parties hzp,
          apps.mtl_material_transactions mmt,
          apps.hz_cust_site_uses_all hcsua,
          apps.hz_cust_acct_sites_all hcasa,
          apps.jtf_rs_salesreps jrs,
          apps.mtl_categories mc
        WHERE 1 = 1
          AND trx.complete_flag = 'Y'
          AND hou.organization_id = rctl.org_id
          AND rctl.warehouse_id = msi.organization_id
          AND rctl.inventory_item_id = msi.inventory_item_id
          AND oola.ship_from_org_id = mp.organization_id
          AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
          AND TYPE.org_id = trx.org_id
          AND trx.customer_trx_id = rctl.customer_trx_id
          AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
          AND rctl.interface_line_attribute6 = oola.top_model_line_id
          AND rctl.line_type = 'LINE'
          AND cc.code_combination_id = gl_dist.code_combination_id
          AND gl_dist.customer_trx_id = trx.customer_trx_id
          AND ott.transaction_type_id(+) = oola.line_type_id
          AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
          || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
          AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
          || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
          AND trx.org_id = TYPE.org_id
          AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
          AND hzp.party_id = hca.party_id
          AND cc.segment5 IN('3041', '6415') -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
          AND mmt.inventory_item_id = oola.inventory_item_id
          AND mmt.organization_id = oola.ship_from_org_id
          AND mmt.transaction_action_id IN(1, 27)
          AND mmt.transaction_type_id IN(33) -- sales order issues
          AND mmt.source_line_id = oola.line_id
          AND mc.category_id =
          (SELECT mic.category_id
          FROM apps.mtl_item_categories mic,
            apps.mtl_category_sets mcs
          WHERE mcs.category_set_name = 'Inventory'
            AND mic.category_set_id = mcs.category_set_id
            AND mic.organization_id = msi.organization_id
            AND mic.inventory_item_id = msi.inventory_item_id
          )
          AND hcsua.site_use_id = trx.bill_to_site_use_id
          AND hcasa.cust_acct_site_id = hcsua.cust_acct_site_id
          AND jrs.salesrep_id = trx.primary_salesrep_id
          AND jrs.org_id = trx.org_id
       GROUP BY 'Part2',
          hou.name,
          rctl.customer_trx_line_id,
          oola.top_model_line_id,
          cc.segment2,
          cc.segment5,
          hcasa.territory,
          jrs.name,
          hca.cust_account_id,
          hca.account_number,
          hzp.party_name,
          rctl.interface_line_attribute1,
          oola.line_number
          || '.'
          || oola.shipment_number,
          ott.name,
          TYPE.description,
          trx.trx_date,
          trx.trx_number,
          rctl.line_number,
          rctl.line_type,
          rctl.description,
          gl_dist.gl_date,
          mp.organization_code,
          msi.inventory_item_id,
          msi.segment1,
          msi.primary_uom_code,
          msi.weight_uom_code,
          msi.unit_weight,
          mc.segment1,
          mc.segment2,
          mc.segment3,
          mc.segment4,
          NVL(rctl.quantity_invoiced, rctl.quantity_credited),
          rctl.uom_code,
          rctl.unit_standard_price,
          rctl.unit_selling_price,
          rctl.extended_amount,
          DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0),
          CASE
            WHEN gl_dist.acctd_amount < 0
              AND rctl.quantity_invoiced > 0
              AND cc.segment5 <> '6415'
            THEN gl_dist.acctd_amount
            ELSE 0
          END,
          gl_dist.acctd_amount,
          TRUNC(mmt.transaction_date),
          mmt.transaction_id ) a
        UNION ALL
        /* RMA Returns */
        SELECT
          /*+ INDEX(trx RA_CUSTOMER_TRX_U1) INDEX(hcasa HZ_CUST_ACCT_SITES_U1) */
          'Part3' query_idenitifer,
          rctl.customer_trx_line_id,
          oola.line_id order_line_id,
          hou.name operating_unit,
          cc.segment2 line_of_business,
          cc.segment5 rev_gl_account,
          hcasa.territory,
          jrs.name sales_person,
          hca.cust_account_id,
          hca.account_number,
          hzp.party_name customer,
          rctl.interface_line_attribute1 order_number,
          oola.line_number
          || '.'
          || oola.shipment_number order_line,
          ott.name order_line_type,
          TYPE.description invoice_type,
          trx.trx_date invoice_date,
          trx.trx_number invoice_number,
          rctl.line_number invoice_line,
          rctl.line_type inv_line_type,
          rctl.description line_desc,
          gl_dist.gl_date gl_date,
          mp.organization_code warehouse,
          msi.inventory_item_id,
          msi.segment1 item_number,
          msi.primary_uom_code,
          msi.weight_uom_code,
          msi.unit_weight,
          mc.segment1 inventory_category1,
          mc.segment2 inventory_category2,
          mc.segment3 inventory_category3,
          mc.segment4 inventory_category4,
          NVL(rctl.quantity_invoiced, rctl.quantity_credited) quantity,
          rctl.uom_code,
          rctl.unit_standard_price,
          rctl.unit_selling_price,
          rctl.extended_amount,
          DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0) om_freight,
          CASE
            WHEN gl_dist.acctd_amount < 0
              AND rctl.quantity_invoiced > 0
              AND cc.segment5 <> '6415'
            THEN gl_dist.acctd_amount
            ELSE 0
          END om_credits,
          gl_dist.acctd_amount om_rev,
          CASE
            WHEN mmt.new_cost <> 0
              AND gl_dist.acctd_amount = 0
            THEN (
                  NVL(
                      (SELECT SUM(base_transaction_value) 
                        FROM mtl_transaction_accounts mta
                       WHERE mta.transaction_id = mmt.transaction_id 
                         AND mta.accounting_line_type = 2)
                      ,(SELECT SUM(base_transaction_value) 
                        FROM mtl_transaction_accounts mta
                       WHERE mta.transaction_id = mmt.transaction_id 
                         AND mta.accounting_line_type = 36)
                     )
                 )
            ELSE 0
          END om_replacements,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                    FROM mtl_transaction_accounts 
                   WHERE transaction_id = mmt.transaction_id 
                     AND accounting_line_type = 2)
                  ,(SELECT SUM(base_transaction_value) 
                    FROM mtl_transaction_accounts 
                   WHERE transaction_id = mmt.transaction_id 
                     AND accounting_line_type = 36)
                 )
            ) om_cogs,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 1) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 1) 
                 )
            ) om_material,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 2) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 2) 
                 )
            ) om_material_overhead,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 3) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 3) 
                 )
            ) om_resource,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 4) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 4) 
                 )
            ) om_outside_processing,
            (
              NVL(
                  (SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 2 
                      AND cost_element_id = 5) 
                 ,(SELECT SUM(base_transaction_value) 
                     FROM mtl_transaction_accounts 
                    WHERE transaction_id = mmt.transaction_id 
                      AND accounting_line_type = 36 
                      AND cost_element_id = 5) 
                 )
            ) om_overhead,
          TRUNC(mmt.transaction_date) transaction_date
        FROM apps.ra_cust_trx_types_all TYPE,
          apps.gl_code_combinations cc,
          apps.ra_cust_trx_line_gl_dist_all gl_dist,
          apps.ra_customer_trx_all trx,
          apps.ra_customer_trx_lines_all rctl,
          apps.oe_order_lines_all oola,
          apps.oe_transaction_types_tl ott,
          apps.hr_all_organization_units hou,
          apps.mtl_parameters mp,
          apps.mtl_system_items_b msi,
          apps.hz_cust_accounts hca,
          apps.hz_parties hzp,
          apps.mtl_material_transactions mmt,
          apps.hz_cust_site_uses_all hcsua,
          apps.hz_cust_acct_sites_all hcasa,
          apps.jtf_rs_salesreps jrs,
          apps.mtl_categories mc
        WHERE 1 = 1
          AND trx.complete_flag = 'Y'
          AND hou.organization_id = rctl.org_id
          AND rctl.warehouse_id = msi.organization_id
          AND rctl.inventory_item_id = msi.inventory_item_id
          AND oola.ship_from_org_id = mp.organization_id
          AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
          AND TYPE.org_id = trx.org_id
          AND trx.customer_trx_id = rctl.customer_trx_id
          AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
          AND rctl.interface_line_attribute6 = oola.line_id
          AND rctl.line_type = 'LINE'
          AND cc.code_combination_id = gl_dist.code_combination_id
          AND gl_dist.customer_trx_id = trx.customer_trx_id
          AND ott.transaction_type_id(+) = oola.line_type_id
          AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
          || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
          AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
          || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
          AND trx.org_id = TYPE.org_id
          AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
          AND hzp.party_id = hca.party_id
          AND cc.segment5 IN('3041', '6415') -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
          AND mmt.inventory_item_id = oola.inventory_item_id
          AND mmt.organization_id = oola.ship_from_org_id
          AND mmt.transaction_action_id IN(1, 27)
          AND mmt.transaction_type_id IN(15) -- RMA returns
          AND mmt.trx_source_line_id = oola.line_id
          AND mc.category_id =
          (SELECT mic.category_id
          FROM apps.mtl_item_categories mic,
            apps.mtl_category_sets mcs
          WHERE mcs.category_set_name = 'Inventory'
            AND mic.category_set_id = mcs.category_set_id
            AND mic.organization_id = msi.organization_id
            AND mic.inventory_item_id = msi.inventory_item_id
          )
          AND hcsua.site_use_id = trx.bill_to_site_use_id
          AND hcasa.cust_acct_site_id = hcsua.cust_acct_site_id
          AND jrs.salesrep_id = trx.primary_salesrep_id
          AND jrs.org_id = trx.org_id
        UNION ALL
        /* Freight Lines */
        SELECT
          /*+ INDEX(trx RA_CUSTOMER_TRX_U1) INDEX(hcasa HZ_CUST_ACCT_SITES_U1) */
          'Part4' query_idenitifer,
          rctl.customer_trx_line_id,
          NULL order_line_id,
          hou.name operating_unit,
          cc.segment2 line_of_business,
          cc.segment5 rev_gl_account,
          hcasa.territory,
          jrs.name sales_person,
          hca.cust_account_id,
          hca.account_number,
          hzp.party_name customer,
          rctl.interface_line_attribute1 order_number,
          NULL order_line,
          NULL order_line_type,
          TYPE.description invoice_type,
          trx.trx_date invoice_date,
          trx.trx_number invoice_number,
          rctl.line_number invoice_line,
          rctl.line_type inv_line_type,
          rctl.description line_desc,
          gl_dist.gl_date gl_date,
          NULL warehouse,
          NULL inventory_item_id,
          NULL item_number,
          NULL primary_uom_code,
          NULL weight_uom_code,
          NULL unit_weight,
          NULL inventory_category1,
          NULL inventory_category2,
          NULL inventory_category3,
          NULL inventory_category4,
          NVL(rctl.quantity_invoiced, rctl.quantity_credited) quantity,
          rctl.uom_code,
          rctl.unit_standard_price,
          rctl.unit_selling_price,
          rctl.extended_amount,
          DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0) om_freight,
          CASE
            WHEN gl_dist.acctd_amount < 0
              AND rctl.quantity_invoiced > 0
              AND cc.segment5 <> '6415'
            THEN gl_dist.acctd_amount
            ELSE 0
          END om_credits,
          gl_dist.acctd_amount om_rev,
          0 om_replacements,
          0 om_cogs,
          0 om_material,
          0 om_material_overhead,
          0 om_resource,
          0 om_outside_processing,
          0 om_overhead,
          NULL transaction_date
        FROM apps.ra_cust_trx_types_all TYPE,
          apps.gl_code_combinations cc,
          apps.ra_cust_trx_line_gl_dist_all gl_dist,
          apps.ra_customer_trx_all trx,
          apps.ra_customer_trx_lines_all rctl,
          apps.hr_all_organization_units hou,
          apps.hz_cust_accounts hca,
          apps.hz_parties hzp,
          apps.hz_cust_site_uses_all hcsua,
          apps.hz_cust_acct_sites_all hcasa,
          apps.jtf_rs_salesreps jrs
        WHERE 1 = 1
          AND trx.complete_flag = 'Y'
          AND hou.organization_id = rctl.org_id
          AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
          AND TYPE.org_id = trx.org_id
          AND trx.customer_trx_id = rctl.customer_trx_id
          AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
          AND cc.code_combination_id = gl_dist.code_combination_id
          AND gl_dist.customer_trx_id = trx.customer_trx_id
          AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
          || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
          AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
          || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
          AND trx.org_id = TYPE.org_id
          AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
          AND hzp.party_id = hca.party_id
          AND cc.segment5 IN('3041', '6415') -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
          AND rctl.line_type = 'FREIGHT'
          AND gl_dist.acctd_amount <> 0
          AND hcsua.site_use_id = trx.bill_to_site_use_id
          AND hcasa.cust_acct_site_id = hcsua.cust_acct_site_id
          AND jrs.salesrep_id = trx.primary_salesrep_id
          AND jrs.org_id = trx.org_id
        UNION ALL
        /* Revenue Lines with no item */
        SELECT
          /*+INDEX(trx RA_CUSTOMER_TRX_U1) INDEX(rctl RA_CUSTOMER_TRX_LINES_N2) INDEX(hcasa HZ_CUST_ACCT_SITES_U1) */
          'Part5' query_identifier,
          rctl.customer_trx_line_id,
          NULL order_line_id,
          hou.name operating_unit,
          cc.segment2 line_of_business,
          cc.segment5 rev_gl_account,
          hcasa.territory,
          jrs.name sales_person,
          hca.cust_account_id,
          hca.account_number,
          hzp.party_name customer,
          rctl.interface_line_attribute1 order_number,
          NULL order_line,
          NULL order_line_type,
          TYPE.description invoice_type,
          trx.trx_date invoice_date,
          trx.trx_number invoice_number,
          rctl.line_number invoice_line,
          rctl.line_type inv_line_type,
          rctl.description line_desc,
          gl_dist.gl_date gl_date,
          NULL warehouse,
          NULL inventory_item_id,
          NULL item_number,
          NULL primary_uom_code,
          NULL weight_uom_code,
          NULL unit_weight,
          NULL inventory_category1,
          NULL inventory_category2,
          NULL inventory_category3,
          NULL inventory_category4,
          NVL(rctl.quantity_invoiced, rctl.quantity_credited) quantity,
          rctl.uom_code,
          rctl.unit_standard_price,
          rctl.unit_selling_price,
          rctl.extended_amount,
          DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0) om_freight,
          CASE
            WHEN gl_dist.acctd_amount < 0
              AND rctl.quantity_invoiced > 0
              AND cc.segment5 <> '6415'
            THEN gl_dist.acctd_amount
            ELSE 0
          END om_credits,
          gl_dist.acctd_amount om_rev,
          0 om_replacements,
          0 om_cogs,
          0 om_material,
          0 om_material_overhead,
          0 om_resource,
          0 om_outside_processing,
          0 om_overhead,
          NULL transaction_date
        FROM apps.ra_cust_trx_types_all TYPE,
          apps.gl_code_combinations cc,
          apps.ra_cust_trx_line_gl_dist_all gl_dist,
          apps.ra_customer_trx_all trx,
          apps.ra_customer_trx_lines_all rctl,
          apps.hr_all_organization_units hou,
          apps.hz_cust_accounts hca,
          apps.hz_parties hzp,
          apps.hz_cust_site_uses_all hcsua,
          apps.hz_cust_acct_sites_all hcasa,
          apps.jtf_rs_salesreps jrs
        WHERE 1 = 1
          AND trx.complete_flag = 'Y'
          AND hou.organization_id = rctl.org_id
          AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
          AND TYPE.org_id = trx.org_id
          AND trx.customer_trx_id = rctl.customer_trx_id
          AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
          AND cc.code_combination_id = gl_dist.code_combination_id
          AND gl_dist.customer_trx_id = trx.customer_trx_id
          AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
          || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
          AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
          || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
          AND trx.org_id = TYPE.org_id
          AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
          AND cc.segment5 IN('3041', '6415') -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
          AND rctl.line_type = 'LINE'
          AND rctl.inventory_item_id IS NULL
          AND hzp.party_id = hca.party_id
          AND gl_dist.acctd_amount <> 0
          AND hcsua.site_use_id = trx.bill_to_site_use_id
          AND hcasa.cust_acct_site_id = hcsua.cust_acct_site_id
          AND jrs.salesrep_id = trx.primary_salesrep_id
          AND jrs.org_id = trx.org_id
        UNION ALL
        /* Rev Lines with item, but no material_transaction, example Freight, punch charges and scrap */
        SELECT
          /*+ INDEX(trx RA_CUSTOMER_TRX_U1) INDEX(hcasa HZ_CUST_ACCT_SITES_U1) */
          'Part6' query_idenitifer,
          rctl.customer_trx_line_id,
          oola.line_id order_line_id,
          hou.name operating_unit,
          cc.segment2 line_of_business,
          cc.segment5 rev_gl_account,
          hcasa.territory,
          jrs.name sales_person,
          hca.cust_account_id,
          hca.account_number,
          hzp.party_name customer,
          rctl.interface_line_attribute1 order_number,
          oola.line_number
          || '.'
          || oola.shipment_number order_line,
          ott.name order_line_type,
          TYPE.description invoice_type,
          trx.trx_date invoice_date,
          trx.trx_number invoice_number,
          rctl.line_number invoice_line,
          rctl.line_type inv_line_type,
          rctl.description line_desc,
          gl_dist.gl_date gl_date,
          mp.organization_code warehouse,
          msi.inventory_item_id,
          msi.segment1 item_number,
          msi.primary_uom_code,
          msi.weight_uom_code,
          msi.unit_weight,
          mc.segment1 inventory_category1,
          mc.segment2 inventory_category2,
          mc.segment3 inventory_category3,
          mc.segment4 inventory_category4,
          NVL(rctl.quantity_invoiced, rctl.quantity_credited) quantity,
          rctl.uom_code,
          rctl.unit_standard_price,
          rctl.unit_selling_price,
          rctl.extended_amount,
          DECODE(cc.segment5, '6415', gl_dist.acctd_amount, 0) om_freight,
          CASE
            WHEN gl_dist.acctd_amount < 0
              AND rctl.quantity_invoiced > 0
              AND cc.segment5 <> '6415'
            THEN gl_dist.acctd_amount
            ELSE 0
          END om_credits,
          gl_dist.acctd_amount om_rev,
          0 om_replacements,
          0 om_cogs,
          0 om_material,
          0 om_material_overhead,
          0 om_resource,
          0 om_outside_processing,
          0 om_overhead,
          NULL transaction_date
        FROM apps.ra_cust_trx_types_all TYPE,
          apps.gl_code_combinations cc,
          apps.ra_cust_trx_line_gl_dist_all gl_dist,
          apps.ra_customer_trx_all trx,
          apps.ra_customer_trx_lines_all rctl,
          apps.oe_order_lines_all oola,
          apps.oe_transaction_types_tl ott,
          apps.hr_all_organization_units hou,
          apps.mtl_parameters mp,
          apps.mtl_system_items_b msi,
          apps.hz_cust_accounts hca,
          apps.hz_parties hzp,
          apps.hz_cust_site_uses_all hcsua,
          apps.hz_cust_acct_sites_all hcasa,
          apps.jtf_rs_salesreps jrs,
          apps.mtl_categories mc
        WHERE 1 = 1
          AND trx.complete_flag = 'Y'
          AND hou.organization_id = rctl.org_id
          AND rctl.warehouse_id = msi.organization_id
          AND rctl.inventory_item_id = msi.inventory_item_id
          AND NVL(oola.ship_from_org_id,rctl.warehouse_id) = mp.organization_id
          AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
          AND TYPE.org_id = trx.org_id
          AND trx.customer_trx_id = rctl.customer_trx_id
          AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
          AND rctl.interface_line_attribute6 = oola.line_id(+)
          AND rctl.line_type = 'LINE'
          AND cc.code_combination_id = gl_dist.code_combination_id
          AND gl_dist.customer_trx_id = trx.customer_trx_id
          AND ott.transaction_type_id(+) = oola.line_type_id
          AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
          || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
          AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
          || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
          AND trx.org_id = TYPE.org_id
          AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
          AND hzp.party_id = hca.party_id
          AND cc.segment5 IN('3041', '6415')                   -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
          AND NVL(oola.line_id,0) <> NVL(oola.top_model_line_id, - 1) --Not a assembly/configuarion picked up by part2
          --AND msi.mtl_transactions_enabled_flag = 'N'  --SR52965, Part6 Fix
          --AND oola.shippable_flag != 'N'
          AND gl_dist.acctd_amount <> 0
          AND NOT EXISTS
          (SELECT 'X'
          FROM apps.mtl_material_transactions mmt
          WHERE mmt.inventory_item_id = oola.inventory_item_id
            AND mmt.organization_id = oola.ship_from_org_id
            AND mmt.transaction_action_id IN (1, 27)
            AND mmt.transaction_type_id = 33 -- sales order issues
            AND mmt.source_line_id = oola.line_id
          )
          AND NOT EXISTS     --SR52965, Part6 Fix
          (SELECT 'X'
          FROM apps.mtl_material_transactions mmt
          WHERE mmt.inventory_item_id = oola.inventory_item_id
            AND mmt.organization_id = oola.ship_from_org_id
            AND mmt.transaction_action_id IN (1, 27)
            AND mmt.transaction_type_id = 15 -- RMA
            AND mmt.trx_source_line_id = oola.line_id
          )
          AND mc.category_id =
          (SELECT mic.category_id
          FROM apps.mtl_item_categories mic,
            apps.mtl_category_sets mcs
          WHERE mcs.category_set_name = 'Inventory'
            AND mic.category_set_id = mcs.category_set_id
            AND mic.organization_id = msi.organization_id
            AND mic.inventory_item_id = msi.inventory_item_id
          )
          AND hcsua.site_use_id = trx.bill_to_site_use_id
          AND hcasa.cust_acct_site_id = hcsua.cust_acct_site_id
          AND jrs.salesrep_id = trx.primary_salesrep_id
          AND jrs.org_id = trx.org_id
          )
        GROUP BY query_identifier,
          customer_trx_line_id,
          TRUNC(gl_date, 'MONTH'),
          operating_unit,
          line_of_business,
          rev_gl_account,
          territory,
          sales_person,
          cust_account_id,
          account_number,
          customer,
          order_line_id,
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
          inventory_item_id,
          item_number,
          primary_uom_code,
          weight_uom_code,
          unit_weight,
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
          om_rev
        ) ;
--
--
-- Local Types
--
--
TYPE om_details_tab IS TABLE OF om_detail_cursor%ROWTYPE;

-- Local Variables
ld_start_date   DATE;
ltab_om_details OM_DETAILS_TAB;
--
  BEGIN
--SR76767 - Get date to reset all records not updated after this date
    SELECT SYSDATE
      INTO ld_start_date
      FROM dual;

--SR76767 - Move reset to end of module
-- Reset values for current month, found this to be necessary to correct numbers in salesforce if a record is deleted in Oracle, JSS - 10/22/2014
--      UPDATE bolinf.xxwsb_account_plan_interface
--      SET om_freight = 0,
--        om_credits = 0,
--        om_replacements = 0,
--        om_revenue = 0,
--        om_cost = 0
--      WHERE summary_date = p_summary_date;
--

    --
    -- Detail Data for GL Wand
    --
   DELETE FROM bolinf.xxwsb_account_plan_om_detail
    WHERE summary_date = p_summary_date;
      --
   OPEN om_detail_cursor(p_summary_date);
   LOOP
      FETCH om_detail_cursor BULK COLLECT INTO ltab_om_details LIMIT 1000;
      EXIT WHEN ltab_om_details.COUNT = 0;
      BEGIN
         FORALL ln_index IN INDICES OF ltab_om_details SAVE EXCEPTIONS
          ----  INSERT INTO bolinf.xxwsb_account_plan_om_detail VALUES ltab_om_details(ln_index);
            INSERT INTO xxwsb_account_plan_om_detail VALUES ltab_om_details(ln_index); -- Ravi
      EXCEPTION
         WHEN OTHERS THEN
            IF SQLCODE = -24381
            THEN
               FOR indx IN 1 .. SQL%BULK_EXCEPTIONS.COUNT
               LOOP
                  fnd_file.put_line(fnd_file.LOG, 'Bulk Insert Error: '
                     || SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX || ': ORA-' || LPAD(TO_CHAR(SQL%BULK_EXCEPTIONS (indx).ERROR_CODE), 5, '0'));
               END LOOP;
               g_return_code := 2;
            ELSE
               RAISE;
            END IF;

      END; --ForAll
   END LOOP;
   CLOSE om_detail_cursor;
   COMMIT;
--      INSERT
--      INTO bolinf.xxwsb_account_plan_om_detail
--       (
--         query_identifier,
--         customer_trx_line_id,
--         summary_date,
--         operating_unit,
--         line_of_business,
--         rev_gl_account,
--         territory,
--         sales_person,
--         cust_account_id,
--         account_number,
--         customer,
--         order_number,
--         order_line,
--         order_line_type,
--         invoice_type,
--         invoice_date,
--         invoice_number,
--         invoice_line,
--         inv_line_type,
--         line_desc,
--         gl_date,
--         warehouse,
--         item_number,
--         inventory_category1,
--         inventory_category2,
--         inventory_category3,
--         inventory_category4,
--         quantity,
--         uom_code,
--         unit_standard_price,
--         unit_selling_price,
--         extended_amount,
--         om_freight,
--         om_credits,
--         om_rev,
--         om_replacements,
--         om_cogs,
--         om_gross_profit,
--         om_gross_profit_percent,
--         creation_date,
--         request_id
--       )
--       VALUES
--       (
--         om_detail_rec.query_identifier,
--         om_detail_rec.customer_trx_line_id,
--         operating_unit,
--         line_of_business,
--         rev_gl_account,
--         territory,
--         sales_person,
--         cust_account_id,
--         account_number,
--         customer,
--         order_number,
--         order_line,
--         order_line_type,
--         invoice_type,
--         invoice_date,
--         invoice_number,
--         invoice_line,
--         inv_line_type,
--         line_desc,
--         gl_date,
--         warehouse,
--         item_number,
--         inventory_category1,
--         inventory_category2,
--         inventory_category3,
--         inventory_category4,
--         quantity,
--         uom_code,
--         unit_standard_price,
--         unit_selling_price,
--         extended_amount,
--         om_freight,
--         om_credits,
--         om_rev,
--         om_replacements,
--         om_cogs,
--         om_gross_profit,
--         om_gross_profit_percent,
--         creation_date,
--         request_id
--       ) ;
--    END LOOP;
    COMMIT;
    --
    -- Summary Data for Interface
    --
    FOR om_rec IN om_cursor(p_summary_date)
    LOOP
      UPDATE bolinf.xxwsb_account_plan_interface
      SET om_freight = om_rec.om_freight,
        om_credits = om_rec.om_credits,
        om_replacements = om_rec.om_replacements,
        om_revenue = om_rec.om_revenue,
        om_cost = om_rec.om_cogs
      WHERE customer_account_id = om_rec.cust_account_id
        AND line_of_business = om_rec.line_of_business
        AND summary_date = om_rec.summary_date;
      IF SQL%ROWCOUNT = 0 THEN
        INSERT
        ---INTO bolinf.xxwsb_account_plan_interface
        INTO xxwsb_account_plan_interface -- Ravi
          (
            customer_account_id,
            line_of_business,
            summary_date,
            om_freight,
            om_credits,
            om_replacements,
            om_revenue,
            om_cost
          )
          VALUES
          (
            om_rec.cust_account_id,
            om_rec.line_of_business,
            om_rec.summary_date,
            om_rec.om_freight,
            om_rec.om_credits,
            om_rec.om_replacements,
            om_rec.om_revenue,
            om_rec.om_cogs
          ) ;
      END IF;
    END LOOP;
    COMMIT;
    --SR76767 - Reset values for current month for rows with no data, this will take care of reversed records setting totals back to zero.
    UPDATE bolinf.xxwsb_account_plan_interface
       SET om_freight = 0,
           om_credits = 0,
           om_replacements = 0,
           om_revenue = 0,
           om_cost = 0
     WHERE summary_date = p_summary_date
       AND updated < ld_start_date;
    COMMIT;
  --
  EXCEPTION
  WHEN OTHERS THEN
    RAISE;
  END get_om_data;
  --
  --
  -- get_pa_invoice_data is called for a summary_date (first day of month) and loads OM data
  -- It can also be used to run a manual update of the data for a period.
  --
PROCEDURE get_pa_invoice_data
  (
    p_summary_date DATE
  )
IS
  --
  CURSOR pa_inv_cursor(p_summary_date DATE)
  IS
    SELECT cust_account_id,
      line_of_business,
      summary_date,
      SUM(pa_freight) pa_freight,
      SUM(pa_invoice) pa_invoice
    FROM
      (SELECT hca.cust_account_id,
        DECODE(ppa.project_type, 'WSB BUILDINGS', '10', 'WSB PROJECT SERVICES', '40', '00') line_of_business,
        TRUNC(gl_date, 'MONTH') summary_date,
        cc.segment5 gl_account,
        trx.trx_number invoice,
        rctl.line_number,
        rctl.line_type,
        rctl.inventory_item_id,
        DECODE(rctl.inventory_item_id, 53460, gl_dist.acctd_amount, 0) pa_freight,
        gl_dist.acctd_amount pa_invoice
      FROM apps.ra_cust_trx_types_all TYPE,
        apps.gl_code_combinations cc,
        apps.ra_cust_trx_line_gl_dist_all gl_dist,
        apps.ra_customer_trx_all trx,
        apps.ra_customer_trx_lines_all rctl,
        apps.oe_order_lines_all oola,
        apps.oe_transaction_types_tl ott,
        apps.hr_all_organization_units hou,
        apps.mtl_parameters mp,
        apps.mtl_system_items_b msi,
        apps.hz_cust_accounts hca,
        pa_projects_all ppa
      WHERE 1 = 1
        AND trx.complete_flag = 'Y'
        AND hou.organization_id = rctl.org_id
        AND oola.ship_from_org_id = msi.organization_id(+)
        AND oola.inventory_item_id = msi.inventory_item_id(+)
        AND oola.ship_from_org_id = mp.organization_id(+)
        AND TYPE.cust_trx_type_id = trx.cust_trx_type_id
        AND TYPE.org_id = trx.org_id
        AND trx.customer_trx_id = rctl.customer_trx_id
        AND gl_dist.customer_trx_line_id = rctl.customer_trx_line_id
        AND rctl.interface_line_attribute6 = oola.line_id(+)
        AND cc.code_combination_id = gl_dist.code_combination_id
        AND gl_dist.customer_trx_id = trx.customer_trx_id
        AND ott.transaction_type_id(+) = oola.line_type_id
        AND gl_dist.gl_date BETWEEN TO_DATE(TO_CHAR(p_summary_date, 'YYYY-MM')
        || '-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
        AND TO_DATE(TO_CHAR(LAST_DAY(p_summary_date), 'YYYY-MM-DD')
        || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
        AND trx.org_id = TYPE.org_id
        AND hca.cust_account_id = NVL(trx.sold_to_customer_id, trx.bill_to_customer_id)
        AND cc.segment5 IN('1210', '2405') -- 1210 is Unbilled Revenue and 2405 is Unearned Revenue
        AND ppa.segment1 = rctl.interface_line_attribute1
        AND ppa.project_type <> 'WSB COMMON'
      )
  GROUP BY cust_account_id,
    line_of_business,
    summary_date
  ORDER BY 1,
    2,
    3;
--
--
-- Local Variables
ld_start_date  DATE;
--
  BEGIN
--SR76767 - Get date to reset all records not updated after this date
    SELECT SYSDATE
      INTO ld_start_date
      FROM dual;

--SR76767 - Move reset to end of module
-- Reset values for current month, found this to be necessary to correct numbers in salesforce if a record is deleted in Oracle, JSS - 10/22/2014
--      UPDATE bolinf.xxwsb_account_plan_interface
--      SET pa_invoice = 0,
--          pa_freight = 0
--      WHERE summary_date = p_summary_date;
--
  FOR pa_inv_rec IN pa_inv_cursor(p_summary_date)
  LOOP
    UPDATE bolinf.xxwsb_account_plan_interface
    SET pa_invoice = pa_inv_rec.pa_invoice,
        pa_freight = pa_inv_rec.pa_freight
    WHERE customer_account_id = pa_inv_rec.cust_account_id
      AND line_of_business = pa_inv_rec.line_of_business
      AND summary_date = pa_inv_rec.summary_date;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT
      --INTO bolinf.xxwsb_account_plan_interface
      INTO xxwsb_account_plan_interface -- Ravi
        (
          customer_account_id,
          line_of_business,
          summary_date,
          pa_invoice,
          pa_freight
        )
        VALUES
        (
          pa_inv_rec.cust_account_id,
          pa_inv_rec.line_of_business,
          pa_inv_rec.summary_date,
          pa_inv_rec.pa_invoice,
          pa_inv_rec.pa_freight
        ) ;
    END IF;
  END LOOP;
  COMMIT;
  --SR76767 - Reset values for current month for rows with no data, this will take care of reversed records setting totals back to zero.
  UPDATE bolinf.xxwsb_account_plan_interface
     SET pa_invoice = 0,
         pa_freight = 0
   WHERE summary_date = p_summary_date
     AND updated < ld_start_date;
  COMMIT;

EXCEPTION
WHEN OTHERS THEN
  RAISE;
END get_pa_invoice_data;
--
--
-- get_pa_data is called for a summary_date (first day of month) and loads PA data
-- It can also be used to run a manual update of the data for a period.
--
PROCEDURE get_pa_data
  (
    p_summary_date DATE
  )
IS
  --
  CURSOR pa_cursor(p_summary_date DATE)
  IS
    SELECT ppc.customer_id cust_account_id,
      glcc.segment2 line_of_business,
      TRUNC(pdra.gl_date, 'MONTH') summary_date,
      SUM(pcera.amount *(ppc.customer_bill_split / 100)) pa_revenue
    FROM pa_projects_all ppa,
      pa_draft_revenues_all pdra,
      pa_draft_revenue_items pdri,
      pa_cust_event_rdl_all pcera,
      gl_code_combinations glcc,
      pa_project_customers ppc
    WHERE pdra.project_id = ppa.project_id
      AND pdri.project_id = pdra.project_id
      AND pdri.draft_revenue_num = pdra.draft_revenue_num
      AND pcera.project_id = pdri.project_id
      AND pcera.draft_revenue_num = pdri.draft_revenue_num
      AND pcera.draft_revenue_item_line_num = pdri.line_num
      AND glcc.code_combination_id = pcera.code_combination_id
      AND glcc.segment5 IN('3010', '6415') -- 3010 is Project Revenue, 3041 is OM Revenue, 6415 is Freight
      AND ppa.project_type NOT IN 'WSB COMMON'
      AND ppc.project_id = ppa.project_id
      AND TRUNC(pdra.gl_date) = LAST_DAY(p_summary_date)
    GROUP BY ppc.customer_id,
      glcc.segment2,
      TRUNC(pdra.gl_date, 'MONTH')
    ORDER BY 1,
      2,
      3;
  CURSOR pa_cost_cursor(p_summary_date DATE)
  IS
    SELECT cust_account_id,
      line_of_business,
      summary_date,
      SUM(pa_cost) pa_cost
    FROM
      (SELECT ppc.customer_id cust_account_id,
        glcc.segment2 line_of_business,
        TRUNC(pdra.gl_date, 'MONTH') summary_date,
        SUM((pcera.amount * - 1) *(ppc.customer_bill_split / 100)) pa_cost
      FROM pa_projects_all ppa,
        pa_draft_revenues_all pdra,
        pa_draft_revenue_items pdri,
        pa_cust_event_rdl_all pcera,
        gl_code_combinations glcc,
        pa_project_customers ppc
      WHERE pdra.project_id = ppa.project_id
        AND pdri.project_id = pdra.project_id
        AND pdri.draft_revenue_num = pdra.draft_revenue_num
        AND pcera.project_id = pdri.project_id
        AND pcera.draft_revenue_num = pdri.draft_revenue_num
        AND pcera.draft_revenue_item_line_num = pdri.line_num
        AND glcc.code_combination_id = pcera.code_combination_id
        AND glcc.segment5 IN('4138', '6405', '6410', '4309')
        -- 4138 is Project COGS
        -- 6405 is Freight Out
        -- 6410 is Freight Supplements
        -- 4309 is Contract labor Manufacturing
        AND ppa.project_type NOT IN 'WSB COMMON'
        AND ppc.project_id = ppa.project_id
        AND TRUNC(pdra.gl_date) = LAST_DAY(p_summary_date)
      GROUP BY ppc.customer_id,
        glcc.segment2,
        TRUNC(pdra.gl_date, 'MONTH')
    UNION ALL
    SELECT ppc.customer_id cust_account_id,
      glcc.segment2 line_of_business,
      TRUNC(pcd.gl_date, 'MONTH') summary_date,
      SUM(pae.burden_cost *(ppc.customer_bill_split / 100)) pa_cost
    FROM pa_projects_all ppa,
      pa_project_customers ppc,
      pa_expenditure_items_all pae,
      pa_cost_distribution_lines_all pcd,
      gl_code_combinations glcc
    WHERE ppa.project_type NOT IN 'WSB COMMON'
      AND ppa.project_id = ppc.project_id
      AND ppa.project_id = pae.project_id
      AND pae.project_id = pcd.project_id
      AND pae.expenditure_item_id = pcd.expenditure_item_id
      AND TRUNC(pcd.gl_date, 'MONTH') = TRUNC(p_summary_date, 'MONTH')
      AND pcd.dr_code_combination_id = glcc.code_combination_id
      AND glcc.segment5 IN('4138', '6405', '6410', '4309')
      -- 4138 is Project COGS
      -- 6405 is Freight Out
      -- 6410 is Freight Supplements
      -- 4309 is Contract labor Manufacturing
    GROUP BY ppc.customer_id,
      glcc.segment2,
      TRUNC(pcd.gl_date, 'MONTH')
      )
    GROUP BY cust_account_id,
      line_of_business,
      summary_date
    ORDER BY 1,
      2,
      3;
--
--
-- Local Variables
ld_start_date  DATE;
--
  BEGIN
--SR76767 - Get date to reset all records not updated after this date
    SELECT SYSDATE
      INTO ld_start_date
      FROM dual;

--SR76767 - Move reset to end of module
-- Reset values for current month, found this to be necessary to correct numbers in salesforce if a record is deleted in Oracle, JSS - 10/22/2014
--      UPDATE bolinf.xxwsb_account_plan_interface
--      SET pa_revenue = 0,
--          pa_cost = 0
--      WHERE summary_date = p_summary_date;
--
  FOR pa_rec IN pa_cursor(p_summary_date)
    LOOP
      UPDATE bolinf.xxwsb_account_plan_interface
      SET pa_revenue = pa_rec.pa_revenue
      WHERE customer_account_id = pa_rec.cust_account_id
        AND line_of_business = pa_rec.line_of_business
        AND summary_date = pa_rec.summary_date;
      IF SQL%ROWCOUNT = 0 THEN
        INSERT
        --INTO bolinf.xxwsb_account_plan_interface
        INTO xxwsb_account_plan_interface -- Ravi
          (
            customer_account_id,
            line_of_business,
            summary_date,
            pa_revenue,
            pa_cost
          )
          VALUES
          (
            pa_rec.cust_account_id,
            pa_rec.line_of_business,
            pa_rec.summary_date,
            pa_rec.pa_revenue,
            '0'
          ) ;
      END IF;
    END LOOP;
    COMMIT;
    FOR pa_cost_rec IN pa_cost_cursor
    (
      p_summary_date
    )
    LOOP
      UPDATE bolinf.xxwsb_account_plan_interface
      SET pa_cost = pa_cost_rec.pa_cost
      WHERE customer_account_id = pa_cost_rec.cust_account_id
        AND line_of_business = pa_cost_rec.line_of_business
        AND summary_date = pa_cost_rec.summary_date;
      IF SQL%ROWCOUNT = 0 THEN
        INSERT
      -- INTO bolinf.xxwsb_account_plan_interface
        INTO xxwsb_account_plan_interface -- Ravi
          (
            customer_account_id,
            line_of_business,
            summary_date,
            pa_revenue,
            pa_cost
          )
          VALUES
          (
            pa_cost_rec.cust_account_id,
            pa_cost_rec.line_of_business,
            pa_cost_rec.summary_date,
            '0',
            pa_cost_rec.pa_cost
          ) ;
      END IF;
    END LOOP;
    COMMIT;
    --SR76767 - Reset values for current month for rows with no data, this will take care of reversed records setting totals back to zero.
    UPDATE bolinf.xxwsb_account_plan_interface
       SET pa_revenue = 0,
           pa_cost = 0
     WHERE summary_date = p_summary_date
       AND updated < ld_start_date;
    COMMIT;

  EXCEPTION
  WHEN OTHERS THEN
    RAISE;
  END get_pa_data;
  --
  --
  -- get_data_for_summary_date is called for a summary_date (first day of month) and loads both OM and PA data
  -- It can also be used to run a manual update of the data for a period.
  --
PROCEDURE get_data_for_summary_date
  (
    p_summary_date DATE
  )
IS
  --
BEGIN
  --      get_om_data(p_summary_date);
  --      get_pa_invoice_data(p_summary_date);
  --      get_pa_data(p_summary_date);
  --      COMMIT;
  fnd_file.put_line(fnd_file.LOG, 'Summary Date: ' || TO_CHAR(p_summary_date, 'DD-MON-YYYY')) ;
  fnd_file.put_line(fnd_file.LOG, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ' - Starting get_om_data') ;
  COMMIT;

  /* Formatted on 6/28/2024 3:20:59 PM (QP5 v5.401) */

 -- fnd_file.put_line(fnd_file.LOG, 'GK' ||'Before Insert') ;
--  begin
--INSERT INTO xxwsb_account_plan_interface (customer_account_id,
--                                                 line_of_business,
--                                                 summary_date,
--                                                 pa_invoice,
--                                                 pa_freight)
--     VALUES (9700,
--             10,
--             SYSDATE,
--             1,
--             1);
--             COMMIT;
--
--             exception when others then null;
--             fnd_file.put_line(fnd_file.LOG, 'GK' ||SQLERRM) ;
--             end;
--             fnd_file.put_line(fnd_file.LOG, 'GK' ||'AFtr Insert') ;

  get_om_data(p_summary_date) ;
  fnd_file.put_line(fnd_file.LOG, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ' - Starting get_pa_invoice_data') ;
  COMMIT;

  get_pa_invoice_data(p_summary_date) ;
  fnd_file.put_line(fnd_file.LOG, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ' - Starting get_pa_data') ;
  COMMIT;
  get_pa_data(p_summary_date) ;
  fnd_file.put_line(fnd_file.LOG, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ' - Complete') ;
  fnd_file.put_line(fnd_file.LOG, '-------------------------------------------') ;
  COMMIT;
EXCEPTION
WHEN OTHERS THEN
  RAISE;
END get_data_for_summary_date;
--
-- get_data is called by a concurrent program
-- If the parameter date is NULL then it runs on open GL and AR periods
--
PROCEDURE get_data
  (
    errbuf OUT VARCHAR2,
    retcode OUT NUMBER,
    p_summary_date IN VARCHAR2 DEFAULT NULL
  )
IS
  --
  CURSOR period_cursor
  IS
    SELECT DISTINCT period_name
    FROM apps.gl_period_statuses
    WHERE(closing_status = 'O'
      OR(closing_status = 'C'
      AND last_update_date > TRUNC(SYSDATE) - 7) -- Closed within 7 days
      )
      AND application_id IN
      (SELECT application_id
      FROM apps.fnd_application
      WHERE application_short_name IN('SQLGL', 'AR')
      )
  ORDER BY 1;
  --
  l_summary_date DATE;
  l_errcode      NUMBER;
  --
BEGIN
  g_return_code := 0;
  IF p_summary_date IS NULL THEN
    FOR period_rec IN period_cursor
    LOOP
      BEGIN
        l_summary_date := TO_DATE('01-' || period_rec.period_name, 'DD-MON-RR') ;
        get_data_for_summary_date(l_summary_date) ;
      EXCEPTION
      WHEN OTHERS THEN
        l_errcode := SQLCODE;
        IF l_errcode <= - 1810 AND l_errcode >= - 1861 THEN --Date exceptions
          fnd_file.put_line(fnd_file.LOG, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ' - Skipping: ' || period_rec.period_name) ;
        ELSE
          RAISE;
        END IF;
      END;
    END LOOP;
  ELSE
    l_summary_date := TO_DATE('01-' || TO_CHAR(TO_DATE(p_summary_date), 'MON-YYYY'), 'DD-MON-YYYY') ;
    get_data_for_summary_date(l_summary_date) ;
  END IF;
  --SR 50626-Added by PRAO, Update Account Number based on the account ID
  UPDATE bolinf.xxwsb_account_plan_interface a
  SET account_number =
    (SELECT account_number
    FROM hz_cust_accounts_all
    WHERE cust_account_id = a.customer_account_id
    )
  WHERE account_number IS NULL;
  ----
  errbuf := NULL;
  retcode := g_return_code;
  COMMIT;
  ---
EXCEPTION
WHEN OTHERS THEN
  errbuf := SQLERRM;
  retcode := 2;
  COMMIT;
END get_data;
--
END xxwsb_account_plan;