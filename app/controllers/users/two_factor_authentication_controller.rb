module Users
  class TwoFactorAuthenticationController < ApplicationController
    include TwoFactorAuthenticatable

    before_action :check_remember_device_preference

    # rubocop:disable Metrics/MethodLength
    def show
      if current_user.piv_cac_enabled?
        redirect_to login_two_factor_piv_cac_url
      elsif current_user.totp_enabled?
        redirect_to login_two_factor_authenticator_url
      elsif current_user.phone_enabled?
        validate_otp_delivery_preference_and_send_code
      else
        redirect_to two_factor_options_url
      end
    rescue Twilio::REST::RestError, PhoneVerification::VerifyError => exception
      invalid_phone_number(exception, action: 'show')
    end
    # rubocop:enable Metrics/MethodLength

    def send_code
      result = otp_delivery_selection_form.submit(delivery_params)
      analytics.track_event(Analytics::OTP_DELIVERY_SELECTION, result.to_h)

      if result.success?
        handle_valid_otp_delivery_preference(user_selected_otp_delivery_preference)
        update_otp_delivery_preference_if_needed
      else
        handle_invalid_otp_delivery_preference(result)
      end
    rescue Twilio::REST::RestError, PhoneVerification::VerifyError => exception
      invalid_phone_number(exception, action: 'send_code')
    end

    private

    def validate_otp_delivery_preference_and_send_code
      delivery_preference = current_user.otp_delivery_preference
      result = otp_delivery_selection_form.submit(otp_delivery_preference: delivery_preference)
      analytics.track_event(Analytics::OTP_DELIVERY_SELECTION, result.to_h)

      if result.success?
        handle_valid_otp_delivery_preference(delivery_preference)
      else
        handle_valid_otp_delivery_preference('sms')
        flash[:error] = result.errors[:phone].first
      end
    end

    def update_otp_delivery_preference_if_needed
      OtpDeliveryPreferenceUpdater.new(
        user: current_user,
        preference: delivery_params[:otp_delivery_preference],
        context: otp_delivery_selection_form.context
      ).call
    end

    def handle_invalid_otp_delivery_preference(result)
      flash[:error] = result.errors[:phone].first
      preference = current_user.otp_delivery_preference
      redirect_to login_two_factor_url(otp_delivery_preference: preference)
    end

    def invalid_phone_number(exception, action:)
      capture_analytics_for_exception(exception)

      if action == 'show'
        redirect_to_otp_verification_with_error
      else
        flash[:error] = error_message(exception.code)
        redirect_back(fallback_location: account_url)
      end
    end

    def redirect_to_otp_verification_with_error
      flash[:error] = t('errors.messages.phone_unsupported')
      redirect_to login_two_factor_url(
        otp_delivery_preference: current_user.otp_delivery_preference, reauthn: reauthn?
      )
    end

    # rubocop:disable Metrics/MethodLength
    def capture_analytics_for_exception(exception)
      attributes = {
        error: exception.message,
        code: exception.code,
        context: context,
        country: parsed_phone.country,
      }
      if exception.is_a?(PhoneVerification::VerifyError)
        attributes[:status] = exception.status
        attributes[:response] = exception.response
      end
      analytics.track_event(Analytics::TWILIO_PHONE_VALIDATION_FAILED, attributes)
    end
    # rubocop:enable Metrics/MethodLength

    def parsed_phone
      @parsed_phone ||= Phonelib.parse(phone_to_deliver_to)
    end

    def error_message(code)
      twilio_errors.fetch(code, t('errors.messages.otp_failed'))
    end

    def twilio_errors
      TwilioErrors::REST_ERRORS.merge(TwilioErrors::VERIFY_ERRORS)
    end

    def otp_delivery_selection_form
      @otp_delivery_selection_form ||= OtpDeliverySelectionForm.new(
        current_user, phone_to_deliver_to, context
      )
    end

    def reauthn_param
      otp_form = params.permit(otp_delivery_selection_form: [:reauthn])
      super || otp_form.dig(:otp_delivery_selection_form, :reauthn)
    end

    def handle_valid_otp_delivery_preference(method)
      otp_rate_limiter.reset_count_and_otp_last_sent_at if decorated_user.no_longer_locked_out?

      return handle_too_many_otp_sends if exceeded_otp_send_limit?
      otp_rate_limiter.increment
      return handle_too_many_otp_sends if exceeded_otp_send_limit?

      send_user_otp(method)
      redirect_to login_two_factor_url(otp_delivery_preference: method, reauthn: reauthn?)
    end

    def exceeded_otp_send_limit?
      return otp_rate_limiter.lock_out_user if otp_rate_limiter.exceeded_otp_send_limit?
    end

    def send_user_otp(method)
      current_user.create_direct_otp

      job = "#{method.capitalize}OtpSenderJob".constantize
      job_priority = confirmation_context? ? :perform_now : :perform_later
      job.send(job_priority,
               method == 'sms' ? job_params.merge(message: sms_message) : job_params)
    end

    def job_params
      {
        code: current_user.direct_otp,
        phone: phone_to_deliver_to,
        otp_created_at: current_user.direct_otp_sent_at.to_s,
        locale: user_locale,
      }
    end

    def sms_message
      if SmsLoginOptionPolicy.new(current_user).configured?
        'jobs.sms_otp_sender_job.login_message'
      else
        'jobs.sms_otp_sender_job.verify_message'
      end
    end

    def user_selected_otp_delivery_preference
      delivery_params[:otp_delivery_preference]
    end

    def delivery_params
      params.require(:otp_delivery_selection_form).permit(:otp_delivery_preference, :resend)
    end

    def phone_to_deliver_to
      return current_user.phone if authentication_context?

      user_session[:unconfirmed_phone]
    end

    def user_locale
      available_locales = PhoneVerification::AVAILABLE_LOCALES
      http_accept_language.language_region_compatible_from(available_locales)
    end

    def otp_rate_limiter
      @_otp_rate_limited ||= OtpRateLimiter.new(phone: phone_to_deliver_to,
                                                user: current_user,
                                                phone_confirmed: authentication_context?)
    end
  end
end
