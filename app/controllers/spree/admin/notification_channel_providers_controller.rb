# frozen_string_literal: true

module Spree
  module Admin
    # Adds, configures, reorders, tests and removes one provider on one channel.
    class NotificationChannelProvidersController < Spree::Admin::BaseController
      helper 'spree/admin/notification_masking'

      before_action :authorize_providers
      before_action :load_entry, except: :create

      rate_limit to: 5, within: 1.minute, only: :test, by: -> { try_spree_current_user&.id || request.remote_ip },
                 with: -> { redirect_back_or_to(edit_path, alert: 'Too many test messages. Try again in a minute.') }

      def create
        channel = params[:channel].to_s
        definition = SpreeNotificationProviders.provider(params[:provider_key])
        unless Spree::NotificationChannelProvider::CHANNELS.include?(channel) && definition&.supports?(channel)
          flash[:error] = 'That provider is not available for this channel.'
          return redirect_to spree.admin_notification_providers_path(channel: channel.presence), status: :see_other
        end

        entry = Spree::NotificationChannelProvider.find_or_initialize_by(store_id: current_store.id, channel: channel,
                                                                         provider_key: definition.key.to_s)
        entry.enabled = false if entry.new_record?
        entry.save!(validate: false)
        entry.provider_config
        flash[:success] = t('spree_notification_providers.admin.providers.added', provider: definition.label,
                                                                                 channel: channel_label(channel))
        redirect_to spree.edit_admin_notification_channel_provider_path(entry), status: :see_other
      end

      def edit; end

      def update
        config = @entry.provider_config
        attrs = entry_params

        config.assign_inputs(@entry.shared_inputs, values: attrs[:shared_settings], secrets: attrs[:shared_secret_settings],
                                                   clear: attrs[:clear_shared_secrets])
        @entry.assign_inputs(@entry.channel_inputs, values: attrs[:settings], secrets: attrs[:secret_settings],
                                                    clear: attrs[:clear_secrets])
        @entry.templates = cleaned_templates(attrs[:templates]) if attrs.key?(:templates)
        @entry.enabled = ActiveModel::Type::Boolean.new.cast(attrs[:enabled]) if attrs.key?(:enabled)

        config_valid = config.valid?
        if config_valid && @entry.valid?
          ActiveRecord::Base.transaction do
            config.save!
            @entry.save!
          end
          SpreeNotificationProviders::Adapters::Gupshup.clear_template_cache(current_store) if @entry.provider_key == 'gupshup'
          flash[:success] = t('spree_notification_providers.admin.providers.updated', provider: provider_label)
          redirect_to(params[:return_to] == 'index' ? index_path : edit_path, status: :see_other)
        else
          @config_errors = config.input_errors
          flash.now[:error] = (config.errors.full_messages + @entry.errors.full_messages).uniq.join(', ')
          render :edit, status: :unprocessable_content
        end
      end

      def reposition
        position = (params.dig(:notification_channel_provider, :position) || params[:position]).to_i
        count = Spree::NotificationChannelProvider.where(store_id: current_store.id, channel: @entry.channel).count
        @entry.insert_at(position.clamp(1, count)) if position.positive?
        head :no_content
      end

      def destroy
        channel = @entry.channel
        @entry.destroy!
        unless Spree::NotificationChannelProvider.exists?(store_id: current_store.id, provider_key: @entry.provider_key)
          Spree::NotificationProviderConfig.where(store_id: current_store.id, provider_key: @entry.provider_key).destroy_all
        end
        flash[:success] = t('spree_notification_providers.admin.providers.removed', provider: provider_label,
                                                                                   channel: channel_label(channel))
        redirect_to spree.admin_notification_providers_path(channel: channel), status: :see_other
      end

      # Sends one message through this provider only, ignoring priority.
      def test
        to = params[:to].to_s.strip
        unless valid_test_recipient?(to)
          kind = @entry.channel == 'email' ? 'email address' : 'phone number'
          flash[:error] = t('spree_notification_providers.admin.configure.test_invalid_to', kind: kind)
          return redirect_to edit_path, status: :see_other
        end

        message = SpreeNotificationProviders::Message.new(channel: @entry.channel, type: :provider_test, to: to,
                                                          code: SpreeNotificationProviders::Adapters::Base::TEST_CODE)
        result = SpreeNotificationProviders::Router.new(current_store).deliver_via(@entry, message)
        if result.success?
          flash[:success] = t('spree_notification_providers.admin.configure.test_delivered', provider: provider_label)
        else
          flash[:error] = t('spree_notification_providers.admin.configure.test_failed',
                            provider: provider_label, reason: result.attempts.first[:reason] || result.outcome)
        end
        redirect_to edit_path, status: :see_other
      end

      private

      def model_class
        Spree::NotificationChannelProvider
      end

      def authorize_providers
        authorize! :manage, Spree::NotificationChannelProvider
      end

      def load_entry
        @entry = Spree::NotificationChannelProvider.where(store_id: current_store.id).find_by_param!(params[:id])
      end

      def entry_params
        params.fetch(:entry, {}).permit(:enabled, settings: {}, secret_settings: {}, shared_settings: {},
                                                  shared_secret_settings: {}, templates: {}, clear_secrets: [],
                                                  clear_shared_secrets: [])
      end

      # Only registered message types for this channel; blanks dropped.
      def cleaned_templates(raw)
        allowed = SpreeNotificationProviders.message_types_for(@entry.channel).map { |type| type.key.to_s }
        raw.to_h.slice(*allowed).transform_values { |value| value.to_s.strip }.compact_blank
      end

      def valid_test_recipient?(to)
        if @entry.channel == 'email'
          to.match?(SpreeNotificationProviders::InputDefinition::EMAIL_FORMAT)
        else
          to.delete(' -').match?(SpreeNotificationProviders::InputDefinition::PHONE_FORMAT)
        end
      end

      def provider_label
        @entry.definition&.label || @entry.provider_key.titleize
      end

      def channel_label(channel)
        t("spree_notification_providers.channels.#{channel}")
      end

      def edit_path
        spree.edit_admin_notification_channel_provider_path(@entry)
      end

      def index_path
        spree.admin_notification_providers_path(channel: @entry.channel)
      end
    end
  end
end
