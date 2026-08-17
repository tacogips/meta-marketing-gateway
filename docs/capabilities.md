# Capability catalog

Reviewed 2026-08-15. `Catalog/meta-capabilities.json` is the source inventory.

Reader operations are GET-only, Writer operations are POST-only, and Deleter operations
are DELETE-only. Generic relative paths preserve Graph API coverage without sharing an
HTTP-method capability across clients.

| Operation | Surface | Availability | Reviewed | Official source |
| --- | --- | --- | --- | --- |
| `meta.ads.ad-accounts.get` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-account |
| `meta.ads.ad-accounts.list` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-account |
| `meta.ads.ad-creatives.get` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-creative |
| `meta.ads.ad-creatives.list` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-creative |
| `meta.ads.ad-sets.get` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign |
| `meta.ads.ad-sets.list` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign |
| `meta.ads.ad.create` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/adgroup |
| `meta.ads.ad.delete` | deleter | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/adgroup |
| `meta.ads.ad.update` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/adgroup |
| `meta.ads.adcreative.create` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-creative |
| `meta.ads.adcreative.delete` | deleter | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-creative |
| `meta.ads.adcreative.update` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-creative |
| `meta.ads.ads.get` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/adgroup |
| `meta.ads.ads.list` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/adgroup |
| `meta.ads.adset.create` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign |
| `meta.ads.adset.delete` | deleter | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign |
| `meta.ads.adset.update` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign |
| `meta.ads.campaign.create` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group |
| `meta.ads.campaign.delete` | deleter | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group |
| `meta.ads.campaign.update` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group |
| `meta.ads.campaigns.get` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group |
| `meta.ads.campaigns.list` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group |
| `meta.ads.insights.read` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/marketing-api/insights |
| `meta.generic.delete` | deleter | enabled | 2026-08-15 | https://developers.facebook.com/docs/graph-api/using-graph-api |
| `meta.generic.write` | writer | enabled | 2026-08-15 | https://developers.facebook.com/docs/graph-api/using-graph-api |
| `meta.graph.get` | reader | enabled | 2026-08-15 | https://developers.facebook.com/docs/graph-api/using-graph-api |
