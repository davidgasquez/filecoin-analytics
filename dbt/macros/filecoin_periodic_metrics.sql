{% macro filecoin_periodic_metrics(period) %}

with date_calendar as (
    select
        cast(range as date) as date
    from range(date '2020-10-01', current_date(), interval '1 {{ period }}')
),

deal_metrics as (
    select
        time_bucket(interval '1 {{ period }}', sector_start_at, date '2020-10-01') as date,
        sum(padded_piece_size_tibs / 1024) as onboarded_data_pibs,
        sum(padded_piece_size_tibs / 1024) filter (piece_client_replication_order = 1 and piece_provider_replication_order = 1) as unique_data_onboarded_data_pibs,
        unique_data_onboarded_data_pibs / onboarded_data_pibs as unique_data_onboarded_ratio,
        approx_count_distinct(deal_id) as deals,
        approx_count_distinct(piece_cid) as unique_piece_cids,
        approx_count_distinct(client_id) as unique_deal_making_clients,
        approx_count_distinct(provider_id) as unique_deal_making_providers
    from {{ ref('filecoin_state_market_deals') }}
    where 1 = 1
        and sector_start_at is not null
    group by 1
    order by 1
),

users_with_active_deals as (
    select
        dc.date,
        sum(padded_piece_size_tibs / 1024) as data_on_active_deals_pibs,
        sum(padded_piece_size_tibs / 1024) filter (piece_client_replication_order = 1 and piece_provider_replication_order = 1) as unique_data_on_active_deals_pibs,
        approx_count_distinct(deals.deal_id) as active_deals,
        approx_count_distinct(deals.client_id) as clients_with_active_deals,
        approx_count_distinct(deals.provider_id) as providers_with_active_deals
    from date_calendar as dc
    left join {{ ref('filecoin_state_market_deals') }} as deals
        on (deals.sector_start_at <= dc.date + interval '1 {{ period }}')
        and (least(deals.end_at, deals.slash_at) >= dc.date)
    group by dc.date
),

deal_ends as (
    select
        time_bucket(interval '1 {{ period }}', end_at, date '2020-10-01') as date,
        approx_count_distinct(deal_id) as deal_ends,
        coalesce(sum(padded_piece_size_tibs / 1024), 0) as ended_data_pibs
    from {{ ref('filecoin_state_market_deals') }}
    where 1 = 1
        and sector_start_at is not null
    group by 1
    order by 1
),

deal_slashes as (
    select
        time_bucket(interval '1 {{ period }}', slash_at, date '2020-10-01') as date,
        approx_count_distinct(deal_id) as deal_slashes,
        coalesce(sum(padded_piece_size_tibs / 1024), 0) as slashed_data_pibs
    from {{ ref('filecoin_state_market_deals') }}
    where 1 = 1
        and sector_start_at is not null
    group by 1
    order by 1
),

provider_metrics as (
    select
        date,
        sum(raw_power_pibs) as raw_power_pibs,
        sum(quality_adjusted_power_pibs) as quality_adjusted_power_pibs,
        sum(verified_data_power_pibs) as verified_data_power_pibs,
        sum(balance) as total_storage_providers_balance,
        sum(initial_pledge) as total_storage_providers_initial_pledge,
        sum(locked_funds) as total_storage_providers_locked_funds,
        sum(pre_commit_deposits) as total_storage_providers_pre_commit_deposits,
        sum(provider_collateral) as total_storage_providers_collateral,
        sum(fee_debt) as total_storage_providers_fee_debt,
        sum(total_blocks_mined) as total_storage_providers_blocks_mined,
        sum(total_win_count) as total_storage_providers_win_count,
        sum(total_rewards) as total_storage_providers_rewards,
        sum(total_sector_onboarded_count) as total_storage_providers_sectors_onboarded,
        sum(total_terminated_raw_power_tibs / 1024) as terminated_raw_power_pibs,
        sum(total_terminated_quality_adjusted_power_tibs / 1024) as terminated_quality_adjusted_power_pibs,
        sum(daily_sector_onboarding_count) as sector_onboarding_count,
        sum(daily_sector_onboarding_raw_power_tibs) / 1024 as sector_onboarding_raw_power_pibs,
        sum(daily_sector_onboarding_quality_adjusted_power_tibs) / 1024 as sector_onboarding_quality_adjusted_power_pibs,
        sum(daily_new_terminated_raw_power_tibs) / 1024 as sector_terminated_raw_power_pibs,
        sum(daily_new_terminated_quality_adjusted_power_tibs) / 1024 as sector_terminated_quality_adjusted_power_pibs,
        sum(daily_new_extend_raw_power_tibs) / 1024 as sector_extended_raw_power_pibs,
        sum(daily_new_extend_quality_adjusted_power_tibs) / 1024 as sector_extended_quality_adjusted_power_pibs
    from {{ ref('filecoin_daily_storage_providers_metrics') }}
    where 1 = 1
    group by 1
    order by 1
),

new_clients as (
    select
        time_bucket(interval '1 {{ period }}', first_deal_at, date '2020-10-01') as date,
        coalesce(approx_count_distinct(client_id), 0) as new_client_ids
    from {{ ref('filecoin_clients') }}
    group by 1
    order by 1 desc
),

new_providers as (
    select
        time_bucket(interval '1 {{ period }}', first_deal_at, date '2020-10-01') as date,
        coalesce(approx_count_distinct(provider_id), 0) as new_provider_ids
    from {{ ref('filecoin_storage_providers') }}
    group by 1
    order by 1 desc
),

