# FoneBook API Contract

> **Generated:** 2026-10-03  
> **Branch:** security-hardening  
> **Source:** Grepped from `lib/**/*.dart` — all `api.get`, `api.post`, `api.delete` calls.

This document is the **frozen contract** between the Flutter app and the backend.  
**Never rename, remove, or change the response shape of any entry in this table** without a coordinated deploy.

---

## GET Endpoints

| Path | Query Params | Response Shape Used | Called From |
|------|-------------|---------------------|-------------|
| `check-contact` | `type`, `query`, `location`, `limit` | `List<Map>` or `[{status:'No data'}]` | home_screen, worldwide_screen, app_profile_screen |
| `check_search_type1` | `email` | `List<Map>` with contact fields | promote_screen, add_profile_screen, profile_list_screen |
| `check-priority` | `id` | `Map` or `List<Map>` with `priority_balance`, `priority` | promote_screen |
| `check-call-count1` | `id`, `type` | `List<Map>` | reports_screen |
| `api/user_calls` | `user_id`, `owner_email` | `{data: List}` or `List` | recent_screen (via ApiClient.getCallHistoryFromBackend) |

## POST Endpoints

| Path | Body Fields | Response Shape Used | Called From |
|------|------------|---------------------|-------------|
| `send-verification-code` | `email`, `otp`, `fone_identification` | `{status, message}` | login_screen |
| `get_my_contacts` | `email`, `owner_email` | `List<Map>` or `{data, result, contacts}` | login_screen, home_screen, my_contacts_screen, app_profile_screen, recent_screen, contact_export_service |
| `savecontacts` | `id?`, `name`, `phone`, `phone1`, `email`, `service`, `location`, `location1`, `state`, `city`, `imagebolb?`, `filename?`, `about`, `keyword`, `keywords`, `landlineno`, `wpno`, `skypeno`, `category`, `output`, `phonenos`, `services`, `publish`, `owner_email`, `verification?`, `payment_status?`, `transaction_id?`, `amount?` | `{status, id, message}` or string containing 'success' | add_profile_screen, profile_list_screen |
| `savecontacts1` | Same as savecontacts minus payment fields | `{status, id, message}` | add_profile_screen |
| `save_show` | `id?`, `phone`, `show` | any (result ignored) | add_profile_screen, visibility_screen |
| `save_access` | `id?`, `phone`, `who_contact` | any (result ignored) | add_profile_screen, visibility_screen |
| `save_publish` | `id`, `phone`, `publish` | `{status}` or string | profile_list_screen, add_profile_screen, visibility_screen |
| `delete_contact` | `id` or `phone` | string (`'phone no deleted'`) | profile_list_screen, add_profile_screen |
| `savepriority` | `id`, `priority_amount`, `priority` | any (result ignored) | promote_screen, home_screen |
| `save_search_type1` | `id`, `phone`, `type` | any (result ignored) | promote_screen |
| `savepromote` | `id`, `international`, `country`, `state`, `city` | any (result ignored) | promote_screen |
| `save_my_contact` | `email`, `owner_email`, `name`, `phone`, `...` | any | app_profile_screen, my_contacts_screen |
| `update_my_contact` | contact fields | any | home_screen, app_profile_screen, my_contacts_screen |
| `delete_my_contact` | `email`, `owner_email`, `id` or `phone` | any | my_contacts_screen |
| `delete_account` | `email`, `phone` | any | app_profile_screen |
| `bulk_assign_category` | `email`, `owner_email`, `category`, `ids` | any | my_contacts_screen |
| `savetags` | `id`, `phone`, `tags` | any | keyword_screen |
| `savesearch` | search tracking fields | any (fire-and-forget) | home_screen |
| `api/user_calls` | `name`, `phone_number`, `service`, `user_id`, `owner_email`, `call_time` | any | session_store (via ApiClient.addCallToBackend) |
| `receiveData` | `data`, `email` | `{status}` | my_contacts_screen (import) |

## DELETE Endpoints

| Path | Body / Query | Response | Called From |
|------|-------------|----------|-------------|
| `api/user_calls` | `user_id`, `owner_email`, `clear_all?`, `call_ids?` | `{success, message, deleted_count}` | recent_screen (via ApiClient.deleteCallsFromBackend) |

## New V1 Endpoints (Phase 2 — additive)

| Path | Method | Body | Response | Notes |
|------|--------|------|----------|-------|
| `v1/auth/send-otp` | POST | `email`, `fone_identification` | `{status, message}` | Server-side OTP (CRIT-03) |
| `v1/auth/verify-otp` | POST | `email`, `otp` | `{status, access_token, refresh_token}` | Server-side verify |
| `v1/auth/refresh` | POST | `refresh_token` | `{status, access_token}` | Token refresh |
| `v1/auth/logout` | POST | `refresh_token?` | `{status}` | Token revocation |
| `v1/payments/verify` | POST | `product_id`, `purchase_token`, `platform`, `profile_id?` | `{status, message}` | IAP server verification (CRIT-04) |
| `v1/me/premium` | GET | _(auth header)_ | `{premium, subscription_status, ...}` | Authoritative premium check |
| `v1/app-config` | GET | — | `{min_supported_version, latest_version, play_store_url}` | Force-update support |

---

## Critical Response Shapes That Must Not Change

The Flutter app parses these specific patterns:

1. **`savecontacts` / `savecontacts1`** — checks `res.toString().toLowerCase().contains('success')` or `res['status'] == 'success'` and reads `res['id']`.
2. **`send-verification-code`** — checks `res['status'] == 'success'`.
3. **`get_my_contacts`** — handles both `List` and `{data: List}` and `{result: List}` and `{contacts: List}`.
4. **`check-contact`** — always returns `List`. Error shape is `[{status: 'No data'}]` or plain string (both handled).
5. **`delete_contact`** — return value not parsed; any 200 is treated as success.
6. **`api/user_calls` DELETE** — parses `{success: bool, deleted_count: int}`.
