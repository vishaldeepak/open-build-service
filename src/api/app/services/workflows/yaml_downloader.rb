module Workflows
  class YAMLDownloader
    MAX_FILE_SIZE = 1024 * 1024 # 1MB

    attr_reader :errors

    def initialize(scm_payload)
      @scm_payload = scm_payload
      @errors = []
    end

    def call
      download_yaml_file
    end

    private

    def download_yaml_file
      Down.download(download_url, max_size: MAX_FILE_SIZE)
    rescue Down::Error => e
      @errors << e.message
      nil
    end

    def download_url
      case @scm_payload[:scm]
      when 'github'
        "https://raw.githubusercontent.com/#{@scm_payload[:target_repository_full_name]}/#{@scm_payload[:target_branch]}/.obs/workflows.yml"
      when 'gitlab'
        "https://gitlab.com/#{@scm_payload[:path_with_namespace]}/-/raw/#{@scm_payload[:target_branch]}/.obs/workflows.yml"
      end
    end
  end
end
