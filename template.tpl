___TERMS_OF_SERVICE___

By creating or modifying this file you agree to Google Tag Manager's Community
Template Gallery Developer Terms of Service available at
https://developers.google.com/tag-manager/gallery-tos (or such other URL as
Google may provide), as modified from time to time.


___INFO___

{
  "type": "MACRO",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "categories": [
    "UTILITY",
    "ANALYTICS",
    "DATA_WAREHOUSING"
  ],
  "displayName": "Ecommerce Currency Conversion - Fixed Analytics",
  "description": "Converts monetary values between currencies with dual FX APIs, automatic fallback and daily caching.",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "SIMPLE_TABLE",
    "name": "allowedEventDataList",
    "displayName": "Event Currency Configuration",
    "help": "Configure one row per event. Event Name selects the source currency (e.g., purchase, offline_purchase, refund). Unlisted events return undefined.",
    "simpleTableColumns": [
      {
        "defaultValue": "",
        "displayName": "Event Name",
        "name": "eventName",
        "type": "TEXT",
        "valueHint": "e.g., purchase, offline_purchase, refund"
      },
      {
        "defaultValue": "",
        "displayName": "Convert From Currency",
        "name": "fromCurrency",
        "type": "TEXT",
        "valueHint": "e.g., EUR or {{Event Data - currency}}"
      }
    ]
  },
  {
    "type": "TEXT",
    "name": "toCurrency",
    "displayName": "Convert To Currency",
    "simpleValueType": true,
    "valueHint": "e.g., USD or {{Shop Currency}}",
    "help": "The target 3-letter currency code shared by all configured events. A fixed code or GTM variable can be used. The output is the converted monetary amount.",
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ]
  },
  {
    "type": "TEXT",
    "name": "monetaryValue",
    "displayName": "Monetary Value to Convert",
    "simpleValueType": true,
    "valueHint": "e.g., {{Event Data - value}}",
    "help": "Enter a GTM variable returning the monetary amount to convert (for example, event_data.value). This is the amount in the matching event row's Convert From Currency. The template returns the converted amount, not the exchange rate.",
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "decimalSettings",
    "displayName": "Decimal Places",
    "groupStyle": "ZIPPY_CLOSED",
    "subParams": [
      {
        "type": "RADIO",
        "name": "decimalPlaces",
        "displayName": "Decimal Places",
        "simpleValueType": true,
        "defaultValue": "2",
        "radioItems": [
          {
            "value": "2",
            "displayValue": "2 Decimals (Default)",
            "help": "Return a converted amount rounded to two decimal places (default)."
          },
          {
            "value": "0",
            "displayValue": "No Decimals",
            "help": "Return a converted amount rounded to a whole number."
          }
        ],
        "help": "Round the converted monetary amount (not the FX rate). The full-precision exchange rate is used for conversion and caching."
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "loggingSettings",
    "displayName": "Logging Preferences",
    "groupStyle": "ZIPPY_CLOSED",
    "subParams": [
      {
        "type": "RADIO",
        "name": "loggingPreference",
        "displayName": "Logging Preferences",
        "simpleValueType": true,
        "defaultValue": "debug",
        "radioItems": [
          {
            "value": "none",
            "displayValue": "Disable Logging",
            "help": "Do not write diagnostic information to the server container console."
          },
          {
            "value": "debug",
            "displayValue": "Debug Mode",
            "help": "Log only when the server container is in Preview or Debug mode."
          },
          {
            "value": "always",
            "displayValue": "Always Log",
            "help": "Log currency selection, cache use and API outcomes in Preview and published environments."
          }
        ],
        "help": "Choose when to log event selection, cached exchange rates, primary/fallback FX API results and failures. Default: Debug Mode."
      }
    ]
  }
]


___SANDBOXED_JS_FOR_SERVER___

/*
 * Ecommerce Currency Conversion - Fixed Analytics
 * Developer: Javier Garijo (GitHub: javier-garijo-gtm)
 * A monetary amount converter for server-side Google Tag Manager.
 * Output = Monetary Value to Convert x full-precision FROM-to-TO exchange rate.
 * Primary:  https://open.er-api.com/v6/latest/{FROM}
 * Fallback: https://latest.currency-api.pages.dev/v1/currencies/{from}.json
 * Only successfully validated FX rates are cached, until the UTC date changes.
 * No API URLs, API keys, or cache settings need to be configured.
 */
const PRIMARY_API = 'https://open.er-api.com/v6/latest/';
const FALLBACK_API = 'https://latest.currency-api.pages.dev/v1/currencies/';
const FX_TIMEOUT_MS = 5000;
const CACHE_PREFIX = 'fixed_analytics_currency_conversion_v1_';

const JSON = require('JSON');
const Math = require('Math');
const makeNumber = require('makeNumber');
const createRegex = require('createRegex');
const testRegex = require('testRegex');
const getEventData = require('getEventData');
const getTimestampMillis = require('getTimestampMillis');
const sendHttpRequest = require('sendHttpRequest');
const templateDataStorage = require('templateDataStorage');
const logToConsole = require('logToConsole');
const getContainerVersion = require('getContainerVersion');

const currencyPattern = createRegex('^[A-Z]{3}$');
const amountPattern = createRegex('^[+-]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)$');
const LOG_TEMPLATE_NAME = 'Ecommerce Currency Conversion - Fixed Analytics';
const loggingEnabled = isLoggingEnabled();

function isLoggingEnabled() {
  const preference = data.loggingPreference || 'debug';
  if (preference === 'none') return false;
  if (preference === 'always') return true;
  const version = getContainerVersion();
  return !!(version && (version.debugMode || version.previewMode));
}

// Log only non-sensitive metadata: no event payload, API credentials or customer values.
function logEvent(stage, from, to, detail) {
  if (!loggingEnabled) return;
  logToConsole(JSON.stringify({
    template: LOG_TEMPLATE_NAME,
    stage: stage,
    fromCurrency: from || '',
    toCurrency: to || '',
    detail: detail || ''
  }));
}


function normalizeEvent(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function normalizeCurrency(value) {
  if (typeof value !== 'string') return '';
  const code = value.trim().toUpperCase();
  if (!currencyPattern || !testRegex(currencyPattern, code)) return '';
  return code;
}

function rateIsValid(value) {
  return typeof value === 'number' && value === value && value > 0 && value < 1000000000000;
}

// Validate a numeric monetary input; do not treat missing data as zero.
// A valid amount may be negative, for example when handling a refund.
function validAmount(value) {
  return typeof value === 'number' && value === value &&
    value > -1000000000000000 && value < 1000000000000000;
}

function readMonetaryValue(value) {
  if (validAmount(value)) return value;
  if (typeof value !== 'string') return undefined;
  const cleaned = value.trim();
  if (!cleaned || !testRegex(amountPattern, cleaned)) return undefined;
  const parsed = makeNumber(cleaned);
  return validAmount(parsed) ? parsed : undefined;
}

// Round only the resulting monetary value, never the FX multiplier.
function convertAmount(monetaryValue, rate) {
  if (!validAmount(monetaryValue) || !rateIsValid(rate)) return undefined;
  const converted = monetaryValue * rate;
  if (!validAmount(converted)) return undefined;
  const factor = data.decimalPlaces === '0' ? 1 : 100;
  return Math.round(converted * factor) / factor;
}

function getEventFromCurrency() {
  const name = normalizeEvent(getEventData('event_name'));
  if (!name) return '';
  const rows = data.allowedEventDataList || [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (row && normalizeEvent(row.eventName) === name) {
      return normalizeCurrency(row.fromCurrency);
    }
  }
  return '';
}

function primaryRate(response, from, to) {
  if (!response || response.statusCode !== 200 || typeof response.body !== 'string') return undefined;
  const payload = JSON.parse(response.body);
  if (!payload || payload.result !== 'success' || payload.base_code !== from || !payload.rates) return undefined;
  const rate = payload.rates[to];
  return rateIsValid(rate) ? rate : undefined;
}

function fallbackRate(response, from, to) {
  if (!response || response.statusCode !== 200 || typeof response.body !== 'string') return undefined;
  const payload = JSON.parse(response.body);
  const rates = payload && payload[from.toLowerCase()];
  const rate = rates && rates[to.toLowerCase()];
  return rateIsValid(rate) ? rate : undefined;
}

function getFallbackRate(from, to) {
  const url = FALLBACK_API + from.toLowerCase() + '.json';
  return sendHttpRequest(url, {method:'GET', timeout:FX_TIMEOUT_MS}).then(
    response => {
      const rate = fallbackRate(response, from, to);
      logEvent(rateIsValid(rate) ? 'fallback_success' : 'fallback_invalid_response', from, to,
        'HTTP ' + (response && response.statusCode !== undefined ? response.statusCode : 'unknown'));
      return rate;
    },
    error => {
      logEvent('fallback_request_failed', from, to, 'HTTP request rejected');
      return undefined;
    }
  ).then(
    rate => rate,
    error => {
      logEvent('fallback_parse_failed', from, to, 'Invalid response body');
      return undefined;
    }
  );
}

function getLiveRate(from, to) {
  return sendHttpRequest(PRIMARY_API + from, {method:'GET', timeout:FX_TIMEOUT_MS}).then(
    response => {
      const rate = primaryRate(response, from, to);
      logEvent(rateIsValid(rate) ? 'primary_success' : 'primary_invalid_response', from, to,
        'HTTP ' + (response && response.statusCode !== undefined ? response.statusCode : 'unknown'));
      return rate;
    },
    error => {
      logEvent('primary_request_failed', from, to, 'HTTP request rejected');
      return undefined;
    }
  ).then(
    rate => rateIsValid(rate) ? rate : getFallbackRate(from, to),
    error => {
      logEvent('primary_parse_failed', from, to, 'Invalid response body');
      return getFallbackRate(from, to);
    }
  );
}

function convertMoney(from, to, monetaryValue) {
  if (from === to) {
    logEvent('same_currency', from, to, 'No FX request required');
    return convertAmount(monetaryValue, 1);
  }
  const utcDay = Math.floor(getTimestampMillis() / 86400000);
  const cacheKey = CACHE_PREFIX + from + '_' + to;
  const entry = templateDataStorage.getItemCopy(cacheKey);
  if (entry && entry.utcDay === utcDay && rateIsValid(entry.rate)) {
    logEvent('cache_hit', from, to, 'Rate reused from current UTC day');
    return convertAmount(monetaryValue, entry.rate);
  }
  logEvent('cache_miss', from, to, 'Fetching FX rate');
  return getLiveRate(from, to).then(rate => {
    if (!rateIsValid(rate)) {
      logEvent('rate_unavailable', from, to, 'Neither provider returned a valid rate');
      return undefined;
    }
    templateDataStorage.setItemCopy(cacheKey, {utcDay:utcDay,rate:rate});
    logEvent('rate_cached', from, to, 'Full-precision rate validated and cached for current UTC day');
    return convertAmount(monetaryValue, rate);
  });
}

const from = getEventFromCurrency();
const to = normalizeCurrency(data.toCurrency);
const monetaryValue = readMonetaryValue(data.monetaryValue);
if (!from || !to) {
  logEvent('configuration_invalid', from, to, 'Event not configured or currency invalid');
  return undefined;
}
if (monetaryValue === undefined) {
  logEvent('amount_invalid', from, to, 'Monetary Value to Convert must be a number');
  return undefined;
}
logEvent('event_selected', from, to, normalizeEvent(getEventData('event_name')));
return convertMoney(from, to, monetaryValue);


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "access_template_storage",
        "versionId": "1"
      },
      "param": []
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "send_http",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedUrls",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_event_data",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keyPatterns",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "event_name"
              }
            ]
          }
        },
        {
          "key": "eventDataAccess",
          "value": {
            "type": 1,
            "string": "specific"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "all"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_container_data",
        "versionId": "1"
      },
      "param": []
    },
    "isRequired": true
  }
]


