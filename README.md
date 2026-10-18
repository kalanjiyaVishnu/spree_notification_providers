# spree_notification_providers

Per-channel notification providers with priority and failover for
[Spree Commerce](https://spreecommerce.org) 5.5+.

Each store picks the providers it uses for **Email**, **SMS** and **WhatsApp**,
enters only the inputs each provider needs, and puts them in order. Messages go
to the first ready provider; if it definitely did not take the message, the next
one is tried. Every attempt is recorded in an admin **Delivery log**.

Bundled providers:

| Provider | Email | SMS | WhatsApp |
|----------|-------|-----|----------|
| MSG91    | templates, bulk | OTP, Flow templates, bulk | OTP |
| SMTP     | rendered HTML (any mailer) | — | — |
| Gupshup  | — | — | OTP, templates |
| Log      | all (writes to the Rails log; non-production only) | all | all |

You can add your own provider without changing this gem (see
[Adding a provider](#adding-a-provider)).

---

## Installation

```ruby
# Gemfile
gem 'spree_notification_providers', '~> 0.1'
```

```bash
bundle install
bin/rails g spree_notification_providers:install
```

The generator copies three migrations (`spree_notification_provider_configs`,
`spree_notification_channel_providers`, `spree_notification_deliveries`), runs
them, and writes `config/initializers/spree_notification_providers.rb`.

Then:

1. **Encryption keys.** Provider secrets are stored with Active Record
   Encryption. Configure `active_record_encryption` credentials or set
   `config.active_record.encryption.primary_key`, `deterministic_key` and
   `key_derivation_salt` (`bin/rails db:encryption:init` prints a set).
2. **Permissions.** Super users can open the screens already. For other admin
   roles add the permission set:

   ```ruby
   Spree.permissions.assign(:admin, [Spree::PermissionSets::NotificationProviderManagement])
   ```

3. **Mailers (optional but recommended).** Route Action Mailer through the
   store's Email providers:

   ```ruby
   # config/environments/production.rb
   config.action_mailer.delivery_method = :spree_notification_providers
   ```

4. **Retention.** Schedule `Spree::NotificationDeliveries::PurgeJob` daily, e.g.
   with sidekiq-cron:

   ```yaml
   notification_deliveries_purge:
     cron: "0 4 * * *"
     class: "Spree::NotificationDeliveries::PurgeJob"
   ```

5. Open **Admin → Settings → Notification providers**.

---

## Configuring providers

**Admin → Settings → Notification providers** has a tab per channel. Each tab
lists the store's providers in priority order (drag to reorder) with a status:

- **Ready** — enabled and every required input is set.
- **Not ready** — names the missing inputs.
- **Disabled** — skipped; its inputs are kept.
- **Unavailable** — the provider is no longer registered; skipped.

**Add** a provider from *Available providers*, then **Configure** it. The form
shows only that provider's inputs:

- **Shared settings** are entered once per store and used by every channel the
  provider serves (e.g. the MSG91 auth key for Email and SMS).
- **Channel settings** apply to one channel (e.g. the MSG91 email sending domain).
- **Templates** — one field per registered message type (see below). A
  template-based provider is skipped for a message type with no template.

Secret inputs are write-only: they show as "Set ••••1234" (last four characters
only for values of 12+ characters), a blank submit keeps the stored value, and
**Clear** removes it. They are stored encrypted and never logged.

**Send test** sends one message through that provider only, ignoring priority,
and records it in the Delivery log as `provider_test`.

### MSG91

| Scope | Input | Notes |
|-------|-------|-------|
| shared | Auth key * (secret) | MSG91 dashboard → Authkey |
| email | Sending domain * | Verified domain; the sender's own domain is used when the message has a sender |
| email | Default from address | Used when the message has no sender |
| sms | Sender ID | DLT-registered header |
| sms, whatsapp | Default country code | Added to 10-digit numbers (default `91`) |

Templates: email template id, SMS OTP template / Flow id, WhatsApp OTP template.

### SMTP

| Input | Notes |
|-------|-------|
| Host *, Port * (587), Username *, Password * (secret) | |
| From address | Used when a mail has no sender (else the username, if it is an address) |
| Authentication | `plain` (default), `login`, `cram_md5` |
| Use STARTTLS | default yes |

SMTP sends rendered HTML only (Action Mailer mails and `kind: :html` messages).

### Gupshup

| Scope | Input | Notes |
|-------|-------|-------|
| shared | API key * (secret) | |
| shared | Webhook secret (secret) | Random string for the callback URL |
| whatsapp | Source number * | Business number with country code, digits only |
| whatsapp | App name * | |
| whatsapp | App ID | Needed when a template is entered by name instead of UUID |

Point the Gupshup app's callback at
`https://<host>/webhooks/gupshup?secret=<webhook secret>`. A `failed` event
marks the delivery failed and publishes `notification.delivery_failed`.

---

## How priority and failover work

For one-to-one messages the router walks the channel's enabled providers in
order:

1. A provider that is not ready, has no template for the message type, or can't
   send this kind of message is recorded as **skipped**.
2. **Delivered** — stop.
3. **Failed** — a definite failure (connection refused, connect timeout, DNS/TLS
   error, HTTP 4xx, a 5xx that explains itself, SMTP auth/rejection): try the
   next provider.
4. **Unknown** — the message may have reached the provider (read timeout,
   connection reset after sending, a 5xx with no body): **stop**, so the
   customer never gets a duplicate.

Bulk sends (`deliver_bulk`) use the first ready provider that supports bulk and
**never fail over**; each rejected recipient is recorded as failed.

A provider that accepts a message and later reports it failed (e.g. a Gupshup
callback) does not trigger failover; subscribe to `notification.delivery_failed`
to react (spree_otp_auth uses it for its email backup).

---

## Delivery log

**Admin → Settings → Delivery log** lists every attempt for the store, newest
first, with attempts of one message grouped. Filter by channel, provider,
outcome, message type, date and bulk. Recipients are masked
(`ka•••@gmail.com`, `+91•••••3210`) and not searchable. Rows older than
`delivery_retention_days` (default 90) are removed by the purge job.

---

## Sending from code

```ruby
message = SpreeNotificationProviders::Message.new(
  channel: :sms, type: :otp_code, kind: :otp, to: '+919876543210', code: '482913', expiry_minutes: 10
)
result = SpreeNotificationProviders.deliver(store: store, message: message)
result.success?     # true when a provider delivered it
result.retryable?   # true only when no provider can have taken it
result.attempts     # [{ provider_key:, outcome:, reason: }]
```

```ruby
bulk = SpreeNotificationProviders::BulkMessage.new(
  channel: :email, type: :customer_blast, recipients: emails, variables: { 'OFFER' => '10%' },
  templates: { msg91: 'blast-template' }
)
SpreeNotificationProviders.deliver_bulk(store: store, message: bulk).failed_recipients
```

`SpreeNotificationProviders.ready_for?(store, :whatsapp, :otp_code)` and
`channel_status(store, :sms)` answer readiness questions.

### Message types

Register the kinds of message your app sends; each gets a template field on
template-based providers:

```ruby
SpreeNotificationProviders.register_message_type :order_confirmation,
                                                 label: 'Order confirmation', channels: %i[email sms]
SpreeNotificationProviders.register_message_type :newsletter,
                                                 label: 'Newsletter', channels: %i[email], bulk: true
```

### Action Mailer

With `delivery_method = :spree_notification_providers`, each mail is sent
through the store's Email providers. Optional headers (removed before sending):

| Header | Meaning |
|--------|---------|
| `X-Spree-Store-Id` | Store id (default `Spree::Current.store`, then the default store) |
| `X-Spree-Message-Type` | Message type (default `transactional_email`) |
| `X-Spree-Provider-Template-<Key>` | Template for one provider, e.g. `X-Spree-Provider-Template-Msg91` |

The method raises `SpreeNotificationProviders::DeliveryFailed` only when no
provider can have taken the mail, so `deliver_later` retries are safe.

### Events

| Event | When |
|-------|------|
| `notification.delivered` | a provider delivered a message |
| `notification.failed` | every provider failed or was skipped |
| `notification.delivery_failed` | a provider reported an accepted message as failed |

---

## Adding a provider

```ruby
# config/initializers/notification_providers.rb
SpreeNotificationProviders.register_provider :twilio do
  label   'Twilio'
  adapter 'MyApp::TwilioAdapter'

  shared_input :account_sid, label: 'Account SID', required: true, env: 'TWILIO_ACCOUNT_SID'
  shared_input :auth_token,  label: 'Auth token', required: true, secret: true, env: 'TWILIO_AUTH_TOKEN'

  channel :sms, kinds: %i[otp template] do
    input :from_number, label: 'From number', type: :phone, required: true
  end
end
```

```ruby
class MyApp::TwilioAdapter < SpreeNotificationProviders::Adapters::Base
  def deliver(message, context)
    response = SpreeNotificationProviders::Http.request(
      :post, "https://api.twilio.com/2010-04-01/Accounts/#{context[:account_sid]}/Messages.json",
      headers: { 'Authorization' => "Basic #{Base64.strict_encode64("#{context[:account_sid]}:#{context[:auth_token]}")}" },
      form: { 'To' => message.to, 'From' => context[:from_number], 'Body' => "Your code is #{message.code}" }
    )
    body = SpreeNotificationProviders::Http.parse_json(response.body)
    SpreeNotificationProviders::Adapters::HttpOutcome.from_response(
      response, body, accepted: body['sid'].present?, message_id: body['sid'], provider_message: body['message']
    )
  rescue StandardError => e
    SpreeNotificationProviders::Adapters::HttpOutcome.from_error(e)
  end
end
```

- Input types: `:string`, `:integer`, `:email`, `:phone`, `:url`, `:select`
  (with `options:`), `:boolean`. Options: `required`, `secret`, `format`
  (Regexp), `default`, `label`, `help`, `env`.
- Channel kinds: `:otp`, `:template`, `:html`, `:bulk`. `template_required: true`
  skips the provider for message types without a template; `missing_check`
  adds readiness rules that depend on several values.
- `context[:name]` gives merged shared + channel values (secrets decrypted,
  defaults applied); `context.template` is the template for the message type.
- Return `Result.delivered(id)`, `Result.failed(reason)` or
  `Result.unknown(reason)`. Never put credentials or full response bodies in a
  reason.
- `env:` is read only by the importer below; adapters never read `ENV`.

---

## Upgrading from environment variables

If your app kept provider settings in ENV (`MSG91_AUTH_KEY`, `SMTP_HOST`,
`GUPSHUP_API_KEY`, …), copy them into a store's configuration:

```bash
bin/rails g spree_notification_providers:import_env --store=<code> --dry-run
bin/rails g spree_notification_providers:import_env --store=<code>
```

Only blank inputs are filled, so it is safe to rerun.

---

## Configuration

```ruby
SpreeNotificationProviders.configure do |config|
  config.delivery_retention_days = 90                       # >= 1
  config.enable_log_provider     = !Rails.env.production?   # register the Log provider
  config.http_timeout_seconds    = 5                        # bundled HTTP adapters
  config.bulk_batch_size         = 100
end
```

---

## Development

```bash
bundle exec rake test_app   # generates spec/dummy (spree_dev_tools)
bundle exec rspec
```

Specs stub `SpreeNotificationProviders::Http.request`; a real provider call
from a spec raises.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
