# frozen_string_literal: true

require "httparty"

module CodeRunners
  class RunnerService
    def run(code, language, input, _time_limit, _memory_limit)
      runner_url = ENV.fetch("RUNNER_URL", "http://runner:5000/run")

      payload = { code: code, language: language, stdin: input }

      # noinspection RubyArgCount
      response = HTTParty.post(
        runner_url,
        body: payload.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 10
      )

      JSON.parse(response.body, symbolize_names: true)
    rescue => e
      Rails.logger.error "[RunnerService] #{e.message}\n#{Array(e.backtrace).join("\n")}"
      { output: "", time: 0, memory: 0, status: "Service Error", error_message: e.message }
    end
  end
end
