# frozen_string_literal: true

class SubmissionService
  class InvalidParamsError < StandardError; end

  def initialize(params)
    @code = params[:submission_code]
    @language = params[:language]
    @test_cases = params[:test_cases]
    @time_limit = (params[:time_limit] || 2).to_i
    @memory_limit = (params[:memory_limit] || 256).to_i

    validate_params!
  end

  def run_all_tests
    results = []
    @test_cases.each_with_index do |test_case, index|
      Rails.logger.info "Running test case #{index + 1} for language #{@language}"

      runner = select_runner
      result = runner.run(@code, @language, test_case[:input], @time_limit, @memory_limit)

      passed = result[:output].strip == test_case[:expected_output].strip

      results << result.merge(
        test_case_number: index + 1,
        input: test_case[:input],
        expected_output: test_case[:expected_output],
        passed: passed
      )
    end
    results
  end

  private

  def validate_params!
    if @code.blank? || @language.blank? || @test_cases.blank?
      raise InvalidParamsError, "Missing required parameters"
    end
  end

  def select_runner
    if ENV["USE_DOCKER_RUNNER"] == "true"
      CodeRunners::DockerExecutor.new
    else
      CodeRunners::RunnerService.new
    end
  end
end
