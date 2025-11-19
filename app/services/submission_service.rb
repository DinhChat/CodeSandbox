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
    runner = select_runner
    results = runner.run_all_tests_in_docker(@code, @language, @test_cases, @time_limit, @memory_limit)

    results.each_with_index do |result, index|
      result[:test_case_number] = index + 1 unless result.key?(:test_case_number)
      result[:input] = @test_cases[index][:input] if @test_cases[index] && !result.key?(:input)
      result[:expected_output] = @test_cases[index][:expected_output] if @test_cases[index] && !result.key?(:expected_output)
      result[:passed] = !!result[:passed]
    end

    results
  end

  private

  def validate_params!
    raise InvalidParamsError, "Submission code is required" if @code.blank?
    raise InvalidParamsError, "Language is required" if @language.blank?
    raise InvalidParamsError, "Test cases are required" if @test_cases.blank?
    raise InvalidParamsError, "Test cases must be an array" unless @test_cases.is_a?(Array)
    @test_cases.each_with_index do |tc, i|
      raise InvalidParamsError, "Test case #{i+1} must have input" if tc[:input].blank?
      raise InvalidParamsError, "Test case #{i+1} must have expected_output" if tc[:expected_output].blank?
    end
  end

  def select_runner
    CodeRunners::DockerExecutor.new
  end
end
