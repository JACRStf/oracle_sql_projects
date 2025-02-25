/* Tonnage Analysis Report - Query */
SELECT 
       a.org org,
       SUM(a.Frame) Frame,
       SUM(a.Non_Frame) Non_Frame,
       SUM(a.OSP_Frame) OSP_Frame,
       SUM(a.OSP_Non_Frame) OSP_Non_Frame,
        SUM(a.OSP_Hi_Tensile) OSP_Hi_Tensile,
       SUM(a.Hi_Tensile) Hi_Tensile,
      SUM(a.Trim) Trim,
       SUM(a.OSP_Trim) OSP_Trim,
       SUM(a.sheeting) Sheeting,
       SUM(a.OSP_Sheeting) OSP_Sheeting,
       ABS(SUM(a.ship_confirmed)) ship_confirmed
FROM 
(SELECT 
      org.organization_code org,
      SUM(DECODE(ffv.attribute2, 'Frame',             
              XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1))
              ,0)) Frame,
  SUM(DECODE(ffv.attribute2, 'Hi-Tensile',             
              XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1))
              ,0)) Hi_Tensile,
     SUM(DECODE(ffv.attribute2, 'Trim',             
              XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1))
              ,0)) Trim,
     SUM(DECODE(ffv.attribute2, 'Sheeting',             
              XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1))
              ,0)) Sheeting,
      SUM(DECODE(ffv.attribute2, 'Hi-Tensile',          
                        XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1)),                           
              'Trim' , XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1)),
            'Sheeting', XXWSB_INV_get_uom_rate( mmt.inventory_item_id,mmt.transaction_uom, 'LB') * (mmt.primary_quantity * NVL(msi.unit_weight,1)),  0)) Non_Frame, 
      0 OSP_Frame,
      0 OSP_Hi_Tensile,
      0 OSP_Trim,
      0 OSP_Sheeting,
      0 OSP_Non_Frame,
0  ship_confirmed
FROM   fnd_flex_values ffv,
     fnd_flex_value_sets ffvs,
     mtl_categories mca,
     mtl_item_categories mic,
     mtl_system_items msi,
     mtl_material_transactions mmt,
     mtl_parameters org
     --org_acct_periods oap
     &P_CAT_TAB
WHERE &P_CAT_WHERE
   --AND oap.period_name = :P_PERIOD_NAME
  AND org.organization_id =mmt. organization_id
  --AND mmt.organization_id = oap.organization_id
  --AND mmt.transaction_date >= trunc(oap.period_start_date)
  --AND mmt.transaction_date <  trunc(oap.schedule_close_date)
  AND trunc(mmt.transaction_date) >= trunc(:p_start_date)
  AND trunc(mmt.transaction_date) <= trunc(:p_end_date)
  AND mic.organization_id   = mmt.organization_id
  AND mic.inventory_item_id = mmt.inventory_item_id  
  AND msi.organization_id   = mmt.organization_id
  AND msi.inventory_item_id = mmt.inventory_item_id  
  AND mca.category_id       = mic.category_id
  AND mca.structure_id = 101
  AND ffv.flex_value = mca.segment1
  AND ffvs.flex_value_set_id = ffv.flex_value_set_id
  AND ffvs.flex_value_set_name = 'WSB_PRODUCT_LINE_CATEGORY'     
  AND mmt.transaction_type_id =44 -- wip completion
  AND mmt.transaction_source_type_id = 5 --in ( 2) 
  AND mmt.transaction_action_id = 31
&P_WHERE
&C_WHERE_CAT
GROUP BY org.organization_code
UNION 
SELECT 
         org.organization_code org,
         0 Frame,
          0 Hi_Tensile,
         0 Trim,
         0 Sheeting,
         0 Non_Frame,
         SUM(DECODE(ffv.attribute2, 'Frame',             
             (NVL(pll.quantity,0) - NVL(pll.quantity_cancelled,0))
          ,0)) OSP_Frame,

          SUM(DECODE(ffv.attribute2, 'Hi-Tensile',          
                       (NVL(pll.quantity,0)- NVL(pll.quantity_cancelled,0)),0))OSP_Hi_Tensile,
          SUM(DECODE(ffv.attribute2, 'Trim',          
                       (NVL(pll.quantity,0)- NVL(pll.quantity_cancelled,0)),0))OSP_Trim,
          SUM(DECODE(ffv.attribute2, 'Sheeting',          
                       (NVL(pll.quantity,0)- NVL(pll.quantity_cancelled,0)),0))OSP_Sheeting,

         SUM(DECODE(ffv.attribute2, 'Hi-Tensile',          
                       (NVL(pll.quantity,0)- NVL(pll.quantity_cancelled,0)),                           
              'Trim' ,  (NVL(pll.quantity,0)- NVL(pll.quantity_cancelled,0)),
            'Sheeting', (NVL(pll.quantity,0)- NVL(pll.quantity_cancelled,0)),
          0)) OSP_Non_Frame,
0  ship_confirmed
FROM   po_vendors             pov
,      po_line_types                plt
,      po_line_locations_all     pll
,      po_lines_all                   pol
,      po_headers_all             poh
,      po_distributions_all       pod
,      bom_resources             br1
,      mtl_system_items          msi
,      wip_entities                   we
,      wip_discrete_jobs         wdj
,      fnd_flex_values            ffv
,      fnd_flex_value_sets     ffvs
,      mtl_categories              mca
,      mtl_item_categories      mic
,      mtl_parameters             org
       &P_CAT_TAB