___TESTS___

scenarios: []


___NOTES___

Ecommerce Currency Conversion - Fixed Analytics.
Developer: Javier Garijo (GitHub: javier-garijo-gtm).
For each event, configure Event Name and Convert From Currency, then set a shared Convert To Currency.
Monetary Value to Convert should be a GTM variable containing the numeric event amount (for example, {{Event Data - value}}).
The output is the converted monetary amount, not the FX multiplier.
Calculation: output = monetary value x full-precision FX rate (From -> To), rounded to two decimals by default.
Decimal Places options: 2 Decimals (default) and No Decimals.
Example: 95 EUR at an illustrative EUR->USD rate of 1.12 returns 106.40 USD.
Another example: 95 USD at an illustrative USD->EUR rate of 0.89 returns 84.55 EUR.
Matching From/To codes return the original amount rounded according to Decimal Places; no network request is needed.
A missing, invalid or non-numeric amount returns undefined rather than zero.
Events not configured in the table also return undefined.
Primary FX API: open.er-api.com/v6/latest/{FROM}.
Fallback FX API: latest.currency-api.pages.dev/v1/currencies/{from}.json.
The fallback is used automatically when the primary API fails or does not provide a valid rate.
Validated full-precision rates are cached per pair for the current UTC day, even when outputs are rounded.
Rates reflect the providers' latest published quotations; they are not real-time tick-by-tick rates.
If both providers fail, return undefined; do not invent the rate.
Logging Preferences: Disable Logging, Debug Mode (default; Preview/Debug only), Always Log.
No embedded test scenarios. Verify the imported template in GTM Preview.
