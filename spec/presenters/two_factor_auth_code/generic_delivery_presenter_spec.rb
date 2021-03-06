require 'rails_helper'

describe TwoFactorAuthCode::GenericDeliveryPresenter do
  include Rails.application.routes.url_helpers

  it 'is an abstract presenter with methods that should be implemented' do
    presenter = presenter_with

    %w[header help_text fallback_links].each do |m|
      expect { presenter.send(m.to_sym) }.to raise_error(NotImplementedError)
    end
  end

  describe '#piv_cac_option' do
    context 'for a user without a piv/cac enabled' do
      let(:presenter) { presenter_with(has_piv_cac_configured: false) }

      it 'returns nothing' do
        expect(presenter.send(:piv_cac_option)).to be_nil
      end
    end

    context 'for a user with a piv/cac enabled' do
      let(:presenter) { presenter_with(has_piv_cac_configured: true) }

      it 'returns a link to the piv/cac option' do
        expect(presenter.send(:piv_cac_option)).to eq t(
          'devise.two_factor_authentication.piv_cac_fallback.text_html',
          link: presenter.send(:piv_cac_link)
        )
      end
    end
  end

  describe '#piv_cac_link' do
    context 'for a user without a piv/cac enabled' do
      let(:presenter) { presenter_with(has_piv_cac_configured: false) }

      it 'returns nothing' do
        expect(presenter.send(:piv_cac_link)).to be_nil
      end
    end

    context 'for a user with a piv/cac enabled' do
      let(:presenter) { presenter_with(has_piv_cac_configured: true) }

      it 'returns a link to the piv/cac option' do
        expect(presenter.send(:piv_cac_link)).to eq ActionController::Base.new.view_context.link_to(
          t('devise.two_factor_authentication.piv_cac_fallback.link'),
          login_two_factor_piv_cac_path(locale: LinkLocaleResolver.locale)
        )
      end
    end
  end

  def presenter_with(arguments = {}, view = ActionController::Base.new.view_context)
    TwoFactorAuthCode::GenericDeliveryPresenter.new(data: arguments, view: view)
  end
end
