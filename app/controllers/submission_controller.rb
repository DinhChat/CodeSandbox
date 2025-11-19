# frozen_string_literal: true

require "open3"
require "httparty"

class SubmissionController < ApplicationController
  wrap_parameters false
  # POST /submissions/run
  def run
    service = SubmissionService.new(submission_params)
    results = service.run_all_tests

    total_test_cases = results.length
    passed_test_cases = results.count { |r| r[:passed] }
    all_passed = passed_test_cases == total_test_cases
    # find error
    compilation_error = results.find { |r| r[:status] == "Compilation Error" }&.dig(:error_message)

    render json: {
      meta: {
        total_test_cases: total_test_cases,
        passed_test_cases: passed_test_cases,
        all_passed: all_passed,
        compilation_error: compilation_error
      },
      results: results.map { |r| SubmissionResultSerializer.new(r).as_json }
    }, status: :ok
  rescue SubmissionService::InvalidParamsError => e
    render json: { error: e.message }, status: :bad_request
  rescue => e
    Rails.logger.error "Error processing submission: #{e.message}\n#{Array(e.backtrace).join("\n")}"
    render json: { error: "Internal server error", message: e.message }, status: :internal_server_error
  end

  private

  def submission_params
    params.permit(:submission_code, :language, :time_limit, :memory_limit, test_cases: %i[input expected_output])
  end
end

