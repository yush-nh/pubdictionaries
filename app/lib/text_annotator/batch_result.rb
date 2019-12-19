require 'fileutils'
require 'json'

class TextAnnotator
  class BatchResult
    PATH = "tmp/annotations/"

    attr_reader :filename, :job_id

    class << self
      def older_files(duration)
        to_delete = []
        Dir.foreach(PATH) do |filename|
          next if filename == '.' || filename == '..'
          filepath = to_path(filename)
          to_delete << filepath if Time.now - File.mtime(filepath) > duration
        end
        to_delete
      end

      def to_path(filename)
        PATH + filename
      end
    end

    def initialize(filename = nil, job_id = nil)
      @filename = if filename
        filename =~ /^annotation-(.+)\.json$/
        @job_id = $1
        filename
      elsif job_id
        @job_id = job_id
        "annotation-#{job_id}.json"
      else
        raise ArgumentError, "Either filename or job_id has to be specified."
      end
    end

    def save!(result)
      File.write(file_path, JSON.generate(result))
    end

    def status
      if complete?
        if success?
          :success
        else
          :error
        end
      else
        :not_found
      end
    end

    def file_path
      @filepath ||= self.class.to_path(filename)
    end

    private

    def setup_directory
      unless File.directory?(PATH)
        FileUtils.mkdir_p(PATH)
      end
    end

    def complete?
      File.exist?(file_path)
    end

    def success?
      annotations

      if annotations.class == Array
        annotations.first.has_key?(:text)
      else
        annotations.has_key?(:text)
      end
    end

    def annotations
      @annotations ||= JSON.parse(File.read(file_path), symbolize_names: true)
    end
  end
end