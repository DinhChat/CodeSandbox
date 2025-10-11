# frozen_string_literal: true

class SubmissionResultSerializer
  def initialize(result)
    @result = result
  end

  def as_json
    {
      test_case_number: @result[:test_case_number],
      input: @result[:input],
      expected_output: @result[:expected_output],
      actual_output: @result[:output],
      time_taken: @result[:time],
      memory_used: @result[:memory],
      status: @result[:status],
      passed: @result[:passed]
    }
  end
end
