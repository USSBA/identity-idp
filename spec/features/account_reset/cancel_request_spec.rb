require 'rails_helper'

describe 'Account Reset Request: Cancellation' do
  context 'user cancels right away from the first email' do
    it 'cancels the request and does not delete the user', email: true do
      TwilioService::Utils.telephony_service = FakeSms
      user = create(:user, :signed_up)
      signin(user.email, user.password)
      click_link t('two_factor_authentication.login_options_link_text')
      click_link t('devise.two_factor_authentication.account_reset.link')
      click_button t('account_reset.request.yes_continue')
      open_last_email
      click_email_link_matching(/cancel\?token/)

      expect(page).to have_current_path new_user_session_path
      expect(page).
        to have_content t('devise.two_factor_authentication.account_reset.successful_cancel')

      signin(user.email, user.password)

      expect(page).
        to have_current_path login_two_factor_path(otp_delivery_preference: 'sms', reauthn: 'false')
    end
  end

  context 'user cancels from the second email after the request has been granted' do
    it 'cancels the request and does not delete the user', email: true do
      TwilioService::Utils.telephony_service = FakeSms
      user = create(:user, :signed_up)
      signin(user.email, user.password)
      click_link t('two_factor_authentication.login_options_link_text')
      click_link t('devise.two_factor_authentication.account_reset.link')
      click_button t('account_reset.request.yes_continue')
      reset_email

      Timecop.travel(Time.zone.now + 2.days) do
        AccountResetService.grant_tokens_and_send_notifications
        open_last_email
        click_email_link_matching(/cancel\?token/)

        expect(page).to have_current_path new_user_session_path
        expect(page).
          to have_content t('devise.two_factor_authentication.account_reset.successful_cancel')

        signin(user.email, user.password)

        expect(page).
          to have_current_path(
            login_two_factor_path(otp_delivery_preference: 'sms', reauthn: 'false')
          )
      end
    end
  end
end
