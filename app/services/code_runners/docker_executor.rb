# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require "securerandom"

module CodeRunners
  class DockerExecutor
    def run_all_tests_in_docker(code, language, test_cases, time_limit, memory_limit)
      submission_id = SecureRandom.uuid
      temp_dir = "/tmp/#{submission_id}"
      code_file_name = get_code_file_name(language)
      executable_file_name = get_executable_file_name(language)
      docker_image = get_docker_image(language)

      FileUtils.mkdir_p(temp_dir)
      File.write("#{temp_dir}/#{code_file_name}", code)
      File.write("#{temp_dir}/test_cases.json", test_cases.to_json)
      File.write("#{temp_dir}/run_script.sh", generate_run_script(language, code_file_name, executable_file_name, time_limit.to_f))
      FileUtils.chmod("+x", "#{temp_dir}/run_script.sh")

      docker_command = [
        "docker run --rm -i",
        "--network none",
        "--memory #{memory_limit}m",
        "--pids-limit 64",
        "--ulimit nproc=64:64",
        "--ulimit nofile=1024:1024",
        "--cpus=1.0",
        "-v #{temp_dir}:/app",
        docker_image,
        "/app/run_script.sh"
      ].join(" ")

      stdout, stderr, status = Open3.capture3(docker_command)

      Rails.logger.debug "[DockerExecutor] STDOUT:\n#{stdout}"
      Rails.logger.debug "[DockerExecutor] STDERR:\n#{stderr}"

      FileUtils.remove_entry_secure(temp_dir) rescue nil

      parse_overall_results(stdout, stderr, status, test_cases)
    rescue => e
      Rails.logger.error "[DockerExecutor] Exception: #{e.message}\n#{e.backtrace.join("\n")}"
      test_cases.map.with_index(1) do |tc, i|
        {
          test_case_number: i,
          input: tc[:input],
          expected_output: tc[:expected_output],
          output: "",
          time: 0,
          memory: 0,
          status: "Internal Error",
          error_message: e.message,
          passed: false
        }
      end
    end

    private

    def get_code_file_name(lang)
      { "python" => "solution.py", "java" => "Solution.java", "cpp" => "solution.cpp", "ruby" => "solution.rb" }[lang] || "solution.txt"
    end

    def get_executable_file_name(lang)
      { "java" => "Solution", "cpp" => "a.out" }[lang] || get_code_file_name(lang)
    end

    def get_docker_image(lang)
      {
        "python" => "my-python-executor",
        "java"   => "openjdk:11-jre-slim-buster",
        "cpp"    => "my-cpp-executor:12",
        "ruby"   => "ruby:3.0-slim-buster"
      }[lang] || "my-cpp-executor:12"
    end

    def generate_run_script(lang, code_file, exec_file, time_limit)
      <<~BASH
        #!/bin/bash
        set -euo pipefail
        cd /app

        # Compile
        if [ "#{lang}" = "java" ]; then
          javac #{code_file} && echo "JUDGE_COMPILED_OK" || { echo "JUDGE_COMPILATION_ERROR: $(javac #{code_file} 2>&1)"; echo "JUDGE_RESULTS_END"; exit 0; }
        elif [ "#{lang}" = "cpp" ]; then
          g++ -O2 -static -DONLINE_JUDGE -lm -s -x c++ #{code_file} -o #{exec_file} 2>&1 | head -20 > compile.log
          if [ $? -ne 0 ]; then
            echo "JUDGE_COMPILATION_ERROR: $(cat compile.log)"
            echo "JUDGE_RESULTS_END"
            exit 0
          fi
        fi

        echo "JUDGE_RESULTS_START"

        # Xử lý test case
        jq -c '.[]' test_cases.json | while IFS= read -r testcase; do
          echo "$testcase" | jq -r '.input' > input.txt
          expected=$(echo "$testcase" | jq -r '.expected_output')

          START=$(date +%s.%N)
          
          case "#{lang}" in
            cpp)   timeout #{time_limit}s ./#{exec_file} < input.txt > output.txt 2> stderr.txt ;;
            python)timeout #{time_limit}s python #{code_file} < input.txt > output.txt 2> stderr.txt ;;
            java)  timeout #{time_limit}s java #{exec_file} < input.txt > output.txt 2> stderr.txt ;;
            ruby)  timeout #{time_limit}s ruby #{code_file} < input.txt > output.txt 2> stderr.txt ;;
          esac
          exit_code=$?
          END=$(date +%s.%N)

          output=$(cat output.txt 2>/dev/null || echo "")
          stderr=$(cat stderr.txt 2>/dev/null || echo "")
          time_used=$(echo "scale=3; $END - $START" | bc -l | awk '{printf "%.3f", $0}')
          [[ "$time_used" == "."* ]] && time_used="0$time_used"
          [ -z "$time_used" ] && time_used="0.000"

          if [ $exit_code -eq 124 ]; then
            status="Time Limit Exceeded"
          elif [ $exit_code -ne 0 ]; then
            status="Runtime Error"
          else
            status="Success"
          fi

          # result
          printf 'JUDGE_TEST_CASE_RESULT: {"input":%s,"expected_output":%s,"output":%s,"stderr":%s,"status":"%s","time":%s,"memory":0}\\n' \
            "$(jq -Rs . input.txt)" \
            \
            "$(printf '%s' "$expected" | jq -Rs .)" \
            "$(printf '%s' "$output" | jq -Rs .)"    \
            "$(printf '%s' "$stderr" | jq -Rs .)"    \
            "$status" \
            "$time_used"
        done

        echo "JUDGE_RESULTS_END"
      BASH
    end
    

    def parse_overall_results(stdout, docker_stderr, status, original_test_cases)
      results = []
      compilation_error = nil

      stdout.each_line do |line|
        line = line.chomp
        next if line.empty?

        case line
        when /^JUDGE_COMPILATION_ERROR:/
          compilation_error = line.sub(/^JUDGE_COMPILATION_ERROR:\s*/, "").strip
        when /^JUDGE_TEST_CASE_RESULT:\s*(.+)/
          json_str = Regexp.last_match(1)
          begin
            data = JSON.parse(json_str)
            passed = data["status"] == "Success" && data["output"].strip == data["expected_output"].strip
            results << {
              input: data["input"],
              expected_output: data["expected_output"],
              output: data["output"],
              time: data["time"].to_f,
              memory: data["memory"],
              status: data["status"],
              error_message: data["stderr"].presence || (data["status"] != "Success" ? data["status"] : nil),
              passed: passed
            }
          rescue => e
            Rails.logger.error "JSON parse error: #{e.message} | line: #{line}"
          end
        end
      end

      if results.any?
        results.each_with_index { |r, i| r[:test_case_number] = i + 1 }
        return results
      end

      # Không có kết quả → lỗi biên dịch hoặc lỗi hệ thống
      status_str = compilation_error ? "Compilation Error" : "Internal Error"
      msg = compilation_error || docker_stderr.presence || "Unknown error"

      original_test_cases.map.with_index(1) do |tc, i|
        {
          test_case_number: i,
          input: tc[:input],
          expected_output: tc[:expected_output],
          output: "",
          time: 0,
          memory: 0,
          status: status_str,
          error_message: msg,
          passed: false
        }
      end
    end
  end
end