network_user_address_count as (
    select
        time_bucket(interval '1 {{ period }}', cast(stat_date as date), date '2020-10-01') as date,
        avg(total_address_count) as total_address_count,
        avg(active_address_count_daily) as active_address_count_daily,
        avg(active_address_count_weekly) as active_address_count_weekly,
        avg(active_address_count_monthly) as active_address_count_monthly,
        avg(total_address_count_100) as total_address_count_100,
        avg(total_address_count_1000) as total_address_count_1000,
        avg(total_address_count_10000) as total_address_count_10000,
        avg(total_address_count_100000) as total_address_count_100000,
        avg(total_address_count_1000000) as total_address_count_1000000
    from {{ source("raw_assets", "raw_network_user_address_count") }}
    group by 1
    order by 1 desc
),

new_pieces as (
    select
        time_bucket(interval '1 {{ period }}', piece_first_sector_start_at, date '2020-10-01') as date,
        coalesce(approx_count_distinct(piece_cid), 0) as new_piece_cids
    from {{ ref('filecoin_state_market_deals') }}
    group by 1
    order by 1 desc
),

retrieval_metrics as (
    select
        time_bucket(interval '1 {{ period }}', date, date '2020-10-01') as date,
        mean(success_rate) as mean_spark_retrieval_success_rate,
        approx_count_distinct(provider_id) filter (success_rate > 0) as providers_with_successful_retrieval,
        approx_count_distinct(provider_id) as providers_with_retrieval_attempts
    from {{ source("raw_assets", "raw_spark_retrieval_success_rate") }}
    group by 1
),

providers_adding_capacity as (
    with pwp as (
        select
            provider_id,
            min(date) as started_providing_power_date
        from {{ ref('filecoin_daily_storage_providers_metrics') }}
        where raw_power_pibs > 0
        group by provider_id
    )

    select
        time_bucket(interval '1 {{ period }}', started_providing_power_date, date '2020-10-01') as date,
        count(distinct provider_id) as new_providers_providing_capacity
    from pwp
    group by 1
),

circulating_supply as (
    select
        cast(stat_date as date) as date,
        circulating_fil,
        mined_fil,
        vested_fil,
        reserve_disbursed_fil,
        locked_fil,
        burnt_fil
    from {{ source("raw_assets", "raw_circulating_supply") }}
    order by date desc
)

select
    date_calendar.date,
    onboarded_data_pibs,
    unique_data_onboarded_data_pibs,
    unique_data_onboarded_ratio,
    deals,
    unique_piece_cids,
    unique_deal_making_clients,
    unique_deal_making_providers,
    data_on_active_deals_pibs,
    unique_data_on_active_deals_pibs,
    active_deals,
    clients_with_active_deals,
    providers_with_active_deals,
    deal_ends,
    ended_data_pibs,
    deal_slashes,
    slashed_data_pibs,
    raw_power_pibs,
    quality_adjusted_power_pibs,
    verified_data_power_pibs,
    total_storage_providers_balance,
    total_storage_providers_initial_pledge,
    total_storage_providers_locked_funds,
    total_storage_providers_pre_commit_deposits,
    total_storage_providers_collateral,
    total_storage_providers_fee_debt,
    total_storage_providers_blocks_mined,
    total_storage_providers_win_count,
    total_storage_providers_rewards,
    total_storage_providers_sectors_onboarded,
    terminated_raw_power_pibs,
    terminated_quality_adjusted_power_pibs,
    data_on_active_deals_pibs / raw_power_pibs as network_utilization_ratio,
    sector_onboarding_count,
    sector_onboarding_raw_power_pibs,
    sector_onboarding_quality_adjusted_power_pibs,
    sector_terminated_raw_power_pibs,
    sector_terminated_quality_adjusted_power_pibs,
    sector_extended_raw_power_pibs,
    sector_extended_quality_adjusted_power_pibs,
    new_client_ids,
    new_provider_ids,
    active_address_count_daily,
    active_address_count_weekly,
    active_address_count_monthly,
    total_address_count,
    total_address_count_100,
    total_address_count_1000,
    total_address_count_10000,
    total_address_count_100000,
    total_address_count_1000000,
    new_piece_cids,
    mean_spark_retrieval_success_rate,
    providers_with_successful_retrieval,
    providers_with_retrieval_attempts,
    new_providers_providing_capacity,
    circulating_fil,
    mined_fil,
    vested_fil,
    reserve_disbursed_fil,
    locked_fil,
    burnt_fil
from date_calendar
left join deal_metrics on date_calendar.date = deal_metrics.date
left join users_with_active_deals on date_calendar.date = users_with_active_deals.date
left join deal_ends on date_calendar.date = deal_ends.date
left join deal_slashes on date_calendar.date = deal_slashes.date
left join provider_metrics on date_calendar.date = provider_metrics.date
left join new_clients on date_calendar.date = new_clients.date
left join new_providers on date_calendar.date = new_providers.date
left join network_user_address_count on date_calendar.date = network_user_address_count.date
left join new_pieces on date_calendar.date = new_pieces.date
left join retrieval_metrics on date_calendar.date = retrieval_metrics.date
left join providers_adding_capacity on date_calendar.date = providers_adding_capacity.date
left join circulating_supply on date_calendar.date = circulating_supply.date
order by date_calendar.date desc

{% endmacro %}
