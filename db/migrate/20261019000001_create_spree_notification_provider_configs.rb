# frozen_string_literal: true

class CreateSpreeNotificationProviderConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_notification_provider_configs do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores }, index: false
      t.string :provider_key, null: false
      t.jsonb :settings, null: false, default: {}
      t.text :secret_settings
      t.string :import_source
      t.datetime :imported_at

      t.timestamps
    end

    add_index :spree_notification_provider_configs, %i[store_id provider_key], unique: true,
                                                                               name: 'idx_spree_notif_provider_configs_on_store_provider'
  end
end
