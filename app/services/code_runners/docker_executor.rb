# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module CodeRunners
  class DockerExecutor
    def run(code, language, input, time_limit, memory_limit)
      submission_id = SecureRandom.uuid
      temp_dir = "/tmp/#{submission_id}"
      code_file_name = get_code_file_name(language)
      executable_file_name = get_executable_file_name(language)
      docker_image = get_docker_image(language)

      FileUtils.mkdir_p(temp_dir)
      File.write("#{temp_dir}/#{code_file_name}", code)
      File.write("#{temp_dir}/input.txt", input)
      File.write("#{temp_dir}/run_script.sh", generate_run_script(language, code_file_name, executable_file_name))
      FileUtils.chmod("+x", "#{temp_dir}/run_script.sh")

      docker_command = [
        "docker run",
        "-i --rm",
        "--network none",
        "--memory #{memory_limit}m",
        "--pids-limit 64",
        "--ulimit nproc=64:64",
        "--ulimit nofile=1024:1024",
        "--cpus=\"1.0\"",
        "-v #{temp_dir}:/app",
        docker_image,
        "timeout #{time_limit}s /app/run_script.sh"
      ].join(" ")

      stdout, stderr, status = Open3.capture3(docker_command)
      output, metrics = parse_output(stdout)

      FileUtils.remove_entry(temp_dir)

      {
        output: output,
        time: metrics[:time],
        memory: metrics[:memory],
        status: determine_status(status, stderr),
        error_message: stderr
      }
    rescue => e
      Rails.logger.error "[DockerExecutor] #{e.message}\n#{Array(e.backtrace).join("\n")}"
      { output: "", time: 0, memory: 0, status: "Internal Error", error_message: e.message }
    end

    private

    def get_code_file_name(lang)
      { "python" => "solution.py", "java" => "Solution.java", "cpp" => "solution.cpp", "ruby" => "solution.rb" }[lang] || "solution.txt"
    end

    def get_executable_file_name(lang)
      { "java" => "Solution", "cpp" => "a.out" }[lang] || get_code_file_name(lang)
    end

    def get_docker_image(lang)
      { "python" => "python:3.9-slim-buster", "java" => "openjdk:11-jre-slim-buster", "cpp" => "gcc:9-slim", "ruby" => "ruby:3.0-slim-buster" }[lang] || "alpine/base"
    end

    def generate_run_script(lang, code_file, exec_file)
      script = <<~BASH
        #!/bin/bash
        cd /app
        start_time=$(date +%s.%N)

        case "#{lang}" in
          python) python #{code_file} < input.txt ;;
          java)
            javac #{code_file} 2> compile_error.txt
            if [ $? -ne 0 ]; then cat compile_error.txt; exit 1; fi
            java #{exec_file} < input.txt ;;
          cpp)
            g++ #{code_file} -o #{exec_file} 2> compile_error.txt
            if [ $? -ne 0 ]; then cat compile_error.txt; exit 1; fi
            ./#{exec_file} < input.txt ;;
          ruby) ruby #{code_file} < input.txt ;;
          *) echo "Unsupported language: #{lang}"; exit 1 ;;
        esac

        end_time=$(date +%s.%N)
        time_taken=$(echo "$end_time - $start_time" | bc -l)
        echo "JUDGE_METRICS: {\\\"time\\\": $time_taken, \\\"memory\\\": 0}"
      BASH
      script
    end

    def parse_output(stdout)
      lines = stdout.split("\n")
      metrics_line = lines.find { |l| l.start_with?("JUDGE_METRICS:") }
      metrics = metrics_line ? JSON.parse(metrics_line.sub("JUDGE_METRICS:", "")).symbolize_keys : { time: 0, memory: 0 }
      output = (lines - [ metrics_line ]).join("\n").strip
      [ output, metrics ]
    end

    def determine_status(status, stderr)
      return "Success" if status.success?
      return "Time Limit Exceeded" if status.exitstatus == 124
      return "Memory Limit Exceeded" if stderr.include?("Memory limit exceeded")

      "Runtime Error"
    end
  end
end