WHERE  &P_CAT_WHERE
AND    poh.po_header_id = pol.po_header_id
AND    DECODE(poh.type_lookup_code, 'STANDARD', NVL(poh.closed_code,'OPEN'),
                                                       'PLANNED', NVL(poh.closed_code,'OPEN')) = 'OPEN'
AND    DECODE(poh.type_lookup_code, 'STANDARD', NVL(pol.closed_code,'OPEN'),
                                                       'PLANNED', NVL(pol.closed_code,'OPEN'),
                                                       'BLANKET','OPEN') = 'OPEN' 
AND    NVL(poh.cancel_flag,'N') = 'N'
AND    NVL(pol.cancel_flag,'N') = 'N'
AND    poh.vendor_id = pov.vendor_id
AND    pol.po_line_id = pll.po_line_id
AND    pol.line_type_id = plt.line_type_id
AND    pll.shipment_type IN ('STANDARD','SCHEDULED','BLANKET')
AND    NVL(pll.approved_flag,'N') = 'Y'
AND    NVL(pll.cancel_flag,'N') = 'N'
AND    poh.type_lookup_code in ('BLANKET','STANDARD','PLANNED')
AND    NVL(pll.closed_code,'OPEN') IN ('OPEN','CLOSED FOR INVOICE')
AND    NVL(pll.quantity,0) - NVL(pll.quantity_cancelled,0) > NVL(pll.quantity_received,0)
AND    pll.line_Location_id = pod.line_location_id
AND    pod.wip_entity_id = wdj.wip_entity_id
AND    pod.wip_entity_id = we.wip_entity_id
AND    pod.bom_resource_id = br1.resource_id 
AND    wdj.primary_item_id = msi.inventory_item_id
AND    wdj.organization_id = msi.organization_id
AND    mca.category_id = mic.category_id
AND    mic.category_set_id = 1
AND    org.organization_id = wdj.organization_id
AND    ffvs.flex_value_set_id = 1005933   -- ffvs.flex_value_set_name = 'WSB_PRODUCT_LINE_CATEGORY'
AND    ffv.flex_value_set_id = ffvs.flex_value_set_id
AND    ffv.flex_value = mca.segment1
AND    wdj.primary_item_id = mic.inventory_item_id
AND    wdj.organization_id = mic.organization_id
AND    wdj.status_type = 3
AND    br1.attribute6 = 'Y' 
&P_WHERE
&C_WHERE_CAT
GROUP BY org.organization_code
UNION
SELECT 
      org.organization_code org,
      0 Frame,
      0  Hi_Tensile,
     0 Trim,
     0 Sheeting,
     0 Non_Frame, 
      0 OSP_Frame,
      0 OSP_Hi_Tensile,
      0 OSP_Trim,
      0 OSP_Sheeting,
      0 OSP_Non_Frame,
      sum(XXWSB_INV_get_uom_rate(mmt.inventory_item_id,mmt.transaction_uom,'LB')*(mmt.primary_quantity*nvl(msi.unit_weight,1))) ship_confirmed
     
FROM   fnd_flex_values ffv,
     fnd_flex_value_sets ffvs,
     mtl_categories mca,
     mtl_item_categories mic,
     mtl_system_items msi,
     mtl_material_transactions mmt,
     mtl_parameters org
     --org_acct_periods oap
     &P_CAT_TAB
WHERE &P_CAT_WHERE
   --AND oap.period_name = :P_PERIOD_NAME
  AND org.organization_id =mmt. organization_id
  --AND mmt.organization_id = oap.organization_id
  --AND mmt.transaction_date >= trunc(oap.period_start_date)
  --AND mmt.transaction_date <  trunc(oap.schedule_close_date)
  AND trunc(mmt.transaction_date) >= trunc(:p_start_date)
  AND trunc(mmt.transaction_date) <= trunc(:p_end_date)
  AND mic.organization_id   = mmt.organization_id
  AND mic.inventory_item_id = mmt.inventory_item_id  
  AND msi.organization_id   = mmt.organization_id
  AND msi.inventory_item_id = mmt.inventory_item_id  
  AND mca.category_id       = mic.category_id
  AND mca.structure_id = 101
  AND ffv.flex_value = mca.segment1

AND mmt.transaction_type_id in (33,62) -- SO issue, internal order ship
AND mmt.transaction_source_type_id in (2,8)
AND mmt.transaction_action_id in (1,21)

  AND ffvs.flex_value_set_id = ffv.flex_value_set_id
  AND ffvs.flex_value_set_name = 'WSB_PRODUCT_LINE_CATEGORY'     
  --AND mmt.transaction_type_id = 33-- wip completion
  --AND mmt.transaction_source_type_id =  2--in ( 2) 
  --AND mmt.transaction_action_id = 1
&P_WHERE
&C_WHERE_CAT
GROUP BY org.organization_code
) a
GROUP BY a.org 


------------------------
P_CAT_TAB -- , mtl_category_sets mcs1, mtl_item_categories mic1, mtl_categories mc1
C_WHERE_CAT--
'and msi.inventory_item_id = mic1.inventory_item_id
  and msi.organization_id = mic1.organization_id 
and mic1.category_id = mc1.category_id 
and mcs1.structure_id = '||:P_STRUCT_NUM
||' and mcs1.category_set_id = mic1.category_set_id
 and mic1.category_set_id = '||to_number(:P_CATEGORY_SET_ID)); 

-----------------------
