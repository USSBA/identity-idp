require 'rails_helper'

describe Idv::IdvFailurePresenter do
  let(:decorated_session) { mock_decorated_session }
  let(:view_context) { mock_view_context }
  let(:presenter) { described_class.new(view_context: view_context) }

  describe 'it uses the :locked failure state' do
    subject { presenter.state }

    it { is_expected.to eq(:locked) }
  end

  context 'methods are overriden' do
    %i[message title header description].each do |method|
      describe "##{method}" do
        subject { presenter.send(method) }

        it { is_expected.to_not be_nil }
      end
    end
  end

  describe '#title' do
    subject { presenter.send(:title) }

    it 'includes the app name' do
      expect(subject).to include('login.gov')
    end
  end

  describe '#header' do
    subject { presenter.send(:header) }

    it 'includes the app name' do
      expect(subject).to include('login.gov')
    end
  end

  describe '#description' do
    subject { presenter.send(:description) }

    it 'includes the lockout window' do
      expect(subject).to include(Figaro.env.idv_attempt_window_in_hours)
    end
  end

  describe '#next_steps' do
    subject { presenter.next_steps }

    it 'includes `help_step`, `sp_step`, and `profile_step`' do
      expect(subject).to eq(
        [
          presenter.send(:help_step),
          presenter.send(:sp_step),
          presenter.send(:profile_step),
        ]
      )
    end
  end

  describe '#help_step' do
    subject { presenter.send(:help_step) }

    it 'includes help url' do
      expect(subject).to include(MarketingSite.help_url)
    end
  end

  describe '#sp_step' do
    subject { presenter.send(:sp_step) }

    it 'includes sp url' do
      expect(subject).to include(decorated_session.sp_return_url)
    end
  end

  describe '#profile_step' do
    subject { presenter.send(:profile_step) }

    it 'includes profile url' do
      expect(subject).to include(view_context.account_path)
    end
  end

  def mock_view_context
    view_context = ActionView::Base.new
    allow(view_context).to receive(:account_path).and_return('Account Path')
    allow(view_context).to receive(:decorated_session).and_return(mock_decorated_session)
    view_context
  end

  def mock_decorated_session
    decorated_session = instance_double(SessionDecorator)
    allow(decorated_session).to receive(:sp_name).and_return('Test SP')
    allow(decorated_session).to receive(:sp_return_url).and_return('SP Link')
    decorated_session
  end
end
