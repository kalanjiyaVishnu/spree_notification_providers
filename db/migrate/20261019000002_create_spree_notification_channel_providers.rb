# frozen_string_literal: true

class CreateSpreeNotificationChannelProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_notification_channel_providers do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores }, index: false
      t.string :channel, null: false
      t.string :provider_key, null: false
      t.boolean :enabled, null: false, default: false
      t.integer :position, null: false
      t.jsonb :settings, null: false, default: {}
      t.text :secret_settings
      t.jsonb :templates, null: false, default: {}

      t.timestamps
    end

    add_index :spree_notification_channel_providers, %i[store_id channel provider_key], unique: true,
                                                                                        name: 'idx_spree_notif_channel_providers_on_store_channel_provider'
    add_index :spree_notification_channel_providers, %i[store_id channel position],
              name: 'idx_spree_notif_channel_providers_on_store_channel_position'
  end
end
