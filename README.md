# Ecommerce Currency Conversion - Fixed Analytics™

A **server-side Google Tag Manager (sGTM) variable template** that converts monetary event values from one currency to another, with automatic FX API fallback and daily exchange-rate caching.

**Developer:** [Javier Garijo](https://github.com/javier-garijo-gtm)  
**Brand:** Fixed Analytics™

## Why use it?

Ecommerce stores often receive purchases in different **presentment currencies**, while revenue and profitability reporting requires a consistent **shop currency**.

This template converts monetary values such as `ecommerce.value` or `value` into the target currency.

It is especially useful for sending **shop-currency monetary values to Google Analytics 4 and BigQuery through custom event parameters in server-side GA4 tags**, enabling consistent revenue and profitability analysis across multiple markets.

**The template returns the converted monetary amount, not the exchange rate.** No additional multiplication variable is required.

## Installation

1. Open your Google Tag Manager **server container**.
2. Navigate to **Templates → Variable Templates → New → Import**.
3. Import `template.tpl` and save the template.
4. Create a new variable using **Ecommerce Currency Conversion - Fixed Analytics**.
5. Configure the fields and test in sGTM Preview.

## Configuration

| Setting | Description |
|---|---|
| Event Currency Configuration | Map events such as `purchase`, `offline_purchase`, and `refund` to their source currencies. |
| Convert From Currency | Source currency, e.g. `USD` or `{{Event Data - currency}}`. |
| Convert To Currency | Shared target currency, typically the shop currency, e.g. `EUR`. |
| Monetary Value to Convert | GTM variable containing the monetary value, e.g. `{{Event Data - value}}`. |
| Decimal Places | `2 Decimals (Default)` or `No Decimals`. |
| Logging Preferences | Disable Logging, Debug Mode (default), or Always Log. |

Unconfigured events return `undefined`.

## Conversion examples

The calculation is:

**Converted amount = original monetary value × exchange rate**

Using illustrative exchange rates:

| Original amount | FX rate | Converted output |
|---|---|---|
| 95 USD → EUR | 0.89 | 84.55 EUR |
| 95 EUR → USD | 1.12 | 106.40 USD |
| 95 EUR → EUR | 1.00 | 95.00 EUR |

### Numeric output and decimal places

The template rounds the converted amount to two decimals by default and returns a **numeric value**.

For example, `102.80` may appear as `102.8` in GTM Preview. These represent exactly the same numeric amount because JavaScript numbers do not preserve trailing zeroes.

For GA4 and BigQuery, keeping the value numeric is preferable. Apply display formatting in your reporting tool when two visible decimal places are required.

## GA4 → BigQuery integration

The template's main use case is to retain the original ecommerce transaction value while sending an additional value in the store's shop currency.

For example, an order has a value of **95 USD**, while the shop currency is **EUR**. At an illustrative FX rate of `0.89`, the converted value is **84.55 EUR**.

Configure these parameters in your **server-side GA4 event tag**:

| GA4 event parameter | Value |
|---|---|
| `value` | `95` |
| `currency` | `USD` |
| `value_shop_currency` | `{{Ecommerce Currency Conversion}}` |
| `shop_currency` | `EUR` |

The `value_shop_currency` parameter will contain the numeric converted amount, such as `84.55`.

**Keep GA4's standard `value` and `currency` parameters unchanged.** Add the converted shop-currency values as separate custom parameters.

These additional parameters will be available in BigQuery's `event_params` array, allowing revenue and profitability reporting in a consistent currency.

### BigQuery SQL example

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_day,
  ecommerce.transaction_id,
  (
    SELECT COALESCE(
      p.value.double_value,
      p.value.float_value,
      CAST(p.value.int_value AS FLOAT64),
      SAFE_CAST(p.value.string_value AS FLOAT64)
    )
    FROM UNNEST(event_params) AS p
    WHERE p.key = 'value_shop_currency'
    LIMIT 1
  ) AS value_shop_currency,
  (
    SELECT p.value.string_value
    FROM UNNEST(event_params) AS p
    WHERE p.key = 'shop_currency'
    LIMIT 1
  ) AS shop_currency
FROM `YOUR_PROJECT.YOUR_GA4_DATASET.events_*`
WHERE event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));
```

Replace the project and GA4 dataset with your own. Deduplicate transactions when necessary before aggregating revenue.

## FX providers

The template uses two public exchange-rate providers:

**Primary:** [ExchangeRate-API Open Access](https://www.exchangerate-api.com/docs/free)  
`https://open.er-api.com/v6/latest/{FROM}`

**Fallback:** [fawazahmed0 Exchange API](https://github.com/fawazahmed0/exchange-api)  
`https://latest.currency-api.pages.dev/v1/currencies/{from}.json`

The fallback provider is used automatically if the primary provider fails or returns an invalid rate.

## Additional functionality

- Full-precision FX rates cached per currency pair for the current UTC day.
- Conversion result rounded to two decimals by default.
- Same-currency conversion without external API calls.
- Negative monetary values supported for refunds.
- Invalid monetary inputs, missing event configurations, and unsuccessful FX lookups return `undefined`.
- Configurable logging for debugging and monitoring.

**Note:** Exchange rates reflect the providers' latest published quotations, not historical transaction-time rates or payment-settlement rates.

## Developer

Developed and maintained by **Javier Garijo**.

GitHub: [github.com/javier-garijo-gtm](https://github.com/javier-garijo-gtm)

**Fixed Analytics™**
