module Idv
  class DocAuth
    class Result
      attr_reader :status

      def self.success
        new(:success)
      end

      def self.failure
        new(:failure)
      end

      def initialize(status)
        @status = status
      end

      def success?
        status == :success
      end

      def failure?
        !success?
      end
    end

    attr_reader :session

    # Order matters
    STEPS = {
      front_image: {
        requires: :front_image,
        handler: :handle_front_image
      },
      back_image: {
        requires: :back_image,
        handler: :handle_back_image
      },
      id_verification_failed: {
        requires: :id_verified,
      },
      id_data_confirmation: {
        requires: :id_data_confirmation,
        handler: :handle_id_data_confirmation
      },
      self_image: {
        requires: :self_image,
        handler: :handle_self_image
      },
      image_verification_failed: {
        requires: :image_verified,
      },
      doc_auth_completed: {
        requires: :doc_auth_confirmation,
        handler: :handle_doc_auth_confirmation
      }
    }.freeze

    def initialize(session)
      @session = session || {}
    end

    def next_step
      # Find the first requirement that is not satisfied
      step, _config = STEPS.detect do |step, config|
        key = config.fetch(:requires)
        !session[key]
      end
      step || :doc_auth_succeeded
    end

    def handle(step, params)
      @session[:error_message] = nil
      handler = STEPS.dig(step.to_sym, :handler)
      return send(handler, params) if handler
      failure("Unhandled step #{step}")
    end

    def completed?
      next_step == :doc_auth_succeeded
    end

    def handle_front_image(params)
      image = params.fetch(:image)

      status, data = create_document
      return failure(data) if status == :error

      @session[:instance_id] = data

      status, data = upload_front_image(image.read)
      return failure(data) if status == :error

      @session[:front_image] = true
      Result.success
    end

    def handle_back_image(params)
      image = params.fetch(:image)

      status, data = upload_back_image(image.read)
      return failure(data) if status == :error

      @session[:back_image] = true

      status, data = verify_document
      return failure(data) if status == :error

      @session[:id_verified] = true
      @session[:id_data] = data

      status, data = get_front_image
      return failure(data) if status == :error
      @session[:front_image_content] = data if data

      status, data = get_back_image
      return failure(data) if status == :error
      @session[:back_image_content] = data if data

      # status, data = assure_id.get_face_image(@session[:instance_id])
      # return failure(data) if status == :error
      # @session[:face_image_content] = data if data

      Result.success
    end

    def handle_id_data_confirmation(_params)
      @session[:id_data_confirmation] = true
      Result.success
    end

    def handle_self_image(params)
      image = params.fetch(:image)

      status, data = verify_image(image.read)
      return failure(data) if status == :error

      @session[:self_image] = true
      @session[:image_verified] = true
      @session[:image_verification_data] = data
      Result.success
    end

    def handle_doc_auth_confirmation
      @session[:doc_auth_confirmation] = true
      Result.success
    end

    def failure(message)
      @session[:error_message] = message
      Result.failure
    end

    def create_document
      assure_id.create_document
    end

    def upload_front_image(image)
      assure_id.post_front_image(@session[:instance_id], image)
    end

    def upload_back_image(image)
      assure_id.post_back_image(@session[:instance_id], image)
    end

    def get_front_image(image)
      assure_id.get_front_image(@session[:instance_id])
    end

    def get_back_image(image)
      assure_id.get_back_image(@session[:instance_id])
    end

    def get_face_image(image)
      assure_id.get_face_image(@session[:instance_id])
    end

    def verify_document
      assure_id.get_results(@session[:instance_id])
    end

    # Obviously not ideal
    def verify_image(self_image)

      status, data = get_face_image
      return failure(data) if status == :error

      Tempfile.open('foo', encoding: 'ascii-8bit') do |f1|
        Tempfile.open('foo', encoding: 'ascii-8bit') do |f2|
          f1.write(data)
          f1.write(self_image)
          facial_match.verify_image(f1, f2)
        end
      end
    end

    def assure_id
      @assure_id ||= Idv::Acuant::AssureId.new
    end

    def facial_match
      @facial_match ||= Idv::Acuant::FacialMatch.new
    end
  end
end