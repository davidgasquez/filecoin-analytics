with state_market_deals_metrics as (
    select distinct
        client_id,
        count(distinct deal_id) as total_deals,
        count(distinct provider_id) as total_unique_providers,
        count(distinct piece_cid) as total_unique_piece_cids,
        sum(unpadded_piece_size_tib) as total_data_uploaded_tibs,
        sum(case when is_active then unpadded_piece_size_tib else 0 end) as total_active_data_uploaded_tibs,
        count(case when is_active then 1 else 0 end) as total_active_deals,
        count(case when is_verified then 1 else 0 end) as total_verified_deals,
        count(case when is_active and is_verified then 1 else 0 end) as total_active_verified_deals,
        min(sector_start_at) as first_deal_at,
        min(case when is_active then sector_start_at else null end) as first_active_deal_at,
        max(sector_start_at) as last_deal_at,
        max(case when is_active then sector_start_at else null end) as last_active_deal_at,
        sum(case when sector_start_at > current_date() - interval '30 days' then unpadded_piece_size_tib else 0 end) as data_uploaded_tibs_30d
    from {{ ref("filecoin_state_market_deals") }}
    where sector_start_epoch is not null
    group by 1
),

datacap_clients as (
    select distinct
        addressid as client_id,
        nullif(address, '') as client_address,
        nullif(name, '') as client_name,
        orgname as organization_name,
        nullif(region, '') as region,
        nullif(industry, '') as industry,
        initialallowance as initial_datacap,
        coalesce(try_cast(allowance as numeric), 0) as current_datacap,
        verifieraddressid as verifier_id,
    from {{ source("raw_assets", "raw_datacapstats_verified_clients") }}
    qualify row_number() over (partition by addressid order by createdatheight desc) = 1
)

select
    m.client_id,
    c.client_address,
    c.client_name,
    c.organization_name,
    c.region,
    c.industry,
    c.initial_datacap,
    c.current_datacap,
    c.verifier_id,
    m.total_deals,
    m.total_unique_providers,
    m.total_unique_piece_cids,
    m.total_data_uploaded_tibs,
    m.total_active_data_uploaded_tibs,
    m.total_verified_deals,
    m.total_active_deals,
    m.total_active_verified_deals,
    m.first_deal_at,
    m.last_deal_at,
    m.first_active_deal_at,
    m.last_active_deal_at,
    m.data_uploaded_tibs_30d
from state_market_deals_metrics m
left join datacap_clients c on m.client_id = c.client_id
